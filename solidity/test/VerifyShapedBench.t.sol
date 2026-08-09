// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test, console2} from "forge-std/Test.sol";
import {LibBigInt as B} from "../src/LibBigInt.sol";
import {LibClassGroupBig as CG} from "../src/LibClassGroupBig.sol";
import {LibClassGroupBigTest} from "./LibClassGroupBig.t.sol";

/// Honest end-to-end cost model of one Wesolowski verification pass:
/// 80 squarings + ~60 compositions with a FULL-SIZE base (Shamir joint pass,
/// 80-bit challenge), memory expansion included, in a single call.
contract VerifyShapedBench is LibClassGroupBigTest {
    function _bits() private pure returns (uint256) {
        return uint256(keccak256("shamir-shape")) | uint256(keccak256("or-mask"));
    }

    function test_GasVerifyShaped_Compact() public view {
        B.Int memory d = D();
        // full-size generic base: g^(2^8), reduced, ~512-bit coefficients
        CG.Form memory h = G();
        for (uint256 i = 0; i < 8; i++) h = CG.squareCompact(h, d);

        uint256 bits = _bits();
        uint256 nComp = 0;
        uint256 gas0 = gasleft();
        CG.Form memory r = h;
        for (uint256 i = 0; i < 80; i++) {
            r = CG.squareCompact(r, d);
            if ((bits >> i) & 3 != 0) { r = CG.composeCompact(r, h, d); nComp++; }
        }
        uint256 used = gas0 - gasleft();
        console2.log("VERIFY-SHAPED FULL: 80 sq + composes:", nComp);
        console2.log("  TOTAL gas:", used);
        console2.log("  per-op avg:", used / (80 + nComp));
        require(!B.isZero(r.a), "sanity");
    }

    function test_GasFullSizeOps() public view {
        B.Int memory d = D();
        CG.Form memory h = G();
        for (uint256 i = 0; i < 8; i++) h = CG.squareCompact(h, d);
        CG.Form memory h2 = CG.squareCompact(h, d);

        uint256 g0 = gasleft();
        CG.Form memory s1 = CG.square(h, d);
        console2.log("ONE full-size square gas:", g0 - gasleft());
        g0 = gasleft();
        CG.Form memory c1 = CG.compose(h, h2, d);
        console2.log("ONE full-size compose gas:", g0 - gasleft());
        require(!B.isZero(s1.a) && !B.isZero(c1.a), "sanity");
    }

    function test_CompactMatchesPlain() public view {
        B.Int memory d = D();
        CG.Form memory g = G();
        CG.Form memory q = g;
        for (uint256 i = 0; i < 6; i++) {
            q = CG.squareCompact(q, d);
            q = CG.composeCompact(q, g, d);
        }
        CG.Form memory p = g;
        for (uint256 i = 0; i < 6; i++) {
            p = CG.square(p, d);
            p = CG.compose(p, g, d);
        }
        require(CG.eq(p, q), "compact != plain");
    }
}
