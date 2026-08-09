// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test, console2} from "forge-std/Test.sol";
import {LibBigInt as B} from "../src/LibBigInt.sol";
import {LibClassGroupBig as CG} from "../src/LibClassGroupBig.sol";
import {LibClassGroupBigTest} from "./LibClassGroupBig.t.sol";

/// Same verification shape as VerifyShapedBench, but composition uses NUCOMP.
/// Identical structure so the two totals are directly comparable.
contract VerifyNucompBench is LibClassGroupBigTest {
    function _bits() private pure returns (uint256) {
        return uint256(keccak256("shamir-shape")) | uint256(keccak256("or-mask"));
    }

    function test_GasVerifyShaped_Nucomp() public view {
        B.Int memory d = D();
        CG.Form memory h = G();
        for (uint256 i = 0; i < 8; i++) h = CG.squareCompact(h, d);

        uint256 bits = _bits();
        uint256 nComp = 0;
        uint256 gas0 = gasleft();
        CG.Form memory r = h;
        for (uint256 i = 0; i < 80; i++) {
            r = CG.squareCompact(r, d);
            if ((bits >> i) & 3 != 0) { r = CG.nucompCompact(r, h, d); nComp++; }
        }
        uint256 used = gas0 - gasleft();
        console2.log("VERIFY (NUCOMP): 80 sq + composes:", nComp);
        console2.log("  TOTAL gas:", used);
        console2.log("  per-op avg:", used / (80 + nComp));
        require(!B.isZero(r.a), "sanity");
    }
}
