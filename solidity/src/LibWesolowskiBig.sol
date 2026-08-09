// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibBigInt as B} from "./LibBigInt.sol";
import {LibClassGroupBig as CG} from "./LibClassGroupBig.sol";

/// @title On-chain Wesolowski verifikacija nad 1024-bit klasnom grupom.
/// @dev Kanonska serijalizacija forme (mora biti IDENTICNA python strani,
///      videti gen_wesolowski_fixture.py): a(128B BE) || sign(b)(1B) ||
///      |b|(128B BE) || c(128B BE). Seed = sha256(ser(u)||ser(w)||T(32B)||
///      |D|(128B BE)); kandidat l = sha256(seed||counter) >> 176 | (1<<79) | 1.
library LibWesolowskiBig {
    function _pad128(B.Int memory x) private pure returns (bytes memory) {
        uint256[] memory L = x.limbs;
        uint256 n = L.length;
        require(n <= 4, "form too wide");
        bytes32 w0; bytes32 w1; bytes32 w2; bytes32 w3;
        if (n > 3) w0 = bytes32(L[3]);
        if (n > 2) w1 = bytes32(L[2]);
        if (n > 1) w2 = bytes32(L[1]);
        w3 = bytes32(L[0]);
        return abi.encodePacked(w0, w1, w2, w3); // big-endian 128 bajtova
    }

    function _ser(CG.Form memory f) private pure returns (bytes memory) {
        return abi.encodePacked(
            _pad128(f.a),
            uint8(f.b.neg ? 1 : 0),
            _pad128(f.b),
            _pad128(f.c)
        );
    }

    function fiatShamirPrime(
        CG.Form memory u, CG.Form memory w, uint256 T, B.Int memory D
    ) internal pure returns (uint256) {
        bytes32 seed = sha256(
            abi.encodePacked(_ser(u), _ser(w), T, _pad128(D))
        );
        for (uint256 counter = 0;; counter++) {
            uint256 cand = uint256(sha256(abi.encodePacked(seed, counter))) >> 176;
            cand |= (1 << 79) | 1;
            if (millerRabin(cand)) return cand;
        }
    }

    /// @notice proverava pi^l * u^r == w  (l Fiat-Shamir prost, r = 2^T mod l)
    function verify(
        CG.Form memory u, CG.Form memory w, CG.Form memory pi,
        uint256 T, B.Int memory D
    ) internal pure returns (bool) {
        uint256 l = fiatShamirPrime(u, w, T, D);
        uint256 r = powmod(2, T, l);
        return CG.eq(CG.shamir(pi, l, u, r, D), CG.reduce(w));
    }

    /// @dev deterministicki Miller-Rabin, 12 baza — dovoljno za 80-bit kandidate
    function millerRabin(uint256 n) internal pure returns (bool) {
        uint256[12] memory bases =
            [uint256(2), 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37];
        for (uint256 i = 0; i < 12; i++) {
            if (n % bases[i] == 0) return n == bases[i];
        }
        uint256 d = n - 1;
        uint256 s = 0;
        while (d & 1 == 0) { d >>= 1; s++; }
        for (uint256 i = 0; i < 12; i++) {
            uint256 x = powmod(bases[i], d, n);
            if (x == 1 || x == n - 1) continue;
            bool passed = false;
            for (uint256 j = 0; j + 1 < s; j++) {
                x = mulmod(x, x, n);
                if (x == n - 1) { passed = true; break; }
            }
            if (!passed) return false;
        }
        return true;
    }

    function powmod(uint256 base, uint256 e, uint256 m) internal pure returns (uint256 r) {
        r = 1 % m;
        base %= m;
        while (e > 0) {
            if (e & 1 == 1) r = mulmod(r, base, m);
            base = mulmod(base, base, m);
            e >>= 1;
        }
    }
}
