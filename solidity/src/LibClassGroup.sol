// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title LibClassGroup — aritmetika klasne grupe za DEMO diskriminante (~96 bitova)
/// @notice Elementi su redukovane binarne kvadratne forme (a,b,c), b^2-4ac = D < 0.
///         Sve staje u int256 jer je |D| ~ 2^96 (međuproizvodi < 2^200).
///         Za produkcijske diskriminante (hiljade bitova) potrebna je bignum
///         biblioteka u stilu Cicadinog LibUint1024 — to je "pravi" projekat.
library LibClassGroup {
    struct Form {
        int256 a;
        int256 b;
        int256 c;
    }

    // ---------- celobrojne operacije sa Python (floor) semantikom ----------

    /// @dev Solidity deli ka nuli; nama treba floor kao u Pythonu.
    ///      `unchecked` je bezbedan: granice međuvrednosti (<2^200 za 96-bitnu
    ///      diskriminantu) su dimenzionisane da overflow ne može da nastane.
    function fdiv(int256 x, int256 y) internal pure returns (int256 q) {
        unchecked {
            q = x / y;
            if ((x % y != 0) && ((x < 0) != (y < 0))) q -= 1;
        }
    }

    function fmod(int256 x, int256 y) internal pure returns (int256) {
        unchecked {
            return x - fdiv(x, y) * y; // znak prati y; za y>0 rezultat u [0,y)
        }
    }

    function abs_(int256 x) internal pure returns (int256) {
        return x < 0 ? -x : x;
    }

    /// @dev prošireni Euklid: g = gcd(a,b) = ax + by, g >= 0
    function xgcd(int256 a, int256 b)
        internal pure returns (int256 g, int256 x, int256 y)
    {
        unchecked {
            (int256 r0, int256 r1) = (a, b);
            (int256 x0, int256 x1) = (int256(1), int256(0));
            (int256 y0, int256 y1) = (int256(0), int256(1));
            while (r1 != 0) {
                int256 q = r0 / r1; // truncated je ok — svejedno konvergira
                (r0, r1) = (r1, r0 - q * r1);
                (x0, x1) = (x1, x0 - q * x1);
                (y0, y1) = (y1, y0 - q * y1);
            }
            if (r0 < 0) (r0, x0, y0) = (-r0, -x0, -y0);
            return (r0, x0, y0);
        }
    }

    function gcd3(int256 a, int256 b, int256 c) internal pure returns (int256) {
        (int256 g1,,) = xgcd(a, b);
        (int256 g2,,) = xgcd(g1, c);
        return g2;
    }

    /// @dev reši a*x ≡ b (mod m); vraća (x0, m/g)
    function solveMod(int256 a, int256 b, int256 m)
        internal pure returns (int256 x, int256 cap)
    {
        (int256 g, int256 x0,) = xgcd(a, m);
        require(b % g == 0, "no solution");
        cap = m / g;
        x = fmod(x0 * (b / g), cap);
    }

    // ---------------------- forme: redukcija ----------------------

    function normalize(Form memory f) internal pure returns (Form memory) {
        unchecked {
            if (-f.a < f.b && f.b <= f.a) return f;
            int256 r = fdiv(f.a - f.b, 2 * f.a);
            int256 b2 = f.b + 2 * r * f.a;
            int256 c2 = f.a * r * r + f.b * r + f.c;
            return Form(f.a, b2, c2);
        }
    }

    /// @notice kanonski (jedinstveni) predstavnik klase
    function reduce(Form memory f) internal pure returns (Form memory) {
        unchecked {
            f = normalize(f);
            while (f.a > f.c || (f.a == f.c && f.b < 0)) {
                int256 s = fdiv(f.c + f.b, 2 * f.c);
                (f.a, f.b, f.c) = (f.c, -f.b + 2 * s * f.c, f.c * s * s - f.b * s + f.a);
            }
            return normalize(f);
        }
    }

    function identity(int256 D) internal pure returns (Form memory) {
        return Form(1, 1, (1 - D) / 4);
    }

    function eq(Form memory x, Form memory y) internal pure returns (bool) {
        return x.a == y.a && x.b == y.b && x.c == y.c;
    }

    // ------------------- Gausova kompozicija -------------------

    /// @notice grupovna operacija; k se redukuje mod s*t da sve stane u int256
    function compose(Form memory f1, Form memory f2)
        internal pure returns (Form memory)
    {
        unchecked {
            int256 g = (f1.b + f2.b) / 2; // b-ovi su iste parnosti (D neparan)
            int256 h = (f2.b - f1.b) / 2;
            int256 w = gcd3(f1.a, f2.a, g);
            int256 s = f1.a / w;
            int256 t = f2.a / w;
            int256 u = g / w;
            (int256 k0, int256 cap) = solveMod(t * u, h * u + s * f1.c, s * t);
            (int256 n,) = solveMod(t * cap, h - t * k0, s);
            int256 k = fmod(k0 + cap * n, s * t);
            int256 l = (t * k - h) / s;
            int256 m = (t * u * k - h * u - s * f1.c) / (s * t);
            return reduce(Form(s * t, w * u - (k * t + l * s), k * l - w * m));
        }
    }

    function square(Form memory f) internal pure returns (Form memory) {
        return compose(f, f);
    }


    /// @notice Shamirov trik: x^e1 * y^e2 u JEDNOM prolazu kvadriranja,
    ///         umesto dva odvojena stepenovanja — glavna gas optimizacija
    ///         verifikacije (~2x manje grupovnih operacija).
    function shamir(
        Form memory x,
        uint256 e1,
        Form memory y,
        uint256 e2,
        int256 D
    ) internal pure returns (Form memory r) {
        Form memory xy = compose(x, y); // pretracunato za slucaj bita (1,1)
        r = identity(D);
        uint256 m = e1 > e2 ? e1 : e2;
        uint256 bit = 1;
        while (bit <= m >> 1) bit <<= 1; // najvisi bit
        while (bit != 0) {
            r = compose(r, r);
            bool b1 = e1 & bit != 0;
            bool b2 = e2 & bit != 0;
            if (b1 && b2) r = compose(r, xy);
            else if (b1) r = compose(r, x);
            else if (b2) r = compose(r, y);
            bit >>= 1;
        }
    }
    /// @notice f^e kvadriranjem i množenjem — trošak ~2*log2(e) kompozicija
    function pow(Form memory f, uint256 e, int256 D)
        internal pure returns (Form memory r)
    {
        r = identity(D);
        Form memory b = f;
        while (e > 0) {
            if (e & 1 == 1) r = compose(r, b);
            b = compose(b, b);
            e >>= 1;
        }
    }
}
