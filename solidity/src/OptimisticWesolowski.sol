// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibBigInt as B} from "./LibBigInt.sol";
import {LibClassGroupBig as CG} from "./LibClassGroupBig.sol";
import {LibWesolowskiBig as W} from "./LibWesolowskiBig.sol";

/// @title Optimisticka (fraud-proof) Wesolowski verifikacija.
/// @notice Umesto 57M on-chain: prover objavi hash checkpoint-a svakog
///         segmenta NAF petlje + bond. Srecan put = ~0,4M. Bilo ko moze da
///         ospori TACNO JEDAN segment: ugovor ga re-izvrsi (~8M) i pri
///         neslaganju dodeli bond izazivacu. Ideja ostaje netaknuta —
///         klasna grupa radi ceo timelock, lanac moze punu presudu.
contract OptimisticWesolowski {
    uint256 public constant SEG_BITS = 10;
    uint256 public constant WINDOW = 100; // blokova za osporavanje

    struct Claim {
        address prover;
        uint96 bond;
        uint64 deadline;
        bool finalized;
        bool invalid;
        uint16 topPos;
        uint16 nSeg;
        uint256 P1; uint256 N1; uint256 P2; uint256 N2;
        bytes32 bind; // keccak(u, pi, T) — ulazi se ponovo salju u challenge
        bytes32[] cps; // checkpoint hesovi: cps[0]=init acc, cps[nSeg]=reduce(w)
    }
    mapping(bytes32 => Claim) internal claims;

    function status(bytes32 id) external view returns (bool finalized, bool invalid, uint64 deadline) {
        Claim storage c = claims[id];
        return (c.finalized, c.invalid, c.deadline);
    }

    /// @notice srecan put: samo Fiat-Shamir + hash provere + skladistenje
    function claimVerified(
        CG.Form memory u, CG.Form memory w, CG.Form memory pi,
        uint256 T, B.Int memory D, bytes32[] calldata cps
    ) external payable returns (bytes32 id) {
        id = keccak256(abi.encode(u, w, pi, T, cps));
        Claim storage c = claims[id];
        require(c.prover == address(0), "exists");
        uint256 l = W.fiatShamirPrime(u, w, T, D);
        uint256 r = W.powmod(2, T, l);
        (uint256 P1, uint256 N1) = CG._naf(l);
        (uint256 P2, uint256 N2) = CG._naf(r);
        uint256 all = P1 | N1 | P2 | N2;
        uint256 top = 255;
        while (all & (uint256(1) << top) == 0) top--;
        uint256 nSeg = (top + SEG_BITS - 1) / SEG_BITS;
        require(cps.length == nSeg + 1, "cps len");
        // finalni checkpoint MORA biti reduce(w) — nema posebnog izazova za kraj
        require(cps[nSeg] == keccak256(abi.encode(CG.reduce(w))), "final cp");
        c.prover = msg.sender;
        c.bond = uint96(msg.value);
        c.deadline = uint64(block.number + WINDOW);
        c.topPos = uint16(top);
        c.nSeg = uint16(nSeg);
        c.P1 = P1; c.N1 = N1; c.P2 = P2; c.N2 = N2;
        c.bind = keccak256(abi.encode(u, pi, T));
        c.cps = cps;
    }

    /// @notice ospori segment i (1..nSeg) dostavljanjem preimage-a cps[i-1];
    ///         segment 0 (init) se osporava sa i == 0 bez preimage-a.
    function challenge(
        bytes32 id, uint256 i,
        bytes calldata accPrevEnc,
        CG.Form memory u, CG.Form memory pi, uint256 T, B.Int memory D
    ) external {
        Claim storage c = claims[id];
        require(c.prover != address(0) && !c.finalized && !c.invalid, "bad claim");
        require(block.number <= c.deadline, "window over");
        require(keccak256(abi.encode(u, pi, T)) == c.bind, "inputs mismatch");
        CG.Form memory t12 = CG.nucompCompact(pi, u, D);
        CG.Form memory t1m2 = CG.nucompCompact(pi, CG.inverse(u), D);
        bytes32 got;
        if (i == 0) {
            got = keccak256(abi.encode(
                _tab(pi, u, t12, t1m2, c.P1, c.N1, c.P2, c.N2, uint256(1) << c.topPos)
            ));
        } else {
            require(i <= c.nSeg, "seg idx");
            require(keccak256(accPrevEnc) == c.cps[i - 1], "prev preimage");
            CG.Form memory acc = abi.decode(accPrevEnc, (CG.Form));
            uint256 pos = uint256(c.topPos) - (i - 1) * SEG_BITS;
            uint256 n = pos < SEG_BITS ? pos : SEG_BITS;
            uint256 all = c.P1 | c.N1 | c.P2 | c.N2;
            while (n > 0) {
                pos--;
                n--;
                acc = CG.squareCompact(acc, D);
                uint256 bit = uint256(1) << pos;
                if (all & bit != 0) {
                    acc = CG.nucompCompact(acc, _tab(pi, u, t12, t1m2, c.P1, c.N1, c.P2, c.N2, bit), D);
                }
            }
            got = keccak256(abi.encode(acc));
        }
        if (got != c.cps[i]) {
            c.invalid = true; // prevara dokazana — bond izazivacu
            uint256 bond = c.bond;
            c.bond = 0;
            (bool okT, ) = msg.sender.call{value: bond}("");
            require(okT, "bond xfer");
        } else {
            revert("segment ok"); // izazov nad ispravnim segmentom ne menja stanje
        }
    }

    function finalize(bytes32 id) external {
        Claim storage c = claims[id];
        require(c.prover != address(0) && !c.invalid && !c.finalized, "bad claim");
        require(block.number > c.deadline, "window open");
        c.finalized = true;
        uint256 bond = c.bond;
        c.bond = 0;
        (bool okT, ) = c.prover.call{value: bond}("");
        require(okT, "bond back");
    }

    function _tab(
        CG.Form memory f1, CG.Form memory f2,
        CG.Form memory t12, CG.Form memory t1m2,
        uint256 P1, uint256 N1, uint256 P2, uint256 N2, uint256 bit
    ) private pure returns (CG.Form memory) {
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
        return CG.inverse(t12); // idx == 0; idx == 4 se nikad ne trazi
    }
}
