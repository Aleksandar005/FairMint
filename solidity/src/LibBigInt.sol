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
        uint256 n = a.limbs.length;
        while (n > 1 && a.limbs[n - 1] == 0) n--;
        if (n != a.limbs.length) {
            uint256[] memory t = new uint256[](n);
            for (uint256 i = 0; i < n; i++) t[i] = a.limbs[i];
            a.limbs = t;
        }
        if (isZero(a)) a.neg = false; // canonical zero
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
        return add(a, negate(b));
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
        if (x == 0) return 256;
        while (x >> 255 == 0) { x <<= 1; nn++; }
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
            (Int memory q, ) = divmod(old_r, r);
            (old_r, r) = (r, sub(old_r, mul(q, r)));
            (old_s, s) = (s, sub(old_s, mul(q, s)));
            (old_t, t) = (t, sub(old_t, mul(q, t)));
        }
        if (old_r.neg) { old_r = negate(old_r); old_s = negate(old_s); old_t = negate(old_t); }
        return (old_r, old_s, old_t);
    }

    function gcd(Int memory a, Int memory b) internal pure returns (Int memory g) {
        (g, , ) = xgcd(a, b);
    }
}
