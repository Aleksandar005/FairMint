// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title LibBigInt — signed arbitrary-precision integers for class group arithmetic
/// @notice Class group composition needs SIGNED, non-modular big integers with exact
///         division and extended GCD — which RSA-oriented libraries (e.g. Cicada's
///         LibUint1024, focused on modular arithmetic) do not provide. The 256-bit
///         limb layout and the mul512 word-multiply trick follow the same idea as
///         Cicada / Remco Bloemen's mathemagic; the signed wrapper, schoolbook
///         multiply, Knuth long division and xgcd on top are specific to this use.
///
///         Numbers are sign-magnitude: a bool `neg` plus `uint256[] limbs`, little-endian
///         (limbs[0] = least significant). Zero is represented as neg=false, all-zero
///         limbs. For a 1024-bit discriminant, composition intermediates reach ~1600
///         bits, so callers size limb arrays generously (we use dynamic arrays and
///         trim leading zeros after each op).
library LibBigInt {
    struct Int {
        bool neg;
        uint256[] limbs; // little-endian, no trailing zero limbs (except value 0 -> [] or [0])
    }

    // ----------------------------------------------------------------
    // construction / normalization
    // ----------------------------------------------------------------

    function fromUint(uint256 x) internal pure returns (Int memory z) {
        z.limbs = new uint256[](1);
        z.limbs[0] = x;
        _trim(z);
    }

    function fromInt(int256 x) internal pure returns (Int memory z) {
        z.limbs = new uint256[](1);
        if (x < 0) { z.neg = true; z.limbs[0] = uint256(-x); }
        else z.limbs[0] = uint256(x);
        _trim(z);
    }

    function isZero(Int memory a) internal pure returns (bool) {
        for (uint256 i = 0; i < a.limbs.length; i++) if (a.limbs[i] != 0) return false;
        return true;
    }

    function _trim(Int memory a) internal pure {
        uint256[] memory l = a.limbs;
        uint256 n = l.length;
        while (n > 1 && l[n - 1] == 0) n--;
        if (n != l.length) {
            // OPT: shrink in place — we only ever reduce the length, and _trim is
            // only called on freshly allocated outputs, so no aliasing hazard and
            // no reallocation + copy.
            assembly { mstore(l, n) }
        }
        // after trimming, zero iff the single remaining limb is zero
        if (n == 1 && l[0] == 0) a.neg = false; // canonical zero
    }

    function clone(Int memory a) internal pure returns (Int memory z) {
        z.neg = a.neg;
        z.limbs = new uint256[](a.limbs.length);
        for (uint256 i = 0; i < a.limbs.length; i++) z.limbs[i] = a.limbs[i];
    }

    // ----------------------------------------------------------------
    // unsigned magnitude helpers
    // ----------------------------------------------------------------

    /// @dev compare magnitudes: -1 if |a|<|b|, 0 if equal, 1 if |a|>|b|
    function _ucmp(uint256[] memory a, uint256[] memory b) private pure returns (int256) {
        uint256 la = a.length; uint256 lb = b.length;
        // account for possible trailing zeros
        while (la > 0 && a[la - 1] == 0) la--;
        while (lb > 0 && b[lb - 1] == 0) lb--;
        if (la != lb) return la > lb ? int256(1) : int256(-1);
        for (uint256 i = la; i > 0; i--) {
            if (a[i - 1] != b[i - 1]) return a[i - 1] > b[i - 1] ? int256(1) : int256(-1);
        }
        return 0;
    }

    /// @dev unsigned add: |a| + |b|
    function _uadd(uint256[] memory a, uint256[] memory b) private pure returns (uint256[] memory r) {
        uint256 n = a.length >= b.length ? a.length : b.length;
        r = new uint256[](n + 1);
        uint256 carry = 0;
        for (uint256 i = 0; i < n; i++) {
            uint256 ai = i < a.length ? a[i] : 0;
            uint256 bi = i < b.length ? b[i] : 0;
            unchecked {
                uint256 s = ai + bi;
                uint256 c1 = s < ai ? 1 : 0;
                uint256 s2 = s + carry;
                uint256 c2 = s2 < s ? 1 : 0;
                r[i] = s2;
                carry = c1 + c2;
            }
        }
        r[n] = carry;
    }

    /// @dev unsigned sub: |a| - |b|, requires |a| >= |b|
    function _usub(uint256[] memory a, uint256[] memory b) private pure returns (uint256[] memory r) {
        r = new uint256[](a.length);
        uint256 borrow = 0;
        for (uint256 i = 0; i < a.length; i++) {
            uint256 ai = a[i];
            uint256 bi = i < b.length ? b[i] : 0;
            unchecked {
                uint256 d = ai - bi;
                uint256 b1 = ai < bi ? 1 : 0;
                uint256 d2 = d - borrow;
                uint256 b2 = d < borrow ? 1 : 0;
                r[i] = d2;
                borrow = b1 + b2;
            }
        }
        return r;
    }

    // ----------------------------------------------------------------
    // signed add / sub
    // ----------------------------------------------------------------

    function add(Int memory a, Int memory b) internal pure returns (Int memory z) {
        if (a.neg == b.neg) {
            z.neg = a.neg;
            z.limbs = _uadd(a.limbs, b.limbs);
        } else {
            int256 c = _ucmp(a.limbs, b.limbs);
            if (c == 0) { z.limbs = new uint256[](1); return z; }
            if (c > 0) { z.neg = a.neg; z.limbs = _usub(a.limbs, b.limbs); }
            else { z.neg = b.neg; z.limbs = _usub(b.limbs, a.limbs); }
        }
        _trim(z);
    }

    function negate(Int memory a) internal pure returns (Int memory z) {
        z = clone(a);
        if (!isZero(z)) z.neg = !z.neg;
    }

    function sub(Int memory a, Int memory b) internal pure returns (Int memory z) {
        // OPT: previously add(a, negate(b)) — negate clones the whole limb array.
        // Inline the sign flip instead. (Canonical zero b: bn=true routes to the
        // compare branch, where _ucmp handles it correctly.)
        bool bn = !b.neg;
        if (a.neg == bn) {
            z.neg = a.neg;
            z.limbs = _uadd(a.limbs, b.limbs);
        } else {
            int256 c = _ucmp(a.limbs, b.limbs);
            if (c == 0) { z.limbs = new uint256[](1); return z; }
            if (c > 0) { z.neg = a.neg; z.limbs = _usub(a.limbs, b.limbs); }
            else { z.neg = bn; z.limbs = _usub(b.limbs, a.limbs); }
        }
        _trim(z);
    }

    // ----------------------------------------------------------------
    // multiply (schoolbook with 256x256->512 word products)
    // ----------------------------------------------------------------

    function mul(Int memory a, Int memory b) internal pure returns (Int memory z) {
        uint256 la = a.limbs.length; uint256 lb = b.limbs.length;
        uint256[] memory r = new uint256[](la + lb);
        for (uint256 i = 0; i < la; i++) {
            uint256 carry = 0;
            uint256 ai = a.limbs[i];
            if (ai == 0) continue;
            for (uint256 j = 0; j < lb; j++) {
                (uint256 hi, uint256 lo) = _mul512(ai, b.limbs[j]);
                unchecked {
                    uint256 s = r[i + j] + lo;
                    uint256 c1 = s < lo ? 1 : 0;
                    uint256 s2 = s + carry;
                    uint256 c2 = s2 < carry ? 1 : 0;
                    r[i + j] = s2;
                    carry = hi + c1 + c2;
                }
            }
            r[i + lb] += carry;
        }
        z.neg = a.neg != b.neg;
        z.limbs = r;
        _trim(z);
    }

    /// @dev 256x256 -> 512 bit product (hi, lo). Same trick as Cicada / mathemagic.
    function _mul512(uint256 x, uint256 y) private pure returns (uint256 hi, uint256 lo) {
        assembly {
            let mm := mulmod(x, y, not(0))
            lo := mul(x, y)
            hi := sub(sub(mm, lo), lt(mm, lo))
        }
    }

    // ----------------------------------------------------------------
    // long division: (a, b) -> (q, r) with a = q*b + r, sign-magnitude,
    // floor semantics matching Python (// and %).
    // ----------------------------------------------------------------

    /// @dev word-level long division (Knuth Algorithm D, base 2^256) of magnitudes.
    ///      Division dominates composition cost (xgcd calls it repeatedly), so this is
    ///      the single biggest gas win over the previous bit-by-bit version.
    function _udivmod(uint256[] memory a, uint256[] memory b)
        private pure returns (uint256[] memory q, uint256[] memory r)
    {
        uint256 n = _sig(b);
        require(n != 0, "div0");
        uint256 m = _sig(a);
        if (n == 1) return _divSmall(a, m, b[0]);
        if (_ucmp(a, b) < 0) {
            q = new uint256[](1);
            r = _copy(a, m == 0 ? 1 : m);
            return (q, r);
        }
        uint256 shift = _clz(b[n - 1]);
        uint256[] memory u = _shlBits(a, shift, m + 1);
        uint256[] memory v = _shlBits(b, shift, n);
        uint256 vTop = v[n - 1];
        uint256 vSec = v[n - 2];
        q = new uint256[](m - n + 1);
        for (uint256 j = m - n + 1; j > 0; ) {
            j--;
            uint256 uHi = u[j + n];
            uint256 uLo = u[j + n - 1];
            // D3. estimate qhat = floor((uHi*B + uLo) / vTop), clamped to B-1
            uint256 qhat;
            uint256 rhat;
            bool rhatOverflow;
            if (uHi >= vTop) {
                // quotient would be >= B, clamp to B-1; rhat = uHi*B+uLo - (B-1)*vTop
                qhat = type(uint256).max;
                // rhat = (uHi - vTop)*B + uLo + vTop  -> track overflow past B
                unchecked {
                    uint256 hiPart = uHi - vTop;      // >= 0
                    rhat = uLo + vTop;
                    uint256 c = rhat < uLo ? 1 : 0;   // carry into high
                    rhatOverflow = (hiPart != 0) || (c != 0);
                }
            } else {
                (qhat, rhat) = _div512by256(uHi, uLo, vTop);
                rhatOverflow = false;
            }
            // D3 correction: while qhat*vSec > rhat*B + u[j+n-2], decrement.
            if (!rhatOverflow) {
                uint256 uNext = u[j + n - 2];
                unchecked {
                    while (true) {
                        (uint256 phi, uint256 plo) = _mul(qhat, vSec);
                        if (phi > rhat || (phi == rhat && plo > uNext)) {
                            qhat--;
                            uint256 nr = rhat + vTop;
                            if (nr < rhat) break; // rhat >= B now, correction can't trigger
                            rhat = nr;
                        } else break;
                    }
                }
            }
            // D4. multiply and subtract
            bool negBorrow = _muSub(u, v, qhat, j, n);
            // D5/D6. add back if we overshot
            if (negBorrow) {
                qhat--;
                uint256 c2 = 0;
                for (uint256 i = 0; i < n; i++) {
                    unchecked {
                        uint256 s = u[j + i] + v[i];
                        uint256 c1 = s < u[j + i] ? 1 : 0;
                        uint256 s2 = s + c2;
                        c2 = c1 + (s2 < s ? 1 : 0);
                        u[j + i] = s2;
                    }
                }
                unchecked { u[j + n] += c2; }
            }
            q[j] = qhat;
        }
        r = _finish(u, n, shift);
    }

    /// @dev u[j..j+n] -= qhat * v[0..n]; returns true on overshoot (went negative).
    function _muSub(uint256[] memory u, uint256[] memory v, uint256 qhat, uint256 j, uint256 n)
        private pure returns (bool negBorrow)
    {
        uint256 borrow = 0;
        uint256 carry = 0;
        for (uint256 i = 0; i < n; i++) {
            (uint256 phi, uint256 plo) = _mul(qhat, v[i]);
            unchecked {
                uint256 sub1 = plo + carry;
                carry = phi + (sub1 < plo ? 1 : 0);
                uint256 uij = u[j + i];
                uint256 d = uij - sub1;
                uint256 bb = uij < sub1 ? 1 : 0;
                uint256 d2 = d - borrow;
                borrow = bb + (d < borrow ? 1 : 0);
                u[j + i] = d2;
            }
        }
        unchecked {
            uint256 ujn = u[j + n];
            uint256 tot = carry + borrow;
            u[j + n] = ujn - tot;
            negBorrow = ujn < tot;
        }
    }

    function _finish(uint256[] memory u, uint256 n, uint256 shift)
        private pure returns (uint256[] memory r)
    {
        uint256[] memory rem = new uint256[](n);
        for (uint256 i = 0; i < n; i++) rem[i] = u[i];
        r = _shrBits(rem, shift);
    }

    function _divSmall(uint256[] memory a, uint256 m, uint256 d)
        private pure returns (uint256[] memory q, uint256[] memory r)
    {
        if (m == 0) { q = new uint256[](1); r = new uint256[](1); return (q, r); }
        q = new uint256[](m);
        uint256 rem = 0;
        for (uint256 i = m; i > 0; ) {
            i--;
            (uint256 qi, uint256 ri) = _div512by256(rem, a[i], d);
            q[i] = qi; rem = ri;
        }
        r = new uint256[](1); r[0] = rem;
    }

    function _sig(uint256[] memory a) private pure returns (uint256 n) {
        n = a.length;
        while (n > 0 && a[n - 1] == 0) n--;
    }
    function _copy(uint256[] memory a, uint256 n) private pure returns (uint256[] memory r) {
        r = new uint256[](n);
        for (uint256 i = 0; i < n && i < a.length; i++) r[i] = a[i];
    }
    function _clz(uint256 x) private pure returns (uint256 nn) {
        // OPT NIVO 2: binary search (8 steps) instead of a bit loop of up to
        // 256 iterations — _clz runs once per divmod on the divisor's top limb.
        if (x == 0) return 256;
        if (x >> 128 == 0) { nn += 128; x <<= 128; }
        if (x >> 192 == 0) { nn += 64; x <<= 64; }
        if (x >> 224 == 0) { nn += 32; x <<= 32; }
        if (x >> 240 == 0) { nn += 16; x <<= 16; }
        if (x >> 248 == 0) { nn += 8; x <<= 8; }
        if (x >> 252 == 0) { nn += 4; x <<= 4; }
        if (x >> 254 == 0) { nn += 2; x <<= 2; }
        if (x >> 255 == 0) { nn += 1; }
    }
    /// @dev (hi:lo)/d -> (q,r), requires hi < d so q fits 256 bits. Warren's "divlu"
    ///      (Hacker's Delight fig.9-3) at base 2^128: native div for digit estimates
    ///      instead of a 256-iteration bit loop. Intermediates wrap mod 2^256 but the
    ///      results (< d < 2^256) are exact -- standard overflow-cancellation argument.
    function _div512by256(uint256 hi, uint256 lo, uint256 d)
        private pure returns (uint256 q, uint256 r)
    {
        require(hi < d, "ovf");
        if (hi == 0) { return (lo / d, lo % d); } // native fast path
        unchecked {
            uint256 B128 = 1 << 128;
            uint256 s = _clz(d);                 // normalize divisor: top bit set
            uint256 v = d << s;
            uint256 vn1 = v >> 128;
            uint256 vn0 = v & (B128 - 1);
            uint256 un64 = s == 0 ? hi : (hi << s) | (lo >> (256 - s));
            uint256 un10 = lo << s;
            uint256 un1 = un10 >> 128;
            uint256 un0 = un10 & (B128 - 1);

            uint256 q1 = un64 / vn1;
            uint256 rhat = un64 - q1 * vn1;
            while (q1 >= B128 || (rhat < B128 && q1 * vn0 > (rhat << 128) + un1)) {
                q1 -= 1; rhat += vn1;
                if (rhat >= B128) break;
            }
            uint256 un21 = un64 * B128 + un1 - q1 * v; // wraps mod 2^256; exact (< v)

            uint256 q0 = un21 / vn1;
            rhat = un21 - q0 * vn1;
            while (q0 >= B128 || (rhat < B128 && q0 * vn0 > (rhat << 128) + un0)) {
                q0 -= 1; rhat += vn1;
                if (rhat >= B128) break;
            }
            q = q1 * B128 + q0;
            r = (un21 * B128 + un0 - q0 * v) >> s;  // wraps mod 2^256; exact (< d)
        }
    }
    function _mul(uint256 x, uint256 y) private pure returns (uint256 hi, uint256 lo) {
        assembly {
            let mm := mulmod(x, y, not(0))
            lo := mul(x, y)
            hi := sub(sub(mm, lo), lt(mm, lo))
        }
    }
    function _shlBits(uint256[] memory a, uint256 bits, uint256 outLen)
        private pure returns (uint256[] memory r)
    {
        r = new uint256[](outLen);
        if (bits == 0) {
            for (uint256 i = 0; i < a.length && i < outLen; i++) r[i] = a[i];
            return r;
        }
        uint256 carry = 0;
        for (uint256 i = 0; i < outLen; i++) {
            uint256 ai = i < a.length ? a[i] : 0;
            r[i] = (ai << bits) | carry;
            carry = ai >> (256 - bits);
        }
        return r;
    }
    function _shrBits(uint256[] memory a, uint256 bits)
        private pure returns (uint256[] memory r)
    {
        uint256 nn = a.length;
        r = new uint256[](nn);
        if (bits == 0) { for (uint256 i=0;i<nn;i++) r[i]=a[i]; return r; }
        for (uint256 i = 0; i < nn; i++) {
            uint256 lo = a[i] >> bits;
            uint256 hi = i + 1 < nn ? (a[i + 1] << (256 - bits)) : 0;
            r[i] = lo | hi;
        }
        return r;
    }
    /// @dev floor division and modulo (Python semantics), signed.
    function divmod(Int memory a, Int memory b)
        internal pure returns (Int memory q, Int memory r)
    {
        require(!isZero(b), "div by zero");
        (uint256[] memory uq, uint256[] memory ur) = _udivmod(a.limbs, b.limbs);
        // truncated result
        q.limbs = uq; r.limbs = ur;
        q.neg = a.neg != b.neg;
        r.neg = a.neg;
        _trim(q); _trim(r);
        // adjust to floor semantics: if remainder != 0 and signs differ, q -=1, r += b
        if (!isZero(r) && (a.neg != b.neg)) {
            q = sub(q, fromUint(1));
            r = add(r, b);
        }
    }

    function fdiv(Int memory a, Int memory b) internal pure returns (Int memory q) {
        (q, ) = divmod(a, b);
    }
    function fmod(Int memory a, Int memory b) internal pure returns (Int memory r) {
        (, r) = divmod(a, b);
    }

    // ----------------------------------------------------------------
    // comparison / gcd / extended gcd
    // ----------------------------------------------------------------

    function cmp(Int memory a, Int memory b) internal pure returns (int256) {
        if (a.neg != b.neg) return a.neg ? int256(-1) : int256(1);
        int256 m = _ucmp(a.limbs, b.limbs);
        return a.neg ? -m : m;
    }

    function abs(Int memory a) internal pure returns (Int memory z) {
        z = clone(a); z.neg = false;
    }

    /// @dev extended gcd: returns (g, x, y) with a*x + b*y = g >= 0
    function xgcd(Int memory a, Int memory b)
        internal pure returns (Int memory g, Int memory x, Int memory y)
    {
        Int memory old_r = clone(a);
        Int memory r = clone(b);
        Int memory old_s = fromUint(1);
        Int memory s = fromUint(0);
        Int memory old_t = fromUint(0);
        Int memory t = fromUint(1);
        while (!isZero(r)) {
            // OPT: divmod already computed the remainder — reuse it instead of
            // recomputing old_r - q*r with a full bignum mul + sub per iteration.
            (Int memory q, Int memory rem) = divmod(old_r, r);
            (old_r, r) = (r, rem);
            (old_s, s) = (s, sub(old_s, mul(q, s)));
            (old_t, t) = (t, sub(old_t, mul(q, t)));
        }
        if (old_r.neg) { old_r = negate(old_r); old_s = negate(old_s); old_t = negate(old_t); }
        return (old_r, old_s, old_t);
    }

    /// @dev Naive Euclid half-extended gcd — kept ONLY as the differential-fuzz
    ///      reference for the Lehmer engine below. Not used in production paths.
    function xgcdHalfClassic(Int memory a, Int memory b)
        internal pure returns (Int memory g, Int memory x)
    {
        Int memory old_r = clone(a);
        Int memory r = clone(b);
        Int memory old_s = fromUint(1);
        Int memory s = fromUint(0);
        while (!isZero(r)) {
            (Int memory q, Int memory rem) = divmod(old_r, r);
            (old_r, r) = (r, rem);
            (old_s, s) = (s, sub(old_s, mul(q, s)));
        }
        if (old_r.neg) { old_r = negate(old_r); old_s = negate(old_s); }
        return (old_r, old_s);
    }

    // ----------------------------------------------------------------
    // OPT NIVO 2: Lehmer-ov xgcd.
    //
    // Naivni Euklid radi ~245 punih bignum divmod-ova na 512-bitnim ulazima,
    // svaki ~12k gasa => ~3-6M po (x)gcd pozivu. Lehmer izvlaci gornjih 255
    // bitova oba operanda u native reci i sertifikuje kvocijente Knuth 4.5.2
    // uslovom (interval-test sa kofaktorima): dok god su donji (odseceni)
    // bitovi nebitni za kvocijent, korak se izvodi u 256-bitnoj aritmetici
    // (~50 gasa umesto ~12k). Batch koraka se akumulira u 2x2 matricu
    // [[A,B],[C,D]] sa naizmenicnim znacima (parnost prati bool `even`;
    // cuvamo MAGNITUDE) i primenjuje na velike brojeve odjednom.
    //
    // Invarijanta: (x', y') = M*(x, y) i ISTA matrica azurira Bezout par
    // (s0', s1') = M*(s0, s1), jer je Euklidov korak linearan.
    //
    // Bezbednost od gresaka u zaokruzivanju: kvocijent q se primenjuje SAMO
    // ako je q1 == q2, gde su q1/q2 gornja/donja granica pravog kvocijenta
    // uz najgori slucaj odsecenih bitova (izvedeno iz U ∈ ((u−Bm)2^k,(u+Am)2^k),
    // V ∈ ((v−Cm)2^k,(v+Dm)2^k) za parnu parnost, simetricno za neparnu).
    // Ako sertifikacija ne uspe iz prve (retko: ogromni kvocijenti, u≈v),
    // radi se JEDAN pun bignum divmod korak — korektnost nikad ne zavisi od
    // aproksimacije.
    // ----------------------------------------------------------------

    /// @dev vrednost >> k, uzeto iz limb niza (little-endian), kao jedna rec
    function _shrWord(uint256[] memory L, uint256 k) private pure returns (uint256 r) {
        uint256 w = k >> 8;         // k / 256
        uint256 o = k & 255;
        uint256 n = L.length;
        if (w >= n) return 0;
        r = L[w] >> o;
        if (o != 0 && w + 1 < n) r |= L[w + 1] << (256 - o);
    }

    /// @dev primena matrice [[±Am,∓Bm],[∓Cm,±Dm]] (znaci po parnosti) na par
    function _applyM(
        Int memory p, Int memory q,
        uint256 Am, uint256 Bm, uint256 Cm, uint256 Dm, bool even
    ) private pure returns (Int memory, Int memory) {
        Int memory ap = mul(fromUint(Am), p);
        Int memory bq = mul(fromUint(Bm), q);
        Int memory cp = mul(fromUint(Cm), p);
        Int memory dq = mul(fromUint(Dm), q);
        if (even) return (sub(ap, bq), sub(dq, cp));
        return (sub(bq, ap), sub(cp, dq));
    }

    /// @dev sertifikovana petlja nad gornjim recima; vraca akumuliranu matricu
    function _certifiedLoop(uint256 u, uint256 v, uint256 BOUND)
        private pure
        returns (uint256 Am, uint256 Bm, uint256 Cm, uint256 Dm, bool even, bool progressed)
    {
        Am = 1; Dm = 1; even = true;
        // BOUND <= 2^126: clanovi < BOUND => nijedan medjuracun ne prekoracuje
        while (true) {
            uint256 q1;
            uint256 q2;
            if (even) {
                // A>=0, B<=0, C<=0, D>=0
                if (v <= Cm || u < Bm) break;
                uint256 d2 = v + Dm;
                q1 = (u + Am) / (v - Cm);
                q2 = (u - Bm) / d2;
            } else {
                // A<=0, B>=0, C>=0, D<=0
                if (v <= Dm || u < Am) break;
                uint256 d2 = v + Cm;
                q1 = (u + Bm) / (v - Dm);
                q2 = (u - Am) / d2;
            }
            if (q1 != q2 || q1 > BOUND) break;
            uint256 nC = Am + q1 * Cm;
            uint256 nD = Bm + q1 * Dm;
            if (nC >= BOUND || nD >= BOUND) break;
            (Am, Bm) = (Cm, Dm);
            (Cm, Dm) = (nC, nD);
            even = !even;
            (u, v) = (v, u - q1 * v);
            progressed = true;
        }
    }

    /// @dev zavrsnica kada oba operanda stanu u jednu rec: egzaktan Euklid u
    ///      native aritmetici, matrica se flush-uje na (s0,s1) tek kad bi
    ///      prekoracila uint256
    function _wordXgcdTail(uint256 u, uint256 v, Int memory s0, Int memory s1)
        private pure returns (Int memory, Int memory)
    {
        uint256 Am = 1; uint256 Bm = 0; uint256 Cm = 0; uint256 Dm = 1;
        bool even = true;
        while (v != 0) {
            uint256 q = u / v;
            bool overflow =
                (Cm != 0 && q > (type(uint256).max - Am) / Cm) ||
                (Dm != 0 && q > (type(uint256).max - Bm) / Dm);
            if (overflow) {
                (s0, s1) = _applyM(s0, s1, Am, Bm, Cm, Dm, even);
                Am = 1; Bm = 0; Cm = 0; Dm = 1; even = true;
                continue; // isti (u,v); sa identitetom straze sigurno prolaze
            }
            uint256 nC = Am + q * Cm;
            uint256 nD = Bm + q * Dm;
            (Am, Bm) = (Cm, Dm);
            (Cm, Dm) = (nC, nD);
            even = !even;
            (u, v) = (v, u - q * v);
        }
        (s0, s1) = _applyM(s0, s1, Am, Bm, Cm, Dm, even);
        return (fromUint(u), s0);
    }

    /// @dev OPT NIVO 2: half-extended gcd preko Lehmer-a — vraca (g, x) sa
    ///      a*x ≡ g (mod b), g >= 0. Isti ugovor kao xgcdHalfClassic.
    function xgcdHalf(Int memory a, Int memory b)
        internal pure returns (Int memory, Int memory)
    {
        Int memory x = abs(a);
        Int memory y = abs(b);
        Int memory s0 = fromUint(1);
        Int memory s1 = fromUint(0);
        uint256 outer;
        while (!isZero(y)) {
            require(++outer < 4096, "lehmer runaway"); // tripwire, nikad u praksi
            if (cmp(x, y) < 0) {
                (x, y) = (y, x);
                (s0, s1) = (s1, s0);
            }
            if (isZero(y)) break; // a == 0 na ulazu: posle swap-a y je nula
            uint256 sx = _sig(x.limbs);
            if (sx == 1) {
                (x, s0) = _wordXgcdTail(x.limbs[0], y.limbs[0], s0, s1);
                break;
            }
            uint256 bl = (sx - 1) * 256 + (256 - _clz(x.limbs[sx - 1]));
            uint256 k = bl - 255; // gornjih 255 bitova: headroom za u+Am
            uint256 u = _shrWord(x.limbs, k);
            uint256 v = _shrWord(y.limbs, k);
            (uint256 Am, uint256 Bm, uint256 Cm, uint256 Dm, bool even, bool ok) =
                _certifiedLoop(u, v, 1 << 126);
            if (!ok) {
                // aproksimacija ne moze da sertifikuje (v premalo / u≈v):
                // jedan pun korak, korektnost ne zavisi od aproksimacije
                (Int memory qq, Int memory rem) = divmodFast(x, y);
                (x, y) = (y, rem);
                (s0, s1) = (s1, sub(s0, mul(qq, s1)));
            } else {
                (x, y) = _applyM(x, y, Am, Bm, Cm, Dm, even);
                require(!x.neg && !y.neg, "lehmer sign"); // teorijski nemoguce
                (s0, s1) = _applyM(s0, s1, Am, Bm, Cm, Dm, even);
            }
        }
        if (a.neg) s0 = negate(s0);
        return (x, s0);
    }

    /// @dev OPT NIVO 2: gcd preko Lehmer engine-a (deli implementaciju sa
    ///      xgcdHalf; kofaktorska azuriranja su sada zanemarljiv deo cene).
    function gcd(Int memory a, Int memory b) internal pure returns (Int memory) {
        (Int memory g, ) = xgcdHalf(a, b);
        return g;
    }

    /// @dev Binarni (Stein) gcd — cuva se ISKLJUCIVO kao nezavisna referentna
    ///      familija algoritama za diferencijalni fuzz Lehmer engine-a.
    function gcdBinary(Int memory a, Int memory b) internal pure returns (Int memory) {
        Int memory x = abs(a);
        Int memory y = abs(b);
        if (isZero(x)) return y;
        if (isZero(y)) return x;
        uint256 shift = 0;
        while ((x.limbs[0] & 1) == 0 && (y.limbs[0] & 1) == 0) {
            x = shr1(x); y = shr1(y); shift++;
        }
        while ((x.limbs[0] & 1) == 0) x = shr1(x);
        while (true) {
            while ((y.limbs[0] & 1) == 0) y = shr1(y);
            if (_ucmp(x.limbs, y.limbs) > 0) { Int memory t = x; x = y; y = t; }
            y = sub(y, x); // y >= x, both odd -> difference even and >= 0
            if (isZero(y)) break;
        }
        while (shift > 0) { x = shl1(x); shift--; }
        return x;
    }

    /// @dev (hi, lo) reci vrednosti |L| >> k
    function _shrWord2(uint256[] memory L, uint256 k)
        private pure returns (uint256 hi, uint256 lo)
    {
        lo = _shrWord(L, k);
        hi = _shrWord(L, k + 256);
    }

    /// @dev OPT NIVO 2: floor divmod sa procenom kvocijenta iz gornjih reci.
    ///      Kada kvocijent staje u jednu rec (tipican slucaj u reduce/normalize
    ///      petljama i Lehmer fallback koracima), kolicnik se proceni jednim
    ///      native _div512by256 pozivom i koriguje za najvise ±1 — dokazivo
    ///      dovoljno uz 255-bitne aproksimacije. Rezultat je egzaktno identican
    ///      divmod-u (ista floor semantika); za velike kvocijente pun fallback.
    function divmodFast(Int memory a, Int memory b)
        internal pure returns (Int memory q, Int memory r)
    {
        require(!isZero(b), "div by zero");
        uint256 sa = _sig(a.limbs);
        if (sa == 0) return (fromUint(0), fromUint(0));
        // |a| < |b|: trunc kolicnik 0 bez ikakvog racuna
        if (_ucmp(a.limbs, b.limbs) < 0) {
            q = fromUint(0);
            r = clone(a);
            if (!isZero(r) && (a.neg != b.neg)) {
                q = negate(fromUint(1));
                r = add(r, b);
            }
            return (q, r);
        }
        uint256 blb;
        {
            uint256 sb = _sig(b.limbs);
            uint256 bla = (sa - 1) * 256 + (256 - _clz(a.limbs[sa - 1]));
            blb = (sb - 1) * 256 + (256 - _clz(b.limbs[sb - 1]));
            if (bla > blb + 200) return divmod(a, b); // kvocijent ne staje u procenu
        }
        uint256 k = blb > 255 ? blb - 255 : 0;
        (uint256 hi, uint256 lo) = _shrWord2(a.limbs, k);
        (uint256 est, ) = _div512by256(hi, lo, _shrWord(b.limbs, k));
        Int memory absB = abs(b);
        Int memory rem = sub(abs(a), mul(fromUint(est), absB));
        uint256 fix;
        while (rem.neg) { require(++fix < 4, "est off"); est--; rem = add(rem, absB); }
        while (_ucmp(rem.limbs, absB.limbs) >= 0) { require(++fix < 4, "est off"); est++; rem = sub(rem, absB); }
        q = fromUint(est);
        q.neg = a.neg != b.neg; // est >= 1 jer je |a| >= |b|
        r = rem;
        r.neg = a.neg && !isZero(rem);
        // floor adjust — identicno divmod-u
        if (!isZero(r) && (a.neg != b.neg)) {
            q = sub(q, fromUint(1));
            r = add(r, b);
        }
    }

    /// @dev broj bitova vrednosti |a| (0 za nulu)
    function bitLen(Int memory a) internal pure returns (uint256) {
        uint256 n = _sig(a.limbs);
        if (n == 0) return 0;
        return (n - 1) * 256 + (256 - _clz(a.limbs[n - 1]));
    }

    /// @dev OPT NIVO 3: parcijalni Euklid za NUDUPL/NUCOMP. Na ulazu a > mu >= 0;
    ///      vraca (r_{k-1}, r_k, beta_{k-1}, beta_k, parnost k) gde je
    ///      r_i = alpha_i*a + beta_i*mu standardni niz ostataka, zaustavljen cim
    ///      bitLen(r_k) <= stopBits. SVAKA tacka zaustavljanja daje validnu
    ///      unimodularnu transformaciju — prag utice samo na balans velicina,
    ///      ne na korektnost. Kvocijenti se batch-uju istim Lehmer engine-om
    ///      (_certifiedLoop) sa dinamickim bound-om da se prag ne prebaci mnogo.
    function _euclidStep(Int memory rP, Int memory rC, Int memory bP, Int memory bC)
        private pure returns (Int memory, Int memory, Int memory, Int memory)
    {
        (Int memory q, Int memory rem) = divmodFast(rP, rC);
        return (rC, rem, bC, sub(bP, mul(q, bC)));
    }

    function _batchFor(Int memory rP, Int memory rC, uint256 stopBits)
        private pure
        returns (uint256, uint256, uint256, uint256, bool, bool)
    {
        uint256 sx = _sig(rP.limbs);
        uint256 k = (sx - 1) * 256 + (256 - _clz(rP.limbs[sx - 1])) - 255;
        uint256 gap = bitLen(rC) - stopBits;
        uint256 bound = gap >= 124 ? (1 << 126) : (uint256(1) << (gap + 2));
        return _certifiedLoop(_shrWord(rP.limbs, k), _shrWord(rC.limbs, k), bound);
    }

    function xgcdPartial(Int memory a, Int memory mu, uint256 stopBits)
        internal pure
        returns (Int memory rP, Int memory rC, Int memory bP, Int memory bC, bool evenTot)
    {
        rP = clone(a);
        rC = clone(mu);
        bP = fromUint(0);
        bC = fromUint(1);
        evenTot = true; // parnost ukupnog broja koraka (true = parno)
        uint256 outer;
        while (!isZero(rC) && bitLen(rC) > stopBits) {
            require(++outer < 4096, "partial runaway");
            if (_sig(rP.limbs) == 1) {
                (rP, rC, bP, bC) = _euclidStep(rP, rC, bP, bC);
                evenTot = !evenTot;
                continue;
            }
            (uint256 Am, uint256 Bm, uint256 Cm, uint256 Dm, bool be, bool ok) =
                _batchFor(rP, rC, stopBits);
            if (!ok) {
                (rP, rC, bP, bC) = _euclidStep(rP, rC, bP, bC);
                evenTot = !evenTot;
            } else {
                (rP, rC) = _applyM(rP, rC, Am, Bm, Cm, Dm, be);
                require(!rP.neg && !rC.neg, "partial sign");
                (bP, bC) = _applyM(bP, bC, Am, Bm, Cm, Dm, be);
                if (!be) evenTot = !evenTot; // batch sa neparnim brojem koraka
            }
        }
    }

    /// @dev true iff value is exactly 1
    function isOne(Int memory a) internal pure returns (bool) {
        if (a.neg) return false;
        uint256 n = a.limbs.length;
        if (n == 0 || a.limbs[0] != 1) return false;
        for (uint256 i = 1; i < n; i++) if (a.limbs[i] != 0) return false;
        return true;
    }

    /// @dev OPT: multiply by 2 as a 1-bit shift (replaces mul(two, x) — no
    ///      schoolbook pass, no _two() allocation).
    function shl1(Int memory a) internal pure returns (Int memory z) {
        uint256 n = a.limbs.length;
        uint256[] memory r = new uint256[](n + 1);
        uint256 carry = 0;
        for (uint256 i = 0; i < n; i++) {
            uint256 ai = a.limbs[i];
            unchecked { r[i] = (ai << 1) | carry; }
            carry = ai >> 255;
        }
        r[n] = carry;
        z.neg = a.neg;
        z.limbs = r;
        _trim(z);
    }

    /// @dev OPT: floor division by 2 as a 1-bit shift. fdiv(x, two) was going
    ///      through the full Knuth/Warren machinery limb by limb.
    function shr1(Int memory a) internal pure returns (Int memory z) {
        uint256 n = a.limbs.length;
        bool odd = (a.limbs[0] & 1) == 1;
        uint256[] memory r = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            uint256 lo = a.limbs[i] >> 1;
            uint256 hi = i + 1 < n ? (a.limbs[i + 1] << 255) : 0;
            r[i] = lo | hi;
        }
        z.neg = a.neg;
        z.limbs = r;
        _trim(z);
        // floor semantics for negative odd values: trunc-toward-zero -> floor
        if (odd && a.neg) z = sub(z, fromUint(1));
    }
}
