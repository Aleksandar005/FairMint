// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
import {LibBigInt as B} from "../src/LibBigInt.sol";

/// Diferencijalni fuzz Lehmer engine-a protiv DVE nezavisne familije:
/// klasicnog Euklida (xgcdHalfClassic) i binarnog Stein gcd-a (gcdBinary).
contract GcdFuzz is Test {
    function _mk2(uint256 l0, uint256 l1, bool neg) private pure returns (B.Int memory z) {
        uint256[] memory L = new uint256[](2); L[0] = l0; L[1] = l1;
        z.limbs = L; z.neg = neg && (l0 | l1) != 0;
    }
    function _mk4(uint256 seed, bool neg) private pure returns (B.Int memory z) {
        uint256[] memory L = new uint256[](4);
        L[0] = uint256(keccak256(abi.encode(seed, 0)));
        L[1] = uint256(keccak256(abi.encode(seed, 1)));
        L[2] = uint256(keccak256(abi.encode(seed, 2)));
        L[3] = uint256(keccak256(abi.encode(seed, 3))) >> 2;
        z.limbs = L; z.neg = neg;
    }
    function _checkBezout(B.Int memory a, B.Int memory b, B.Int memory g, B.Int memory x) private pure {
        // a*x ≡ g (mod b)
        if (!B.isZero(b)) {
            require(B.isZero(B.fmod(B.sub(B.mul(a, x), g), b)), "bezout broken");
        }
        require(!g.neg, "g negative");
    }

    /// Lehmer vs klasicni Euklid, 512-bit, sa znacima
    function testFuzz_LehmerVsClassic512(uint256 a0, uint256 a1, uint256 b0, uint256 b1, bool na, bool nb) public pure {
        B.Int memory a = _mk2(a0, a1 >> 1, na);
        B.Int memory b = _mk2(b0, b1 >> 1, nb);
        (B.Int memory g1, B.Int memory x1) = B.xgcdHalf(a, b);
        (B.Int memory g2, ) = B.xgcdHalfClassic(a, b);
        require(B.cmp(g1, g2) == 0, "g mismatch");
        _checkBezout(a, b, g1, x1);
    }

    /// Lehmer vs klasicni Euklid, 1024-bit (razmera compose modula)
    /// forge-config: default.fuzz.runs = 64
    function testFuzz_LehmerVsClassic1024(uint256 sa, uint256 sb, bool na, bool nb) public pure {
        B.Int memory a = _mk4(sa, na);
        B.Int memory b = _mk4(sb, nb);
        (B.Int memory g1, B.Int memory x1) = B.xgcdHalf(a, b);
        (B.Int memory g2, ) = B.xgcdHalfClassic(a, b);
        require(B.cmp(g1, g2) == 0, "g mismatch");
        _checkBezout(a, b, g1, x1);
    }

    /// Lehmer gcd vs binarni Stein (treca nezavisna familija)
    function testFuzz_LehmerVsBinary(uint256 a0, uint256 a1, uint256 b0, uint256 b1, bool na, bool nb) public pure {
        B.Int memory a = _mk2(a0, a1 >> 1, na);
        B.Int memory b = _mk2(b0, b1 >> 1, nb);
        require(B.cmp(B.gcd(a, b), B.gcdBinary(a, b)) == 0, "gcd mismatch");
    }

    /// Ivicni slucajevi sa zajednickim faktorima i malim/nula vrednostima
    function testFuzz_CommonFactor(uint128 m, uint96 p, uint96 q) public pure {
        B.Int memory mm = B.fromUint(uint256(m) | 1);
        B.Int memory a = B.mul(mm, B.fromUint(p));
        B.Int memory b = B.mul(mm, B.fromUint(q));
        (B.Int memory g, B.Int memory x) = B.xgcdHalf(a, b);
        (B.Int memory gc, ) = B.xgcdHalfClassic(a, b);
        require(B.cmp(g, gc) == 0, "g mismatch");
        _checkBezout(a, b, g, x);
        // g mora biti deljiv sa m
        if (p != 0 || q != 0) {
            require(B.isZero(B.fmod(g, mm)), "common factor lost");
        }
    }

    /// divmodFast mora dati IDENTICAN (q, r) kao divmod, ukljucujuci znakove
    function testFuzz_DivmodFastMatches(uint256 a0, uint256 a1, uint256 b0, uint256 b1, bool na, bool nb, uint8 shape) public pure {
        B.Int memory a; B.Int memory b;
        if (shape & 1 == 0) { a = _mk2(a0, a1, na); } else { a = _mk4(a0, na); }
        if (shape & 2 == 0) { b = _mk2(b0, b1 >> (shape >> 2), nb); } else { b = _mk4(b0, nb); }
        if (B.isZero(b)) return;
        (B.Int memory q1, B.Int memory r1) = B.divmodFast(a, b);
        (B.Int memory q2, B.Int memory r2) = B.divmod(a, b);
        require(B.cmp(q1, q2) == 0, "q mismatch");
        require(B.cmp(r1, r2) == 0, "r mismatch");
    }

    /// Regresija: a == 0 je obarao Lehmer fallback (div by zero posle swap-a).
    /// Nadjeno fuzz-om; drzimo deterministicki.
    function test_ZeroEdges() public pure {
        B.Int memory zero = B.fromUint(0);
        B.Int memory b = _mk2(3, 84128, true);
        (B.Int memory g1, B.Int memory x1) = B.xgcdHalf(zero, b);
        (B.Int memory g2, ) = B.xgcdHalfClassic(zero, b);
        require(B.cmp(g1, g2) == 0, "g mismatch");
        _checkBezout(zero, b, g1, x1);
        (g1, x1) = B.xgcdHalf(b, zero);
        (g2, ) = B.xgcdHalfClassic(b, zero);
        require(B.cmp(g1, g2) == 0, "g mismatch 2");
        require(B.cmp(B.gcd(zero, zero), B.fromUint(0)) == 0, "gcd(0,0)");
    }
}
