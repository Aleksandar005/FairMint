// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {console2} from "forge-std/Test.sol";
import {LibBigInt as B} from "../src/LibBigInt.sol";
import {LibClassGroupBig as CG} from "../src/LibClassGroupBig.sol";
import {LibWesolowskiBig as W} from "../src/LibWesolowskiBig.sol";
import {OptimisticWesolowski as OW} from "../src/OptimisticWesolowski.sol";
import {WesolowskiE2E} from "./WesolowskiE2E.t.sol";

contract OptimisticWesolowskiTest is WesolowskiE2E {
    receive() external payable {}

    function _ctx() internal view returns (uint256[6] memory c) {
        uint256 l = W.fiatShamirPrime(U_(), Wf_(), T_, D_());
        (c[0], c[1]) = CG._naf(l);
        (c[2], c[3]) = CG._naf(W.powmod(2, T_, l));
        c[4] = c[0] | c[1] | c[2] | c[3];
        uint256 top = 255;
        while (c[4] & (uint256(1) << top) == 0) top--;
        c[5] = top;
    }

    // prover strana: izracunaj checkpoint hesove istim rasporedom kao ugovor
    function _forms() internal view returns (CG.Form[4] memory fs) {
        fs[0] = PI_();
        fs[1] = U_();
        fs[2] = CG.nucompCompact(fs[0], fs[1], D_());
        fs[3] = CG.nucompCompact(fs[0], CG.inverse(fs[1]), D_());
    }
    function _tab2(CG.Form[4] memory fs, uint256[6] memory c, uint256 bit)
        internal pure returns (CG.Form memory)
    {
        return _tabT(fs[0], fs[1], fs[2], fs[3], c[0], c[1], c[2], c[3], bit);
    }

    function _tabT(CG.Form memory f1, CG.Form memory f2, CG.Form memory t12, CG.Form memory t1m2,
        uint256 P1, uint256 N1, uint256 P2, uint256 N2, uint256 bit) internal pure returns (CG.Form memory) {
        uint256 d1 = P1 & bit != 0 ? 2 : (N1 & bit != 0 ? 0 : 1);
        uint256 d2 = P2 & bit != 0 ? 2 : (N2 & bit != 0 ? 0 : 1);
        uint256 idx = d1 * 3 + d2;
        if (idx == 8) return t12;
        if (idx == 7) return f1;
        if (idx == 6) return t1m2;
        if (idx == 5) return f2;
        if (idx == 3) return CG.inverse(f2);
        if (idx == 2) return CG.inverse(t1m2);
        if (idx == 1) return CG.inverse(f1);
        return CG.inverse(t12);
    }

    function _checkpoints(bool corruptSeg3) internal view returns (bytes32[] memory cps) {
        B.Int memory d = D_();
        uint256[6] memory c = _ctx();
        CG.Form[4] memory fs = _forms();
        uint256 nSeg = (c[5] + 9) / 10;
        cps = new bytes32[](nSeg + 1);
        CG.Form memory acc = _tab2(fs, c, uint256(1) << c[5]);
        cps[0] = keccak256(abi.encode(acc));
        uint256 pos = c[5];
        for (uint256 i = 1; i <= nSeg; i++) {
            uint256 n = pos < 10 ? pos : 10;
            while (n > 0) {
                pos--; n--;
                acc = CG.squareCompact(acc, d);
                if (c[4] & (uint256(1) << pos) != 0) {
                    acc = CG.nucompCompact(acc, _tab2(fs, c, uint256(1) << pos), d);
                }
            }
            cps[i] = keccak256(abi.encode(acc));
            if (corruptSeg3 && i == 3) cps[i] = bytes32(uint256(cps[i]) ^ 1);
        }
    }
    function _accAt(uint256 segIdx) internal view returns (bytes memory) {
        B.Int memory d = D_();
        uint256[6] memory c = _ctx();
        CG.Form[4] memory fs = _forms();
        CG.Form memory acc = _tab2(fs, c, uint256(1) << c[5]);
        uint256 pos = c[5];
        for (uint256 i = 1; i <= segIdx; i++) {
            uint256 n = pos < 10 ? pos : 10;
            while (n > 0) {
                pos--; n--;
                acc = CG.squareCompact(acc, d);
                if (c[4] & (uint256(1) << pos) != 0) {
                    acc = CG.nucompCompact(acc, _tab2(fs, c, uint256(1) << pos), d);
                }
            }
        }
        return abi.encode(acc);
    }

    function test_HappyPathGas() public {
        OW v = new OW();
        bytes32[] memory cps = _checkpoints(false);
        uint256 g0 = gasleft();
        bytes32 id = v.claimVerified{value: 1 ether}(U_(), Wf_(), PI_(), T_, D_(), cps);
        console2.log("OPTIMISTIC claim gas:", g0 - gasleft());
        vm.roll(block.number + 101);
        g0 = gasleft();
        v.finalize(id);
        console2.log("OPTIMISTIC finalize gas:", g0 - gasleft());
        (bool fin, bool inv, ) = v.status(id);
        require(fin && !inv, "not finalized valid");
    }

    function test_FraudCaughtOnExactSegment() public {
        OW v = new OW();
        bytes32[] memory cps = _checkpoints(true); // pokvaren cps[3]
        bytes32 id = v.claimVerified{value: 1 ether}(U_(), Wf_(), PI_(), T_, D_(), cps);
        bytes memory prev = _accAt(2);
        uint256 g0 = gasleft();
        v.challenge(id, 3, prev, U_(), PI_(), T_, D_());
        console2.log("OPTIMISTIC challenge gas:", g0 - gasleft());
        (, bool inv, ) = v.status(id);
        require(inv, "fraud not caught");
    }

    function test_HonestSegmentSurvivesChallenge() public {
        OW v = new OW();
        bytes32[] memory cps = _checkpoints(false);
        bytes32 id = v.claimVerified{value: 1 ether}(U_(), Wf_(), PI_(), T_, D_(), cps);
        bytes memory prev = _accAt(2);
        vm.expectRevert(bytes("segment ok"));
        v.challenge(id, 3, prev, U_(), PI_(), T_, D_());
    }
}
