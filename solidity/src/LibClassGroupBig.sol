// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibBigInt as B} from "./LibBigInt.sol";

/// @title LibClassGroupBig — class group arithmetic at production discriminant sizes
/// @notice Same algorithms as the int256 LibClassGroup (Gauss composition, reduction,
///         powering) but over signed arbitrary-precision integers (LibBigInt), so it
///         works for 1024-bit and larger discriminants where coefficients and
///         composition intermediates no longer fit in 256 bits. Forms are (a,b,c)
///         with b^2 - 4ac = D < 0. This is the "real" on-chain shape; see the gas
///         test for the cost, which motivates L2 / SNARK-wrapping in production.
library LibClassGroupBig {
    using B for B.Int;

    struct Form {
        B.Int a;
        B.Int b;
        B.Int c;
    }

    function _two() private pure returns (B.Int memory) { return B.fromUint(2); }
    function _four() private pure returns (B.Int memory) { return B.fromUint(4); }

    // (a,b,c) with given D as identity: (1, 1, (1-D)/4)
    function identity(B.Int memory D) internal pure returns (Form memory f) {
        f.a = B.fromUint(1);
        f.b = B.fromUint(1);
        B.Int memory oneMinusD = B.sub(B.fromUint(1), D);
        f.c = B.fdiv(oneMinusD, _four());
    }

    function eq(Form memory x, Form memory y) internal pure returns (bool) {
        return B.cmp(x.a, y.a) == 0 && B.cmp(x.b, y.b) == 0 && B.cmp(x.c, y.c) == 0;
    }

    function normalize(Form memory f) internal pure returns (Form memory) {
        // if -a < b <= a: already normal
        B.Int memory negA = B.negate(f.a);
        if (B.cmp(negA, f.b) < 0 && B.cmp(f.b, f.a) <= 0) return f;
        // r = (a - b) / (2a)   (floor)
        B.Int memory twoA = B.mul(_two(), f.a);
        B.Int memory r = B.fdiv(B.sub(f.a, f.b), twoA);
        // b2 = b + 2*r*a ; c2 = a*r*r + b*r + c
        B.Int memory b2 = B.add(f.b, B.mul(B.mul(_two(), r), f.a));
        B.Int memory ar = B.mul(f.a, r);
        B.Int memory c2 = B.add(B.add(B.mul(ar, r), B.mul(f.b, r)), f.c);
        return Form(f.a, b2, c2);
    }

    function reduce(Form memory f) internal pure returns (Form memory) {
        f = normalize(f);
        // while a > c or (a==c and b<0)
        while (B.cmp(f.a, f.c) > 0 || (B.cmp(f.a, f.c) == 0 && f.b.neg)) {
            // s = (c + b) / (2c)  (floor)
            B.Int memory twoC = B.mul(_two(), f.c);
            B.Int memory s = B.fdiv(B.add(f.c, f.b), twoC);
            // (a,b,c) = (c, -b + 2*s*c, c*s*s - b*s + a)
            B.Int memory newA = f.c;
            B.Int memory newB = B.add(B.negate(f.b), B.mul(B.mul(_two(), s), f.c));
            B.Int memory cs = B.mul(f.c, s);
            B.Int memory newC = B.add(B.sub(B.mul(cs, s), B.mul(f.b, s)), f.a);
            f = Form(newA, newB, newC);
        }
        return normalize(f);
    }

    function inverse(Form memory f) internal pure returns (Form memory) {
        return reduce(Form(f.a, B.negate(f.b), f.c));
    }

    /// @dev Gauss composition (Cohen 5.4.7), same as the int256 version.
    function compose(Form memory f1, Form memory f2, B.Int memory D)
        internal pure returns (Form memory)
    {
        // g = (b1 + b2)/2 ; h = (b2 - b1)/2
        B.Int memory g = B.fdiv(B.add(f1.b, f2.b), _two());
        B.Int memory h = B.fdiv(B.sub(f2.b, f1.b), _two());
        // w = gcd(gcd(a1,a2), g)
        B.Int memory w = B.gcd(B.gcd(f1.a, f2.a), g);
        // s = a1/w ; t = a2/w ; u = g/w
        B.Int memory s = B.fdiv(f1.a, w);
        B.Int memory t = B.fdiv(f2.a, w);
        B.Int memory u = B.fdiv(g, w);
        // solve (t*u) x = (h*u + s*c1) mod (s*t)
        B.Int memory st = B.mul(s, t);
        B.Int memory rhs1 = B.add(B.mul(h, u), B.mul(s, f1.c));
        (B.Int memory k0, B.Int memory cap) = _solveMod(B.mul(t, u), rhs1, st);
        // solve (t*cap) n = (h - t*k0) mod s
        (B.Int memory n, ) = _solveMod(B.mul(t, cap), B.sub(h, B.mul(t, k0)), s);
        // k = (k0 + cap*n) mod st
        B.Int memory k = B.fmod(B.add(k0, B.mul(cap, n)), st);
        // l = (t*k - h)/s ; m = (t*u*k - h*u - s*c1)/(s*t)
        B.Int memory l = B.fdiv(B.sub(B.mul(t, k), h), s);
        B.Int memory tuk = B.mul(B.mul(t, u), k);
        B.Int memory mNum = B.sub(B.sub(tuk, B.mul(h, u)), B.mul(s, f1.c));
        B.Int memory m = B.fdiv(mNum, st);
        // a3 = s*t ; b3 = w*u - (k*t + l*s) ; c3 = k*l - w*m
        B.Int memory a3 = st;
        B.Int memory b3 = B.sub(B.mul(w, u), B.add(B.mul(k, t), B.mul(l, s)));
        B.Int memory c3 = B.sub(B.mul(k, l), B.mul(w, m));
        return reduce(Form(a3, b3, c3));
    }

    function square(Form memory f, B.Int memory D) internal pure returns (Form memory) {
        return compose(f, f, D);
    }

    /// @dev solve a*x ≡ b (mod mod); returns (x0, mod/g). Mirrors Python solve_mod.
    function _solveMod(B.Int memory a, B.Int memory bb, B.Int memory mod)
        private pure returns (B.Int memory x, B.Int memory cap)
    {
        (B.Int memory gg, B.Int memory x0, ) = B.xgcd(a, mod);
        // require b % g == 0
        cap = B.fdiv(mod, gg);
        B.Int memory bDivG = B.fdiv(bb, gg);
        x = B.fmod(B.mul(x0, bDivG), cap);
    }

    function pow(Form memory f, uint256 e, B.Int memory D)
        internal pure returns (Form memory r)
    {
        r = identity(D);
        Form memory base = f;
        while (e > 0) {
            if (e & 1 == 1) r = compose(r, base, D);
            base = square(base, D);
            e >>= 1;
        }
    }
}
