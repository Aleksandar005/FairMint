// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibClassGroup as CG} from "./LibClassGroup.sol";

/// @title TimelockVault — "transakcija se otključava tek nakon T"
/// @notice Ugovor drži ETH uz timelock puzzle (u, T). Sredstva se puštaju
///         SAMO uz (w, π) gde Wesolowski provera potvrđuje w = u^(2^T).
///         Ugovor NIKAD ne radi T kvadriranja — samo ~2×80 grupovnih
///         operacija verifikacije, nezavisno od T. To je cela poenta.
contract TimelockVault {
    using CG for CG.Form;

    int256 public immutable D; // javna diskriminanta grupe
    uint256 public immutable T; // broj sekvencijalnih kvadriranja

    struct Puzzle {
        CG.Form u; // brava: u = g^r (r obrisan)
        address recipient;
        uint256 amount;
        bool claimed;
    }

    Puzzle[] public puzzles;

    event Locked(uint256 indexed id, uint256 amount);
    event Unlocked(uint256 indexed id, address recipient);

    constructor(int256 _D, uint256 _T) {
        D = _D;
        T = _T;
    }

    /// @notice zaključaj sredstva iza puzzle-a (ovo bi u aukciji bila ponuda)
    function lock(CG.Form calldata u, address recipient)
        external payable returns (uint256 id)
    {
        id = puzzles.length;
        puzzles.push(Puzzle(u, recipient, msg.value, false));
        emit Locked(id, msg.value);
    }

    /// @notice bilo ko podnosi rešenje; isplata ide unapred zadatom primaocu
    function claim(uint256 id, CG.Form calldata w, CG.Form calldata pi) external {
        Puzzle storage p = puzzles[id];
        require(!p.claimed, "already claimed");
        require(verify(p.u, w, pi), "invalid proof");
        p.claimed = true;
        emit Unlocked(id, p.recipient);
        (bool ok,) = p.recipient.call{value: p.amount}("");
        require(ok, "transfer failed");
    }

    // ------------------ Wesolowski verifikacija ------------------

    /// @notice proveri pi^l * u^(2^T mod l) == w za l = hashToPrime(u,w,T,D)
    /// @dev    Shamirov trik: oba stepenovanja u jednom prolazu kvadriranja
    function verify(CG.Form memory u, CG.Form memory w, CG.Form memory pi)
        public view returns (bool)
    {
        uint256 l = fiatShamirPrime(u, w);
        uint256 r = powmod2(T, l); // 2^T mod l
        CG.Form memory lhs = CG.shamir(pi, l, u, r, D);
        return CG.eq(lhs, CG.reduce(w));
    }

    /// @notice naivna verzija (dva odvojena stepenovanja) — samo za poređenje gasa
    function verifyNaive(CG.Form memory u, CG.Form memory w, CG.Form memory pi)
        public view returns (bool)
    {
        uint256 l = fiatShamirPrime(u, w);
        uint256 r = powmod2(T, l);
        CG.Form memory lhs = CG.compose(CG.pow(pi, l, D), CG.pow(u, r, D));
        return CG.eq(lhs, CG.reduce(w));
    }

    /// @dev 80-bitni prost izazov l iz sha256(u,w,T,D) — Fiat-Shamir.
    ///      Bajt-za-bajt isto kao u Python referenci (gen_vectors.py).
    function fiatShamirPrime(CG.Form memory u, CG.Form memory w)
        public view returns (uint256)
    {
        bytes32 seed = sha256(abi.encodePacked(u.a, u.b, u.c, w.a, w.b, w.c, T, D));
        for (uint256 counter = 0;; counter++) {
            uint256 cand = uint256(sha256(abi.encodePacked(seed, counter))) >> 176;
            cand |= (1 << 79) | 1;
            if (millerRabin(cand)) return cand;
        }
    }

    /// @dev deterministički Miller-Rabin za n < 3.3e24 (pokriva 80 bitova)
    function millerRabin(uint256 n) internal pure returns (bool) {
        uint256[12] memory bases =
            [uint256(2), 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37];
        for (uint256 i = 0; i < 12; i++) {
            if (n % bases[i] == 0) return n == bases[i];
        }
        uint256 d = n - 1;
        uint256 s = 0;
        while (d & 1 == 0) {
            d >>= 1;
            s++;
        }
        for (uint256 i = 0; i < 12; i++) {
            uint256 x = powmod(bases[i], d, n);
            if (x == 1 || x == n - 1) continue;
            bool passed = false;
            for (uint256 j = 0; j + 1 < s; j++) {
                x = mulmod(x, x, n);
                if (x == n - 1) {
                    passed = true;
                    break;
                }
            }
            if (!passed) return false;
        }
        return true;
    }

    function powmod(uint256 base, uint256 e, uint256 m)
        internal pure returns (uint256 r)
    {
        r = 1 % m;
        base %= m;
        while (e > 0) {
            if (e & 1 == 1) r = mulmod(r, base, m);
            base = mulmod(base, base, m);
            e >>= 1;
        }
    }

    /// @dev 2^T mod l bez računanja broja 2^T (koji ima T bitova)
    function powmod2(uint256 t, uint256 l) internal pure returns (uint256) {
        return powmod(2, t, l);
    }
}
