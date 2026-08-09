"""
classgroup.py — aritmetika klasne grupe imaginarnog kvadratnog polja.

Elementi grupe su redukovane binarne kvadratne forme (a, b, c) diskriminante
D = b^2 - 4ac < 0. Grupovna operacija je Gausova kompozicija formi.

Ključno svojstvo: red grupe |Cl(D)| niko ne zna za veliku slučajnu
diskriminantu — zato ne postoji prečica za g^(2^T) i timelock drži.

Sve je pisano čitljivo, bez ijedne spoljne biblioteke.
"""

import hashlib
from math import gcd


# ---------------------------------------------------------------------------
# Pomoćne teorijsko-brojevne funkcije
# ---------------------------------------------------------------------------

def ext_gcd(a, b):
    """Prošireni Euklid: vraća (g, x, y) tako da a*x + b*y = g = gcd(a, b)."""
    old_r, r = a, b
    old_x, x = 1, 0
    old_y, y = 0, 1
    while r != 0:
        q = old_r // r
        old_r, r = r, old_r - q * r
        old_x, x = x, old_x - q * x
        old_y, y = y, old_y - q * y
    if old_r < 0:
        old_r, old_x, old_y = -old_r, -old_x, -old_y
    return old_r, old_x, old_y


def solve_mod(a, b, m):
    """Reši a*x ≡ b (mod m). Vraća (x0, m/g): sva rešenja su x0 + k*(m/g)."""
    g, x0, _ = ext_gcd(a, m)
    if b % g != 0:
        raise ValueError("kongruencija nema rešenje")
    x = (x0 * (b // g)) % (m // g)
    return x, m // g


def is_probable_prime(n, rounds=40):
    """Miller–Rabin test prostosti."""
    if n < 2:
        return False
    for p in (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37):
        if n % p == 0:
            return n == p
    d, s = n - 1, 0
    while d % 2 == 0:
        d //= 2
        s += 1
    for i in range(rounds):
        a = 2 + int.from_bytes(
            hashlib.sha256(n.to_bytes((n.bit_length() + 7) // 8, "big")
                           + i.to_bytes(4, "big")).digest(), "big"
        ) % (n - 3)
        x = pow(a, d, n)
        if x in (1, n - 1):
            continue
        for _ in range(s - 1):
            x = pow(x, 2, n)
            if x == n - 1:
                break
        else:
            return False
    return True


def tonelli_shanks(n, p):
    """Kvadratni koren mod prost broj p: vraća x sa x^2 ≡ n (mod p), ili None."""
    n %= p
    if n == 0:
        return 0
    if pow(n, (p - 1) // 2, p) != 1:
        return None
    if p % 4 == 3:
        return pow(n, (p + 1) // 4, p)
    # opšti slučaj
    q, s = p - 1, 0
    while q % 2 == 0:
        q //= 2
        s += 1
    z = 2
    while pow(z, (p - 1) // 2, p) != p - 1:
        z += 1
    m, c, t, r = s, pow(z, q, p), pow(n, q, p), pow(n, (q + 1) // 2, p)
    while t != 1:
        t2, i = t, 0
        while t2 != 1:
            t2 = pow(t2, 2, p)
            i += 1
        b = pow(c, 1 << (m - i - 1), p)
        m, c = i, pow(b, 2, p)
        t, r = (t * c) % p, (r * b) % p
    return r


def kronecker(a, n):
    """Kroneckerov simbol (a/n) — dovoljan nam je slučaj n prost neparan."""
    return pow(a % n, (n - 1) // 2, n)  # 1 ako je QR, n-1 ako nije


# ---------------------------------------------------------------------------
# Diskriminanta iz javnog seed-a (bez trusted setupa)
# ---------------------------------------------------------------------------

def discriminant_from_seed(seed: bytes, bits: int = 512) -> int:
    """
    D = -p, gde je p prost, p ≡ 3 (mod 4), determinisano izveden iz seed-a
    (u praksi: block hash). Niko ne bira D — i zato niko ne zna red grupe.
    """
    counter = 0
    while True:
        raw = b""
        c2 = 0
        while len(raw) * 8 < bits:
            raw += hashlib.sha256(seed + counter.to_bytes(8, "big")
                                  + c2.to_bytes(8, "big")).digest()
            c2 += 1
        p = int.from_bytes(raw, "big")
        p |= (1 << (bits - 1))          # pun broj bitova
        p |= 3                           # p ≡ 3 (mod 4), neparan
        p -= (p % 4) - 3 if p % 4 != 3 else 0
        if p % 4 == 3 and is_probable_prime(p):
            return -p
        counter += 1


# ---------------------------------------------------------------------------
# Forme: redukcija, kompozicija, stepenovanje
# ---------------------------------------------------------------------------

def normalize(a, b, c):
    if -a < b <= a:
        return a, b, c
    r = (a - b) // (2 * a)
    b2 = b + 2 * r * a
    c2 = a * r * r + b * r + c
    return a, b2, c2


def reduce_form(f):
    """Svaka klasa ima tačno jednog redukovanog predstavnika — kanonski oblik."""
    a, b, c = normalize(*f)
    while a > c or (a == c and b < 0):
        s = (c + b) // (2 * c)
        a, b, c = c, -b + 2 * s * c, c * s * s - b * s + a
    return normalize(a, b, c)


def identity(D):
    """Neutral: glavna forma (1, 1, (1-D)/4) za D ≡ 1 (mod 4)."""
    return (1, 1, (1 - D) // 4)


def inverse(f):
    a, b, c = f
    return reduce_form((a, -b, c))


def compose(f1, f2):
    """Gausova kompozicija dve forme iste diskriminante (Cohen 5.4.7)."""
    a1, b1, c1 = f1
    a2, b2, c2 = f2
    g = (b1 + b2) // 2
    h = (b2 - b1) // 2
    w = gcd(gcd(a1, a2), g)
    s = a1 // w
    t = a2 // w
    u = g // w
    k0, cap = solve_mod(t * u, h * u + s * c1, s * t)
    n, _ = solve_mod(t * cap, h - t * k0, s)
    k = k0 + cap * n
    l = (t * k - h) // s
    m = (t * u * k - h * u - s * c1) // (s * t)
    a3 = s * t
    b3 = w * u - (k * t + l * s)
    c3 = k * l - w * m
    return reduce_form((a3, b3, c3))


def square(f):
    return compose(f, f)


def power(f, e, D):
    """f^e kvadriranjem i množenjem."""
    result = identity(D)
    base = f
    while e > 0:
        if e & 1:
            result = compose(result, base)
        base = square(base)
        e >>= 1
    return result


def prime_form(D, seed: bytes = b"generator"):
    """
    Determinisano nađi generator: formu (q, b, c) gde je q mali prost broj
    za koji je D kvadratni ostatak. Hash-to-group u malom.
    """
    q = 2
    while True:
        q = next_prime(q)
        if q > 2 and kronecker(D, q) == 1:
            b = tonelli_shanks(D % q, q)
            if b is None:
                continue
            if b % 2 == 0:
                b = q - b  # D ≡ 1 (mod 4) ⇒ b mora biti neparan
            c = (b * b - D) // (4 * q)
            return reduce_form((q, b, c))


def next_prime(n):
    n += 1
    while not is_probable_prime(n):
        n += 1
    return n


def serialize(f) -> bytes:
    """Kanonska serijalizacija redukovane forme — za heširanje i ključeve."""
    a, b, c = reduce_form(f)
    return repr((a, b, c)).encode()

# ---------------------------------------------------------------------------
# NUCOMP (van der Poorten alg. 3) — Python ogledalo Solidity implementacije,
# za generisanje vektora i masovnu validaciju protiv klasicnog compose().
# ---------------------------------------------------------------------------

def _xgcd_partial(a, mu, stop_bits):
    """Parcijalni Euklid na (a, mu): vraca (rP, rC, bP, bC, even_steps)."""
    rP, rC, bP, bC = a, mu, 0, 1
    steps = 0
    while rC != 0 and rC.bit_length() > stop_bits:
        q = rP // rC
        rP, rC, bP, bC = rC, rP - q * rC, bC, bP - q * bC
        steps += 1
    return rP, rC, bP, bC, steps % 2 == 0

def nucomp(f1, f2, D):
    """Kompozicija sa parcijalnom redukcijom; identicna klasa kao compose."""
    if f1 == f2:
        return square(f1)
    u1, v1, w1 = f1
    u2, v2, w2 = f2
    s = (v1 + v2) // 2
    m = v2 - s
    # F = gcd(u1,u2) i b: u2*b == F (mod u1)
    import math
    def xgcd(x, y):
        if y == 0:
            return (x, 1, 0) if x >= 0 else (-x, -1, 0)
        g, p, q = xgcd(y, x % y)
        return g, q, p - (x // y) * q
    F, b, _ = xgcd(u2, u1)
    if F < 0:
        F, b = -F, -b
    if s % F == 0:
        G = F
        By = u1 // F
        Bx = (m * b) % By
        Cy = u2 // F
        Dy = s // F
    else:
        c = (F - b * u2) // u1
        G, yF, _ = xgcd(s, F)
        if G < 0:
            G, yF = -G, -yF
        H = F // G
        By = u1 // G
        Cy = u2 // G
        Dy = s // G
        l = (yF * (b * (w1 % H) + c * (w2 % H))) % H
        Bx = (b * (m // H) + l * (u1 // F)) % By
    stop = abs(D).bit_length() >> 2
    by, bx, y, x, even = _xgcd_partial(By, Bx % By, stop)
    no_steps = (y == 0 and x == 1)
    if not even:
        by, y = -by, -y
    ax, ay = G * x, G * y
    if no_steps:
        cx = (bx * Cy - m) // By
        cy = (by * u2) // u1 if bx == 0 else (by * cx + m) // bx
        dx = (bx * Dy - w2) // By
        u3 = by * cy
        w3 = bx * cx - G * dx
        v3 = G * Dy - (bx * cy + by * cx)
    else:
        cx = (bx * Cy - m * x) // By
        cy = (u2 * by - y * m) // u1 if bx == 0 else (by * cx + m) // bx
        dx = (bx * Dy - w2 * x) // By
        dy = (dx * y + Dy) // x
        u3 = by * cy - ay * dy
        w3 = bx * cx - ax * dx
        v3 = (ax * dy + ay * dx) - (bx * cy + by * cx)
    return reduce_form((u3, v3, w3))
