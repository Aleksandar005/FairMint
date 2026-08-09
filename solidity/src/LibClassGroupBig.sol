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
        // r = (a - b) / (2a)   (floor); a - b = 2a*r + rem
        // OPT NIVO 2: b2 = b + 2ra = a - rem  (bez mnozenja!), divmodFast za r
        (B.Int memory r, B.Int memory rem) = B.divmodFast(B.sub(f.a, f.b), B.shl1(f.a));
        B.Int memory b2 = B.sub(f.a, rem);
        // c2 = a*r^2 + b*r + c = c + r*(b + a*r)  — 2 mnozenja umesto 3
        B.Int memory ar = B.mul(f.a, r);
        B.Int memory c2 = B.add(f.c, B.mul(r, B.add(f.b, ar)));
        return Form(f.a, b2, c2);
    }

    function reduce(Form memory f) internal pure returns (Form memory) {
        f = normalize(f);
        // while a > c or (a==c and b<0)
        while (B.cmp(f.a, f.c) > 0 || (B.cmp(f.a, f.c) == 0 && f.b.neg)) {
            // s = (c + b) / (2c)  (floor); c + b = 2c*s + rem
            // OPT NIVO 2: newB = 2sc - b = c - rem (bez mnozenja), divmodFast za s,
            // newC = cs^2 - bs + a = a - s*(b - c*s) — 2 mnozenja umesto 3
            (B.Int memory s, B.Int memory rem) = B.divmodFast(B.add(f.c, f.b), B.shl1(f.c));
            B.Int memory newA = f.c;
            B.Int memory newB = B.sub(f.c, rem);
            B.Int memory cs = B.mul(f.c, s);
            B.Int memory newC = B.sub(f.a, B.mul(s, B.sub(f.b, cs)));
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
        // g = (b1 + b2)/2 ; h = (b2 - b1)/2   (b1, b2 share parity: sums are even)
        B.Int memory g = B.shr1(B.add(f1.b, f2.b));
        B.Int memory h = B.shr1(B.sub(f2.b, f1.b));
        // w = gcd(gcd(a1,a2), g)
        B.Int memory w = B.gcd(B.gcd(f1.a, f2.a), g);
        // s = a1/w ; t = a2/w ; u = g/w
        // OPT: w == 1 almost always for random forms — skip three big divisions.
        B.Int memory s; B.Int memory t; B.Int memory u;
        if (B.isOne(w)) { s = f1.a; t = f2.a; u = g; }
        else {
            s = B.fdiv(f1.a, w);
            t = B.fdiv(f2.a, w);
            u = B.fdiv(g, w);
        }
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

    /// @dev OPT: dedicated squaring. For f1 == f2: g = b, h = 0, t = s, and
    ///      w = gcd(a, b). When w == 1 (the generic case) the congruence
    ///      (t*u)x ≡ s*c (mod s*t) divides through by a and collapses to
    ///        b * mu ≡ c (mod a)
    ///      solved by ONE half-xgcd on operands half the size of s*t, and the
    ///      second _solveMod is provably n = 0, so it is skipped entirely. Result:
    ///        A = a^2,  B = b - 2*a*mu,  C = mu^2 - (b*mu - c)/a   (exact division)
    ///      — algebraically identical to compose(f, f, D), verified against the
    ///      Python vectors. Squarings dominate any square-and-multiply /
    ///      Shamir pass, so this is the hottest call site in verification.
    /// @dev OPT NIVO 3: NUDUPL kvadriranje. Klasicna staza formira
    ///      (a^2, b-2a*mu, ...) pune sirine pa placa ~150 koraka redukcije.
    ///      Umesto toga: parcijalni Euklid na (a, mu) do praga ~bitLen(a)/2
    ///      daje (r', r) i kofaktore (beta', beta); unimodularna smena izvedena
    ///      iz F(x,y) = (ax - mu*y)^2 + bxy - e*y^2 (e = (b*mu - c)/a) daje:
    ///        A' = (a r'^2 - b r' beta' + c beta'^2) / a          (egzaktno)
    ///        C' = (a r^2  - b r  beta  + c beta^2 ) / a          (egzaktno)
    ///        B'0 = (2a r r' - b(beta r' + beta' r) + 2c beta beta') / a
    ///        B' = -B'0 ako je broj koraka paran, inace +B'0
    ///      Provereno: k = 0 koraka reprodukuje tacno klasicne formule.
    ///      Izlaz je ~pola sirine => reduce radi O(1) koraka umesto ~150.
    function square(Form memory f, B.Int memory D) internal pure returns (Form memory) {
        // jedan xgcdHalf daje i w = gcd(b, a) i inverz
        (B.Int memory w, B.Int memory inv) = B.xgcdHalf(f.b, f.a);
        if (!B.isOne(w)) return compose(f, f, D); // redak nekoprimni slucaj
        B.Int memory mu = B.fmod(B.mul(inv, f.c), f.a);
        if (B.bitLen(f.a) <= 256) {
            // male forme: direktne formule su jeftinije od NUDUPL rezija
            B.Int memory a3 = B.mul(f.a, f.a);
            B.Int memory b3 = B.sub(f.b, B.shl1(B.mul(f.a, mu)));
            B.Int memory q = B.fdiv(B.sub(B.mul(f.b, mu), f.c), f.a); // exact
            B.Int memory c3 = B.sub(B.mul(mu, mu), q);
            return reduce(Form(a3, b3, c3));
        }
        // prag = bitLen(D)/4: balansira A' ~ 2^(2t) i C' ~ 2^(|D|bits - 2t)
        // nezavisno od velicine a (za malo a, c je srazmerno vece!)
        (B.Int memory rP, B.Int memory rC, B.Int memory bP, B.Int memory bC, bool evenTot) =
            B.xgcdPartial(f.a, mu, (B.bitLen(D) >> 2) + 1);
        return reduce(_nuduplForm(f, rP, rC, bP, bC, evenTot));
    }

    function _nuduplForm(
        Form memory f,
        B.Int memory rP, B.Int memory rC,
        B.Int memory bP, B.Int memory bC,
        bool evenTot
    ) private pure returns (Form memory) {
        // A' = (a*rP^2 - b*rP*bP + c*bP^2) / a
        B.Int memory t = B.sub(B.mul(B.mul(f.a, rP), rP), B.mul(f.b, B.mul(rP, bP)));
        (B.Int memory A2, B.Int memory x1) = B.divmod(B.add(t, B.mul(f.c, B.mul(bP, bP))), f.a);
        require(B.isZero(x1), "nudupl A");
        // C' = (a*rC^2 - b*rC*bC + c*bC^2) / a
        t = B.sub(B.mul(B.mul(f.a, rC), rC), B.mul(f.b, B.mul(rC, bC)));
        (B.Int memory C2, B.Int memory x2) = B.divmod(B.add(t, B.mul(f.c, B.mul(bC, bC))), f.a);
        require(B.isZero(x2), "nudupl C");
        // B'0 = (2a*rP*rC - b*(bC*rP + bP*rC) + 2c*bP*bC) / a
        t = B.sub(
            B.shl1(B.mul(B.mul(f.a, rP), rC)),
            B.mul(f.b, B.add(B.mul(bC, rP), B.mul(bP, rC)))
        );
        (B.Int memory B2, B.Int memory x3) = B.divmod(B.add(t, B.shl1(B.mul(f.c, B.mul(bP, bC)))), f.a);
        require(B.isZero(x3), "nudupl B");
        if (evenTot) B2 = B.negate(B2);
        return Form(A2, B2, C2);
    }

    /// @dev solve a*x ≡ b (mod mod); returns (x0, mod/g). Mirrors Python solve_mod.
    function _solveMod(B.Int memory a, B.Int memory bb, B.Int memory mod)
        private pure returns (B.Int memory x, B.Int memory cap)
    {
        // OPT: half-extended gcd — the Bezout y-coefficient was computed and thrown away.
        (B.Int memory gg, B.Int memory x0) = B.xgcdHalf(a, mod);
        // OPT: g == 1 in the generic case — skip both divisions.
        if (B.isOne(gg)) {
            cap = mod;
            x = B.fmod(B.mul(x0, bb), cap);
        } else {
            // require b % g == 0
            cap = B.fdiv(mod, gg);
            B.Int memory bDivG = B.fdiv(bb, gg);
            x = B.fmod(B.mul(x0, bDivG), cap);
        }
    }

    // ----------------------------------------------------------------
    // OPT: memory-compacting wrappers.
    //
    // Solidity never frees memory and the EVM charges 3*w + w^2/512 for w words,
    // so a chain of 100+ compositions in ONE transaction pays a quadratically
    // growing memory-expansion bill on top of each op ("463k per composition"
    // was measured on fresh memory and does NOT extrapolate linearly).
    //
    // Fix: snapshot the free-memory pointer, run the op, stash a compact copy of
    // the (small, reduced) result at the top, rewind the pointer to the snapshot
    // and rebuild the result low. All the op's intermediate garbage is reused by
    // the next op instead of accumulating. The stash sits far above the rebuild
    // region (separated by the op's entire garbage), and a guard asserts the
    // rebuild never reaches it.
    // ----------------------------------------------------------------

    function _compact(Form memory r, uint256 fmp0) private pure returns (Form memory) {
        // stash a contiguous copy of r at the current top of memory
        B.Int memory sa = B.clone(r.a);
        B.Int memory sb = B.clone(r.b);
        B.Int memory sc = B.clone(r.c);
        uint256 guard;
        assembly {
            guard := sa             // start of the stash cluster
            mstore(0x40, fmp0)      // rewind — op garbage becomes reusable
        }
        // rebuild EVERYTHING (struct included) below: no pointer may remain in
        // the garbage zone, or the next op's allocations would clobber it
        Form memory g = _rebuild(sa, sb, sc);
        uint256 top;
        assembly { top := mload(0x40) }
        require(top <= guard, "compact overlap"); // never triggers: gap = op garbage
        return g;
    }

    function _rebuild(B.Int memory sa, B.Int memory sb, B.Int memory sc)
        private pure returns (Form memory g)
    {
        g.a = B.clone(sa);
        g.b = B.clone(sb);
        g.c = B.clone(sc);
    }

    function squareCompact(Form memory f, B.Int memory D) internal pure returns (Form memory) {
        uint256 fmp0;
        assembly { fmp0 := mload(0x40) }
        return _compact(square(f, D), fmp0);
    }

    /// @dev NUCOMP (van der Poorten, Math.Comp.72 (2003), Algorithm 3). Composes two
    ///      distinct forms while partially reducing, so intermediates stay ~|D|^(1/2)
    ///      instead of growing to |D| and needing a full ~150-step reduce. Validated in
    ///      Python against the classic compose on 1600+ cases up to 1792-bit (both the
    ///      coprime F=1 branch and the F>1 branch). Convention: b*u2 + c*u1 = F.
    struct _NC { B.Int G; B.Int By; B.Int Bx; B.Int Cy; B.Int Dy; }

    function nucomp(Form memory f1, Form memory f2, B.Int memory D)
        internal pure returns (Form memory)
    {
        // NUCOMP requires distinct forms; duplicate composition is NUDUPL (square).
        if (eq(f1, f2)) return square(f1, D);
        // (1) s = (v1+v2)/2 ; m = v2 - s
        B.Int memory s = B.shr1(B.add(f1.b, f2.b));
        B.Int memory m = B.sub(f2.b, s);
        _NC memory nc;
        {
            // (2) need b with b*u2 + c*u1 = F=gcd(u1,u2). xgcdHalf(u2,u1) gives (F,b)
            //     with u2*b ≡ F (mod u1) — Lehmer-fast, and b is all the common
            //     F|s branch needs. (Any valid b works: Bx = m*b mod (u1/F) is
            //     invariant under b -> b + u1/F.)
            (B.Int memory F, B.Int memory b) = B.xgcdHalf(f2.a, f1.a);
            if (B.isZero(B.fmod(s, F))) {
                nc.G = F;
                nc.By = B.fdiv(f1.a, F);
                nc.Bx = B.fmod(B.mul(m, b), nc.By);
                nc.Cy = B.fdiv(f2.a, F);
                nc.Dy = B.fdiv(s, F);
            } else {
                // rare branch: recover c = (F - b*u2)/u1 (exact), then (G, yF)
                B.Int memory c = B.fdiv(B.sub(F, B.mul(b, f2.a)), f1.a);
                (B.Int memory G, B.Int memory yF) = B.xgcdHalf(s, F); // s*yF ≡ G (mod F)
                B.Int memory H = B.fdiv(F, G);
                nc.G = G;
                nc.By = B.fdiv(f1.a, G);
                nc.Cy = B.fdiv(f2.a, G);
                nc.Dy = B.fdiv(s, G);
                // (4) l = yF*(b*w1 + c*w2) mod H
                B.Int memory inner = B.add(B.mul(b, B.fmod(f1.c, H)), B.mul(c, B.fmod(f2.c, H)));
                B.Int memory l = B.fmod(B.mul(yF, inner), H);
                B.Int memory bx0 = B.add(B.mul(b, B.fdiv(m, H)), B.mul(l, B.fdiv(f1.a, F)));
                nc.Bx = B.fmod(bx0, nc.By);
            }
        }
        // partial reduction threshold: bitLen(D)/4  (== |D|^(1/4)), same as NUDUPL
        return _nucompFinish(f1, f2, m, nc, B.bitLen(D) >> 2);
    }

    function _nucompFinish(
        Form memory f1, Form memory f2, B.Int memory m, _NC memory nc, uint256 stopBits
    ) private pure returns (Form memory) {
        // (5) partial Euclid on (By, Bx mod By) via the Lehmer-batched engine.
        //     xgcdPartial returns two consecutive remainders (rP,rC) with cofactors
        //     (bP,bC) and total-step parity. Map: by=rP, bx=rC, y=bP, x=bC.
        (B.Int memory by, B.Int memory bx, B.Int memory y, B.Int memory x, bool evenTot) =
            B.xgcdPartial(nc.By, B.fmod(nc.Bx, nc.By), stopBits);
        bool noSteps = B.isZero(y) && B.isOne(x); // z == 0 (no Euclid step taken)
        if (!evenTot) { by = B.negate(by); y = B.negate(y); } // z odd
        B.Int memory ax = B.mul(nc.G, x);
        B.Int memory ay = B.mul(nc.G, y);
        // (6) near reduced composite
        B.Int memory u3; B.Int memory v3; B.Int memory w3;
        if (noSteps) {
            B.Int memory cx = B.fdiv(B.sub(B.mul(bx, nc.Cy), m), nc.By);
            B.Int memory cy = B.isZero(bx)
                ? B.fdiv(B.mul(by, f2.a), f1.a)
                : B.fdiv(B.add(B.mul(by, cx), m), bx);
            B.Int memory dx = B.fdiv(B.sub(B.mul(bx, nc.Dy), f2.c), nc.By);
            u3 = B.mul(by, cy);
            w3 = B.sub(B.mul(bx, cx), B.mul(nc.G, dx));
            v3 = B.sub(B.mul(nc.G, nc.Dy), B.add(B.mul(bx, cy), B.mul(by, cx)));
        } else {
            B.Int memory cx = B.fdiv(B.sub(B.mul(bx, nc.Cy), B.mul(m, x)), nc.By);
            B.Int memory cy = B.isZero(bx)
                ? B.fdiv(B.sub(B.mul(f2.a, by), B.mul(y, m)), f1.a)
                : B.fdiv(B.add(B.mul(by, cx), m), bx);
            B.Int memory dx = B.fdiv(B.sub(B.mul(bx, nc.Dy), B.mul(f2.c, x)), nc.By);
            B.Int memory dy = B.fdiv(B.add(B.mul(dx, y), nc.Dy), x);
            u3 = B.sub(B.mul(by, cy), B.mul(ay, dy));
            w3 = B.sub(B.mul(bx, cx), B.mul(ax, dx));
            v3 = B.sub(B.add(B.mul(ax, dy), B.mul(ay, dx)), B.add(B.mul(bx, cy), B.mul(by, cx)));
        }
        return reduce(Form(u3, v3, w3));
    }

    function composeCompact(Form memory f1, Form memory f2, B.Int memory D)
        internal pure returns (Form memory)
    {
        uint256 fmp0;
        assembly { fmp0 := mload(0x40) }
        return _compact(compose(f1, f2, D), fmp0);
    }

    /// @dev memory-compacted NUCOMP — same wrapper as composeCompact, ~7x cheaper
    ///      composition. Use in long verification chains of distinct forms.
    function nucompCompact(Form memory f1, Form memory f2, B.Int memory D)
        internal pure returns (Form memory)
    {
        uint256 fmp0;
        assembly { fmp0 := mload(0x40) }
        return _compact(nucomp(f1, f2, D), fmp0);
    }

    /// @dev OPT: MSB-first square-and-multiply. The LSB-first version paid for
    ///      full-price compositions with the identity AND one wasted final
    ///      squaring of the base after the last bit (~463k gas each at 1024-bit).
    ///      Uses compacting ops so long chains don't hit quadratic memory cost.
    function pow(Form memory f, uint256 e, B.Int memory D)
        internal pure returns (Form memory r)
    {
        if (e == 0) return identity(D);
        uint256 bit = 1 << 255;
        while (e & bit == 0) bit >>= 1;
        r = f;
        bit >>= 1;
        while (bit != 0) {
            r = squareCompact(r, D);
            if (e & bit != 0) r = composeCompact(r, f, D);
            bit >>= 1;
        }
    }
}
