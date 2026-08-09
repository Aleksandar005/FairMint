// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test, console2} from "forge-std/Test.sol";
import {LibBigInt as B} from "../src/LibBigInt.sol";
import {LibClassGroupBig as CG} from "../src/LibClassGroupBig.sol";
import {LibClassGroupBigTest} from "./LibClassGroupBig.t.sol";

/// Protivnicki testovi za NUCOMP koje vektori iz drugog chata ne pokrivaju:
/// (1) translate trik: f2 = f1 * T^t ima ISTO a => F = gcd(a1,a2) = a1
///     (512-bit!) i genericki F nedeljivo sa s => retka grana pod maksimalnim
///     stresom, sa trostruko poznatim odgovorom (compose i square).
/// (2) dugacak diferencijalni lanac nucomp vs compose na punim velicinama.
/// (3) f * f^{-1} = identitet (F = a1, s = 0 => F | s grana sa velikim F).
contract NucompAdversarial is LibClassGroupBigTest {
    function _translate(CG.Form memory f, uint256 t) private pure returns (CG.Form memory) {
        // (a, b + 2at, c + bt + at^2) — ista klasa, ista diskriminanta
        B.Int memory ti = B.fromUint(t);
        B.Int memory at = B.mul(f.a, ti);
        B.Int memory b2 = B.add(f.b, B.shl1(at));
        B.Int memory c2 = B.add(B.add(f.c, B.mul(f.b, ti)), B.mul(at, ti));
        return CG.Form(f.a, b2, c2);
    }
    function _discOk(CG.Form memory f, B.Int memory d) private pure returns (bool) {
        return B.cmp(B.sub(B.mul(f.b, f.b), B.shl1(B.shl1(B.mul(f.a, f.c)))), d) == 0;
    }

    function test_RareBranch_TranslateTrick() public view {
        B.Int memory d = D();
        CG.Form memory f = G();
        for (uint256 i = 0; i < 8; i++) f = CG.squareCompact(f, d);
        CG.Form memory sq = CG.square(f, d);
        for (uint256 t = 1; t <= 3; t++) {
            CG.Form memory f2 = _translate(f, t);
            require(_discOk(f2, d), "translate broke disc");
            CG.Form memory viaN = CG.nucomp(f, f2, d);
            CG.Form memory viaC = CG.compose(f, f2, d);
            require(CG.eq(viaN, viaC), "rare branch: nucomp != compose");
            require(CG.eq(viaN, sq), "rare branch: != square(f)");
            // i obrnut redosled argumenata
            require(CG.eq(CG.nucomp(f2, f, d), sq), "rare branch swapped");
        }
    }

    function test_InverseGivesIdentity() public view {
        B.Int memory d = D();
        CG.Form memory f = G();
        for (uint256 i = 0; i < 8; i++) f = CG.squareCompact(f, d);
        CG.Form memory finv = CG.Form(f.a, B.negate(f.b), f.c);
        CG.Form memory idN = CG.nucomp(f, finv, d);
        CG.Form memory idC = CG.compose(f, finv, d);
        require(CG.eq(idN, idC), "inverse: nucomp != compose");
        require(B.isOne(idN.a), "inverse: not identity");
    }

    function test_DiffChain40() public view {
        B.Int memory d = D();
        CG.Form memory h = G();
        for (uint256 i = 0; i < 8; i++) h = CG.squareCompact(h, d);
        CG.Form memory rn = h;
        CG.Form memory rc = h;
        for (uint256 i = 0; i < 40; i++) {
            rn = CG.nucompCompact(rn, h, d);
            rc = CG.composeCompact(rc, h, d);
            require(CG.eq(rn, rc), "chain: nucomp != compose");
            require(_discOk(rn, d), "chain: disc broken");
        }
    }
}
