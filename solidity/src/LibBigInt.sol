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

    function fromUint(uint256 v) internal pure returns (Int memory z) {
        uint256[] memory L;
        assembly {
            L := mload(0x40)
            mstore(L, 1)
            mstore(add(L, 0x20), v)
            mstore(0x40, add(L, 0x40))
        }
        z.limbs = L;
    }

    function fromInt(int256 x) internal pure returns (Int memory z) {
        z.limbs = new uint256[](1);
        if (x < 0) { z.neg = true; z.limbs[0] = uint256(-x); }
        else z.limbs[0] = uint256(x);
        _trim(z);
    }

    function isZero(Int memory a) internal pure returns (bool z) {
        uint256[] memory L = a.limbs;
        assembly {
            z := 1
            let n := mload(L)
            let d := add(L, 0x20)
            for { let i := 0 } lt(i, n) { i := add(i, 1) } {
                if mload(add(d, shl(5, i))) {
                    z := 0
                    break
                }
            }
        }
    }

    function _trim(Int memory a) internal pure {
        uint256[] memory l = a.limbs;
        bool z;
        assembly {
            let n := mload(l)
            let d := add(l, 0x20)
            for { } gt(n, 1) { } {
                if mload(add(d, shl(5, sub(n, 1)))) { break }
                n := sub(n, 1)
            }
            mstore(l, n) // samo skracuje — bez realokacije
            z := and(eq(n, 1), iszero(mload(d)))
        }
        if (z) a.neg = false; // kanonicka nula
    }

    function clone(Int memory a) internal pure returns (Int memory z) {
        z.neg = a.neg;
        uint256[] memory src = a.limbs;
        uint256[] memory dst;
        assembly {
            let bytesLen := shl(5, mload(src))
            dst := mload(0x40)
            mstore(dst, mload(src))
            mcopy(add(dst, 0x20), add(src, 0x20), bytesLen) // cancun
            mstore(0x40, add(add(dst, 0x20), bytesLen))
        }
        z.limbs = dst;
    }

    // ----------------------------------------------------------------
    // unsigned magnitude helpers
    // ----------------------------------------------------------------

    /// @dev compare magnitudes: -1 if |a|<|b|, 0 if equal, 1 if |a|>|b|
    function _ucmp(uint256[] memory a, uint256[] memory b) private pure returns (int256 res) {
        assembly {
            let la := mload(a)
            let lb := mload(b)
            let ad := add(a, 0x20)
            let bd := add(b, 0x20)
            for { } gt(la, 0) { } {
                if mload(add(ad, shl(5, sub(la, 1)))) { break }
                la := sub(la, 1)
            }
            for { } gt(lb, 0) { } {
                if mload(add(bd, shl(5, sub(lb, 1)))) { break }
                lb := sub(lb, 1)
            }
            switch eq(la, lb)
            case 0 {
                switch gt(la, lb)
                case 1 { res := 1 }
                default { res := sub(0, 1) }
            }
            default {
                for { let i := la } gt(i, 0) { i := sub(i, 1) } {
                    let av := mload(add(ad, shl(5, sub(i, 1))))
                    let bv := mload(add(bd, shl(5, sub(i, 1))))
                    if iszero(eq(av, bv)) {
                        switch gt(av, bv)
                        case 1 { res := 1 }
                        default { res := sub(0, 1) }
                        break
                    }
                }
            }
        }
    }

    /// @dev unsigned add: |a| + |b|
    function _uaddRef(uint256[] memory a, uint256[] memory b) internal pure returns (uint256[] memory r) {
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
    function _usubRef(uint256[] memory a, uint256[] memory b) internal pure returns (uint256[] memory r) {
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

    /// @dev OPT NIVO 5: |a|+|b| u asembleru, bez bounds check-ova i zero-init-a
    function _uadd(uint256[] memory a, uint256[] memory b) internal pure returns (uint256[] memory r) {
        assembly {
            let la := mload(a)
            let lb := mload(b)
            if lt(la, lb) { let t := a a := b b := t t := la la := lb lb := t }
            r := mload(0x40)
            mstore(r, add(la, 1))
            let rd := add(r, 0x20)
            let ad := add(a, 0x20)
            let bd := add(b, 0x20)
            let carry := 0
            let i := 0
            for { } lt(i, lb) { i := add(i, 1) } {
                let ai := mload(add(ad, shl(5, i)))
                let sum := add(ai, mload(add(bd, shl(5, i))))
                let c1 := lt(sum, ai)
                let s2 := add(sum, carry)
                mstore(add(rd, shl(5, i)), s2)
                carry := or(c1, lt(s2, sum)) // c1 i c2 ne mogu oba biti 1
            }
            for { } lt(i, la) { i := add(i, 1) } {
                let ai := mload(add(ad, shl(5, i)))
                let s2 := add(ai, carry)
                mstore(add(rd, shl(5, i)), s2)
                carry := lt(s2, ai)
            }
            mstore(add(rd, shl(5, la)), carry)
            mstore(0x40, add(rd, shl(5, add(la, 1))))
        }
    }

    /// @dev OPT NIVO 5: |a|-|b| u asembleru (zahteva |a| >= |b|, kao i ref)
    function _usub(uint256[] memory a, uint256[] memory b) internal pure returns (uint256[] memory r) {
        assembly {
            let la := mload(a)
            let lb := mload(b)
            r := mload(0x40)
            mstore(r, la)
            let rd := add(r, 0x20)
            let ad := add(a, 0x20)
            let bd := add(b, 0x20)
            let borrow := 0
            let i := 0
            for { } lt(i, lb) { i := add(i, 1) } {
                let ai := mload(add(ad, shl(5, i)))
                let bi := mload(add(bd, shl(5, i)))
                let d := sub(ai, bi)
                let b1 := lt(ai, bi)
                let d2 := sub(d, borrow)
                mstore(add(rd, shl(5, i)), d2)
                borrow := or(b1, lt(d, borrow)) // b1 i b2 ne mogu oba biti 1
            }
            for { } lt(i, la) { i := add(i, 1) } {
                let ai := mload(add(ad, shl(5, i)))
                mstore(add(rd, shl(5, i)), sub(ai, borrow))
                borrow := lt(ai, borrow)
            }
            mstore(0x40, add(rd, shl(5, la)))
        }
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

    /// @dev OPT NIVO 12: bez kloniranja (videti abs)
    function negate(Int memory a) internal pure returns (Int memory z) {
        z.limbs = a.limbs;
        z.neg = !a.neg && !isZero(a); // kanonicki: nikad "-0"
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

    /// @dev referentni skolski mul — cuva se ISKLJUCIVO za diferencijalni fuzz
    function _mulRef(Int memory a, Int memory b) internal pure returns (Int memory z) {
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

    /// @dev OPT NIVO 5: skolski mul u asembleru — fullMul preko mulmod(x,y,not(0))
    ///      trika, bez bounds check-ova; akumulator se nulira calldatacopy trikom.
    function mul(Int memory a, Int memory b) internal pure returns (Int memory z) {
        uint256[] memory A = a.limbs;
        uint256[] memory Bb = b.limbs;
        uint256[] memory r;
        assembly {
            let la := mload(A)
            let lb := mload(Bb)
            let n := add(la, lb)
            r := mload(0x40)
            mstore(r, n)
            let rd := add(r, 0x20)
            calldatacopy(rd, calldatasize(), shl(5, n)) // zero-init akumulatora
            mstore(0x40, add(rd, shl(5, n)))
            let ad := add(A, 0x20)
            let bd := add(Bb, 0x20)
            for { let i := 0 } lt(i, la) { i := add(i, 1) } {
                let ai := mload(add(ad, shl(5, i)))
                if ai {
                    let carry := 0
                    let rp := add(rd, shl(5, i))
                    for { let j := 0 } lt(j, lb) { j := add(j, 1) } {
                        let bj := mload(add(bd, shl(5, j)))
                        let lo := mul(ai, bj)
                        let mm := mulmod(ai, bj, not(0))
                        let hi := sub(sub(mm, lo), lt(mm, lo))
                        let pp := add(rp, shl(5, j))
                        let sum := add(mload(pp), lo)
                        let c1 := lt(sum, lo)
                        let s2 := add(sum, carry)
                        let c2 := lt(s2, sum)
                        mstore(pp, s2)
                        carry := add(hi, add(c1, c2))
                    }
                    let pp := add(rp, shl(5, lb))
                    mstore(pp, add(mload(pp), carry))
                }
            }
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
        assembly {
            n := mload(a)
            let d := add(a, 0x20)
            for { } gt(n, 0) { } {
                if mload(add(d, shl(5, sub(n, 1)))) { break }
                n := sub(n, 1)
            }
        }
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

    /// @dev OPT NIVO 12: bez kloniranja — novi header, deljeni limbovi.
    ///      Bezbedno: biblioteka NIKAD ne mutira ulaze (samo _trim, i to na
    ///      sveze alociranim izlazima operacija).
    function abs(Int memory a) internal pure returns (Int memory z) {
        z.limbs = a.limbs;
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
        assembly {
            let w := shr(8, k)
            let n := mload(L)
            if lt(w, n) {
                let o := and(k, 255)
                let d := add(L, 0x20)
                r := shr(o, mload(add(d, shl(5, w))))
                if o {
                    if lt(add(w, 1), n) {
                        r := or(r, shl(sub(256, o), mload(add(d, shl(5, add(w, 1))))))
                    }
                }
            }
        }
    }

    /// @dev OPT NIVO 6: fuzionisano wa*a - wb*b u jednom asemblerskom prolazu:
    ///      dva word-mul-a u scratch regione iste duzine + poredjenje + jedno
    ///      kombinovanje, bez Int medjustruktura, fromUint-a i po-proizvodnih
    ///      _trim prolaza. Znak: razliciti znaci => sabiranje magnitude (znak a);
    ///      isti znak => oduzimanje vece magnitude (znak po poretku).
    function _fms(uint256 wa, Int memory a, uint256 wb, Int memory b)
        internal pure returns (Int memory z)
    {
        uint256[] memory A = a.limbs;
        uint256[] memory Bl = b.limbs;
        bool diff = a.neg != b.neg;
        uint256[] memory r;
        uint256 ge; // 1 ako je wa*|a| >= wb*|b| (samo za isti znak)
        assembly {
            function wmul(w, src, dst, n) {
                let carry := 0
                let sd := add(src, 0x20)
                for { let j := 0 } lt(j, n) { j := add(j, 1) } {
                    let sv := mload(add(sd, shl(5, j)))
                    let lo := mul(w, sv)
                    let mm := mulmod(w, sv, not(0))
                    let hi := sub(sub(mm, lo), lt(mm, lo))
                    let sum := add(lo, carry)
                    mstore(add(dst, shl(5, j)), sum)
                    carry := add(hi, lt(sum, lo))
                }
                mstore(add(dst, shl(5, n)), carry)
            }
            let la := mload(A)
            let lb := mload(Bl)
            let m := add(la, 1)
            if lt(la, lb) { m := add(lb, 1) }
            let fmp := mload(0x40)
            let pd := fmp                       // scratch P: m reci
            let qd := add(fmp, shl(5, m))       // scratch Q: m reci
            calldatacopy(pd, calldatasize(), shl(6, m)) // nula P i Q odjednom
            wmul(wa, A, pd, la)
            wmul(wb, Bl, qd, lb)
            r := add(qd, shl(5, m))             // rezultat: m+1 reci
            mstore(r, add(m, 1))
            let rd := add(r, 0x20)
            mstore(0x40, add(rd, shl(5, add(m, 1))))
            switch diff
            case 1 {
                // razliciti znaci: R = P + Q
                let carry := 0
                for { let i := 0 } lt(i, m) { i := add(i, 1) } {
                    let av := mload(add(pd, shl(5, i)))
                    let sum := add(av, mload(add(qd, shl(5, i))))
                    let c1 := lt(sum, av)
                    let s2 := add(sum, carry)
                    mstore(add(rd, shl(5, i)), s2)
                    carry := or(c1, lt(s2, sum))
                }
                mstore(add(rd, shl(5, m)), carry)
                ge := 1
            }
            default {
                // isti znak: poredi pa oduzmi vecu - manju
                ge := 1
                for { let i := m } gt(i, 0) { i := sub(i, 1) } {
                    let av := mload(add(pd, shl(5, sub(i, 1))))
                    let bv := mload(add(qd, shl(5, sub(i, 1))))
                    if iszero(eq(av, bv)) {
                        ge := gt(av, bv)
                        break
                    }
                }
                let xd := pd
                let yd := qd
                if iszero(ge) { xd := qd yd := pd }
                let borrow := 0
                for { let i := 0 } lt(i, m) { i := add(i, 1) } {
                    let av := mload(add(xd, shl(5, i)))
                    let bv := mload(add(yd, shl(5, i)))
                    let d := sub(av, bv)
                    let b1 := lt(av, bv)
                    let d2 := sub(d, borrow)
                    mstore(add(rd, shl(5, i)), d2)
                    borrow := or(b1, lt(d, borrow))
                }
                mstore(add(rd, shl(5, m)), 0)
            }
        }
        // znak: razliciti znaci -> znak a; isti znak -> znak a ako P>=Q, inace suprotan
        z.neg = diff ? a.neg : (ge == 1 ? a.neg : !a.neg);
        z.limbs = r;
        _trim(z);
    }

    /// @dev primena matrice [[±Am,∓Bm],[∓Cm,±Dm]] (znaci po parnosti) na par
    function _applyM(
        Int memory p, Int memory q,
        uint256 Am, uint256 Bm, uint256 Cm, uint256 Dm, bool even
    ) private pure returns (Int memory, Int memory) {
        if (even) return (_fms(Am, p, Bm, q), _fms(Dm, q, Cm, p));
        return (_fms(Bm, q, Am, p), _fms(Cm, p, Dm, q));
    }

    /// @dev sertifikovana petlja nad gornjim recima; vraca akumuliranu matricu
    function _certifiedLoop(uint256 u, uint256 v, uint256 BOUND)
        private pure
        returns (uint256 Am, uint256 Bm, uint256 Cm, uint256 Dm, bool even, bool progressed)
    {
        Am = 1; Dm = 1; even = true;
        // BOUND <= 2^126: clanovi < BOUND => nijedan medjuracun ne prekoracuje
        unchecked { // OPT NIVO 11: granice dokazane — bez checked overhead-a
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
        } // unchecked
    }

    /// @dev zavrsnica kada oba operanda stanu u jednu rec: egzaktan Euklid u
    ///      native aritmetici, matrica se flush-uje na (s0,s1) tek kad bi
    ///      prekoracila uint256
    function _wordXgcdTail(uint256 u, uint256 v, Int memory s0, Int memory s1)
        private pure returns (Int memory, Int memory)
    {
        uint256 Am = 1; uint256 Bm = 0; uint256 Cm = 0; uint256 Dm = 1;
        bool even = true;
        unchecked { // OPT NIVO 11: overflow strazari vec cuvaju nC/nD; q = floor(u/v)
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
        } // unchecked
        (s0, s1) = _applyM(s0, s1, Am, Bm, Cm, Dm, even);
        return (fromUint(u), s0);
    }

    // ---------------- OPT NIVO 13: stack-Lehmer za <=2-limb operande ----------------
    // Ceo half-xgcd u registrima: vrednosti kao (lo,hi) parovi, kofaktori kao
    // MAGNITUDE sa znakom iz alternacije (aditivna rekurencija — nema
    // ponistavanja: |s'| = Am|s0| + Bm|s1|). Redak necertifikovani korak
    // boksuje u Int i koristi genericki put.

    function _mul21(uint256 w, uint256 lo, uint256 hi)
        private pure returns (uint256 p0, uint256 p1, uint256 p2)
    {
        unchecked {
            (uint256 h1, uint256 l1) = _mul(w, lo);
            (uint256 h2, uint256 l2) = _mul(w, hi);
            p0 = l1;
            p1 = h1 + l2;
            p2 = h2 + (p1 < h1 ? 1 : 0);
        }
    }

    /// @dev (a3 - b3) za 3-word nenegativne; require rezultat staje u 2 reci
    function _sub32(uint256 a0, uint256 a1, uint256 a2, uint256 b0, uint256 b1, uint256 b2)
        private pure returns (uint256 r0, uint256 r1)
    {
        unchecked {
            r0 = a0 - b0;
            uint256 br = a0 < b0 ? 1 : 0;
            r1 = a1 - b1 - br;
            br = (a1 < b1 || (a1 == b1 && br == 1)) ? 1 : 0;
            require(a2 - b2 - br == 0, "l2 top"); // teorija: pravi ostatak < 2^512
        }
    }

    function _add32(uint256 a0, uint256 a1, uint256 a2, uint256 b0, uint256 b1, uint256 b2)
        private pure returns (uint256 r0, uint256 r1)
    {
        unchecked {
            r0 = a0 + b0;
            uint256 c = r0 < a0 ? 1 : 0;
            r1 = a1 + b1 + c;
            c = (r1 < a1 || (r1 == a1 && c == 1)) ? 1 : 0;
            require(a2 + b2 + c == 0, "l2 cof"); // |s| <= modul < 2^512
        }
    }

    /// @dev primeni (Am..Dm, be) ADITIVNO na kofaktorske magnitude + parnost;
    ///      cof = [m0l, m0h, m1l, m1h, sn] — mutira se u mestu
    function _flush2(uint256 Am, uint256 Bm, uint256 Cm, uint256 Dm, bool be, uint256[5] memory cof)
        private pure
    {
        (uint256 a0, uint256 a1, uint256 a2) = _mul21(Am, cof[0], cof[1]);
        (uint256 b0, uint256 b1, uint256 b2) = _mul21(Bm, cof[2], cof[3]);
        (uint256 n0l, uint256 n0h) = _add32(a0, a1, a2, b0, b1, b2);
        (a0, a1, a2) = _mul21(Cm, cof[0], cof[1]);
        (b0, b1, b2) = _mul21(Dm, cof[2], cof[3]);
        (uint256 n1l, uint256 n1h) = _add32(a0, a1, a2, b0, b1, b2);
        cof[0] = n0l; cof[1] = n0h; cof[2] = n1l; cof[3] = n1h;
        if (!be) cof[4] ^= 1;
    }

    /// @dev w1*v1 - w2*v2 nad 2-word vrednostima (rezultat staje u 2 reci)
    function _applyVal2(uint256 w1, uint256 v1l, uint256 v1h, uint256 w2, uint256 v2l, uint256 v2h)
        private pure returns (uint256, uint256)
    {
        (uint256 a0, uint256 a1, uint256 a2) = _mul21(w1, v1l, v1h);
        (uint256 b0, uint256 b1, uint256 b2) = _mul21(w2, v2l, v2h);
        return _sub32(a0, a1, a2, b0, b1, b2);
    }

    function _applyBatch2(
        uint256 x0, uint256 x1, uint256 y0, uint256 y1,
        uint256 Am, uint256 Bm, uint256 Cm, uint256 Dm, bool be,
        uint256[5] memory cof
    ) private pure returns (uint256, uint256, uint256, uint256) {
        uint256 nx0;
        uint256 nx1;
        if (be) {
            (nx0, nx1) = _applyVal2(Am, x0, x1, Bm, y0, y1);
            (y0, y1) = _applyVal2(Dm, y0, y1, Cm, x0, x1);
        } else {
            (nx0, nx1) = _applyVal2(Bm, y0, y1, Am, x0, x1);
            (y0, y1) = _applyVal2(Cm, x0, x1, Dm, y0, y1);
        }
        _flush2(Am, Bm, Cm, Dm, be, cof);
        return (nx0, nx1, y0, y1);
    }

    function _xgcdHalf2(uint256 x0, uint256 x1, uint256 y0, uint256 y1)
        private pure
        returns (uint256, uint256, uint256, uint256, bool)
    {
        uint256[5] memory cof;
        cof[0] = 1; // m0 = 1, m1 = 0, sn = 0
        uint256 guard;
        while (y0 | y1 != 0) {
            require(++guard < 4096, "l2 runaway");
            if (x1 < y1 || (x1 == y1 && x0 < y0)) {
                (x0, y0) = (y0, x0);
                (x1, y1) = (y1, x1);
                (cof[0], cof[2]) = (cof[2], cof[0]);
                (cof[1], cof[3]) = (cof[3], cof[1]);
                cof[4] ^= 1;
                if (y0 | y1 == 0) break; // a == 0 na ulazu
            }
            if (x1 == 0) {
                uint256 Am = 1; uint256 Bm = 0; uint256 Cm = 0; uint256 Dm = 1;
                bool be = true;
                unchecked {
                    while (y0 != 0) {
                        uint256 q = x0 / y0;
                        if (
                            (Cm != 0 && q > (type(uint256).max - Am) / Cm) ||
                            (Dm != 0 && q > (type(uint256).max - Bm) / Dm)
                        ) {
                            _flush2(Am, Bm, Cm, Dm, be, cof);
                            Am = 1; Bm = 0; Cm = 0; Dm = 1; be = true;
                            continue;
                        }
                        uint256 nC = Am + q * Cm;
                        uint256 nD = Bm + q * Dm;
                        (Am, Bm) = (Cm, Dm);
                        (Cm, Dm) = (nC, nD);
                        be = !be;
                        (x0, y0) = (y0, x0 - q * y0);
                    }
                }
                _flush2(Am, Bm, Cm, Dm, be, cof);
                y1 = 0;
                break;
            }
            uint256 u;
            uint256 v;
            unchecked {
                uint256 k = 512 - _clz(x1) - 255; // x1 != 0 => bl in (256,512]
                if (k < 256) {
                    u = (x1 << (256 - k)) | (x0 >> k);
                    v = (y1 << (256 - k)) | (y0 >> k);
                } else {
                    u = x1 >> (k - 256);
                    v = y1 >> (k - 256);
                }
            }
            (uint256 Am2, uint256 Bm2, uint256 Cm2, uint256 Dm2, bool be2, bool ok) =
                _certifiedLoop(u, v, 1 << 126);
            if (!ok) {
                (x0, x1, y0, y1) = _fallback2(x0, x1, y0, y1, cof);
                continue;
            }
            (x0, x1, y0, y1) = _applyBatch2(x0, x1, y0, y1, Am2, Bm2, Cm2, Dm2, be2, cof);
        }
        return (x0, x1, cof[0], cof[1], cof[4] == 1);
    }


    /// @dev redak necertifikovani korak: boksuj, pun divmodFast, azuriraj
    ///      magnitude aditivno (|s_new| = m0 + q*m1, znak = znak starog s0)
    function _fallback2(uint256 x0, uint256 x1, uint256 y0, uint256 y1, uint256[5] memory cof)
        private pure returns (uint256, uint256, uint256, uint256)
    {
        (Int memory q, Int memory rem) = divmodFast(_box2(x0, x1), _box2(y0, y1));
        Int memory nm = add(_box2(cof[0], cof[1]), mul(q, _box2(cof[2], cof[3])));
        require(_sig(rem.limbs) <= 2 && _sig(nm.limbs) <= 2, "l2 fb");
        (cof[0], cof[1]) = (cof[2], cof[3]);
        cof[2] = nm.limbs.length > 0 ? nm.limbs[0] : 0;
        cof[3] = nm.limbs.length > 1 ? nm.limbs[1] : 0;
        cof[4] ^= 1;
        return (
            y0, y1,
            rem.limbs.length > 0 ? rem.limbs[0] : 0,
            rem.limbs.length > 1 ? rem.limbs[1] : 0
        );
    }

    function _box2(uint256 lo, uint256 hi) private pure returns (Int memory z) {
        uint256[] memory L = new uint256[](2);
        L[0] = lo;
        L[1] = hi;
        z.limbs = L;
        _trim(z);
    }

    /// @dev OPT NIVO 2: half-extended gcd preko Lehmer-a — vraca (g, x) sa
    ///      a*x ≡ g (mod b), g >= 0. Isti ugovor kao xgcdHalfClassic.
    function xgcdHalf(Int memory a, Int memory b)
        internal pure returns (Int memory, Int memory)
    {
        {
            // OPT NIVO 13: stack staza za <=2-limb operande (svi vruci pozivi)
            uint256 sx_ = _sig(a.limbs);
            uint256 sy_ = _sig(b.limbs);
            if (sx_ <= 2 && sy_ <= 2) {
                (uint256 gg0, uint256 gg1, uint256 ssl, uint256 ssh, bool ssn) = _xgcdHalf2(
                    sx_ > 0 ? a.limbs[0] : 0, sx_ > 1 ? a.limbs[1] : 0,
                    sy_ > 0 ? b.limbs[0] : 0, sy_ > 1 ? b.limbs[1] : 0
                );
                Int memory gOut = _box2(gg0, gg1);
                Int memory xOut = _box2(ssl, ssh);
                xOut.neg = (ssn != a.neg) && !isZero(xOut);
                return (gOut, xOut);
            }
        }
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
            if (bla > blb + 253) return divmod(a, b); // hi < bt vazi do blb+254; est greska < 2 do 2^253
        }
        uint256 k = blb > 255 ? blb - 255 : 0;
        (uint256 hi, uint256 lo) = _shrWord2(a.limbs, k);
        (uint256 est, ) = _div512by256(hi, lo, _shrWord(b.limbs, k));
        Int memory absB = abs(b);
        Int memory rem = _fms(1, abs(a), est, absB); // |a| - est*|b| u jednom prolazu
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

    function _bl2(uint256 lo, uint256 hi) private pure returns (uint256) {
        if (hi != 0) return 512 - _clz(hi);
        if (lo != 0) return 256 - _clz(lo);
        return 0;
    }

    /// @dev OPT NIVO 15: stack xgcdPartial za <=2-limb (a, mu). Bez swap-ova
    ///      (invarijanta rP > rC), kofaktori krecu od (0, 1); ista aditivna
    ///      magnitude+parnost masinerija kao _xgcdHalf2.
    function _xgcdPartial2(uint256 x0, uint256 x1, uint256 y0, uint256 y1, uint256 stopBits)
        private pure
        returns (uint256, uint256, uint256, uint256, uint256[5] memory cof)
    {
        cof[2] = 1; // m0(beta_{k-1}) = 0, m1(beta_k) = 1, parnost k u cof[4]
        uint256 guard;
        while ((y0 | y1) != 0 && _bl2(y0, y1) > stopBits) {
            require(++guard < 4096, "p2 runaway");
            if (x1 == 0) {
                // stopBits < 256 (manji D): retko — pojedinacni boksovani koraci
                (x0, x1, y0, y1) = _fallback2(x0, x1, y0, y1, cof);
                continue;
            }
            uint256 u;
            uint256 v;
            uint256 bound;
            unchecked {
                uint256 k = 512 - _clz(x1) - 255;
                if (k < 256) {
                    u = (x1 << (256 - k)) | (x0 >> k);
                    v = (y1 << (256 - k)) | (y0 >> k);
                } else {
                    u = x1 >> (k - 256);
                    v = y1 >> (k - 256);
                }
                uint256 gap = _bl2(y0, y1) - stopBits;
                bound = gap >= 124 ? (1 << 126) : (uint256(1) << (gap + 2));
            }
            (uint256 Am, uint256 Bm, uint256 Cm, uint256 Dm, bool be, bool ok) =
                _certifiedLoop(u, v, bound);
            if (!ok) {
                (x0, x1, y0, y1) = _fallback2(x0, x1, y0, y1, cof);
                continue;
            }
            (x0, x1, y0, y1) = _applyBatch2(x0, x1, y0, y1, Am, Bm, Cm, Dm, be, cof);
        }
        return (x0, x1, y0, y1, cof);
    }

    function xgcdPartial(Int memory a, Int memory mu, uint256 stopBits)
        internal pure
        returns (Int memory rP, Int memory rC, Int memory bP, Int memory bC, bool evenTot)
    {
        if (_sig(a.limbs) <= 2) {
            // OPT NIVO 15: stack staza (mu < a => i mu staje u 2 reci)
            uint256 sa_ = _sig(a.limbs);
            uint256 sm_ = _sig(mu.limbs);
            (uint256 p0, uint256 p1, uint256 c0, uint256 c1, uint256[5] memory cf) = _xgcdPartial2(
                sa_ > 0 ? a.limbs[0] : 0, sa_ > 1 ? a.limbs[1] : 0,
                sm_ > 0 ? mu.limbs[0] : 0, sm_ > 1 ? mu.limbs[1] : 0,
                stopBits
            );
            rP = _box2(p0, p1);
            rC = _box2(c0, c1);
            bP = _box2(cf[0], cf[1]);
            bC = _box2(cf[2], cf[3]);
            evenTot = cf[4] == 0;
            // znaci: sign(beta_k) = (-1)^k ; sign(beta_{k-1}) suprotan
            bC.neg = !evenTot && !isZero(bC);
            bP.neg = evenTot && !isZero(bP);
            return (rP, rC, bP, bC, evenTot);
        }
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
