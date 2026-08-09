// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test, console2} from "forge-std/Test.sol";
import {LibBigInt as B} from "../src/LibBigInt.sol";
import {LibClassGroupBig as CG} from "../src/LibClassGroupBig.sol";
import {LibClassGroupBigTest} from "./LibClassGroupBig.t.sol";

/// Diferencijal: shamir(f1,e1,f2,e2) mora biti identican
/// compose(pow(f1,e1), pow(f2,e2)) — nezavisna referentna staza.
contract ShamirBig is LibClassGroupBigTest {
    function _ref(CG.Form memory f1, uint256 e1, CG.Form memory f2, uint256 e2, B.Int memory d)
        private pure returns (CG.Form memory)
    {
        return CG.compose(CG.pow(f1, e1, d), CG.pow(f2, e2, d), d);
    }

    function test_ShamirMatchesNaive_Small() public view {
        // 16-bitni eksponenti pokrivaju iste kodne staze (tabela, parovi bitova
        // 11/10/01, sve tri inicijalizacije, e=0/1 ivice) uz 1/5 cene
        B.Int memory d = D();
        CG.Form memory f1 = G();
        for (uint256 i = 0; i < 8; i++) f1 = CG.squareCompact(f1, d);
        CG.Form memory f2 = CG.squareCompact(f1, d);
        uint256 d1 = (uint256(keccak256("e1")) & 0xFFFF) | 0x8001;
        uint256 d2 = (uint256(keccak256("e2")) & 0xFFFF) | 0x8000;
        uint256[2][6] memory cases = [
            [d1, d2],
            [uint256(1), d2],
            [d1, uint256(1)],
            [uint256(0), d2],
            [d1, uint256(0)],
            [uint256(1) << 15, uint256(3)]
        ];
        for (uint256 k = 0; k < 6; k++) {
            CG.Form memory got = CG.shamir(f1, cases[k][0], f2, cases[k][1], d);
            CG.Form memory want = _ref(f1, cases[k][0], f2, cases[k][1], d);
            require(CG.eq(got, want), "shamir != naive");
        }
    }

    function test_ShamirMatchesNaive_80bit() public view {
        B.Int memory d = D();
        CG.Form memory f1 = G();
        for (uint256 i = 0; i < 8; i++) f1 = CG.squareCompact(f1, d);
        CG.Form memory f2 = CG.squareCompact(f1, d);
        uint256 e1 = (uint256(keccak256("e1")) >> 176) | (1 << 79) | 1;
        uint256 e2 = (uint256(keccak256("e2")) >> 176) | (1 << 79);
        require(CG.eq(CG.shamir(f1, e1, f2, e2, d), _ref(f1, e1, f2, e2, d)), "80bit mismatch");
    }

    function test_GasShamir80bit() public view {
        B.Int memory d = D();
        CG.Form memory f1 = G();
        for (uint256 i = 0; i < 8; i++) f1 = CG.squareCompact(f1, d);
        CG.Form memory f2 = CG.squareCompact(f1, d);
        uint256 e1 = (uint256(keccak256("l")) >> 176) | (1 << 79) | 1;
        uint256 e2 = (uint256(keccak256("r")) >> 176) | (1 << 79) | 1;
        uint256 g0 = gasleft();
        CG.Form memory res = CG.shamir(f1, e1, f2, e2, d);
        console2.log("SHAMIR 80-bit (pi^l * u^r) REAL gas:", g0 - gasleft());
        require(!B.isZero(res.a), "sanity");
    }
}
