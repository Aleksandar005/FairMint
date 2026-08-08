// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test, console2} from "forge-std/Test.sol";
import {LibBigInt as B} from "../src/LibBigInt.sol";
import {LibClassGroupBig as CG} from "../src/LibClassGroupBig.sol";
import {LibClassGroupBigTest} from "./LibClassGroupBig.t.sol";

/// Diferencijalni lanac: NUDUPL square mora dati IDENTICNU redukovanu formu
/// kao genericki compose(f, f) (nezavisna staza, vec pinovana Python vektorima),
/// uz ocuvanje diskriminante na svakom koraku.
contract NuduplDiff is LibClassGroupBigTest {
    function _discOk(CG.Form memory f, B.Int memory d) private pure returns (bool) {
        // b^2 - 4ac == D
        B.Int memory lhs = B.sub(B.mul(f.b, f.b), B.shl1(B.shl1(B.mul(f.a, f.c))));
        return B.cmp(lhs, d) == 0;
    }

    function test_NuduplMatchesComposeChain() public view {
        B.Int memory d = D();
        CG.Form memory f = G();
        for (uint256 i = 0; i < 25; i++) {
            CG.Form memory s1 = CG.square(f, d);
            CG.Form memory s2 = CG.compose(f, f, d);
            require(CG.eq(s1, s2), "nudupl != compose(f,f)");
            require(_discOk(s1, d), "discriminant broken");
            f = s1;
        }
    }

    function test_GasNuduplSquare() public view {
        B.Int memory d = D();
        CG.Form memory h = G();
        for (uint256 i = 0; i < 8; i++) h = CG.squareCompact(h, d);
        uint256 g0 = gasleft();
        CG.Form memory s = CG.square(h, d);
        console2.log("NUDUPL full-size square gas:", g0 - gasleft());
        require(!B.isZero(s.a), "sanity");
    }
}
