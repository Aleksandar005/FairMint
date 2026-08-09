"""
timelock.py — timelock puzzle nad klasnom grupom + Wesolowski dokaz.

Šema (isti princip kao Cicada, ali nad klasnom grupom — bez trusted setupa):

  SETUP (jednom, javno, verifikabilno):
      D  = -p iz javnog seed-a (npr. block hash)
      g  = determinisani generator
      h  = g^(2^T)   ← ovo traje T sekvencijalnih kvadriranja,
                        ali se radi JEDNOM i dokazuje Wesolowski dokazom
  LOCK (trenutno, koliko god puta hoćeš):
      r  = slučajan 256-bitni broj
      u  = g^r
      ključ = H(h^r), poruka se šifruje ključem
      objavi (u, šifrat) — r i ključ se BRIŠU
  UNLOCK (svako može, ali mora da odradi T kvadriranja):
      w  = u^(2^T) = h^r   ← T sekvencijalnih kvadriranja, nema prečice
      ključ = H(w) → dešifruj
      + Wesolowski dokaz da je w zaista u^(2^T), za jeftinu on-chain proveru
  VERIFY (milisekunde):
      l = H_prime(u, w, T);  r = 2^T mod l;  proveri  π^l · u^r == w
"""

import hashlib
import secrets
import time

import classgroup as cg


# ---------------------------------------------------------------------------
# Sekvencijalno kvadriranje sa progress barom
# ---------------------------------------------------------------------------

def sequential_square(f, T, D, label="kvadriranje", quiet=False):
    """Izračunaj f^(2^T) sa T uzastopnih kvadriranja. Ovo je 'sat'."""
    start = time.time()
    report_every = max(1, T // 200)
    x = f
    for i in range(1, T + 1):
        x = cg.square(x)
        if not quiet and (i % report_every == 0 or i == T):
            elapsed = time.time() - start
            rate = i / elapsed if elapsed > 0 else 0
            eta = (T - i) / rate if rate > 0 else 0
            pct = 100 * i / T
            print(f"\r  [{label}] {pct:5.1f}%  {i:,}/{T:,} kvadriranja"
                  f"  |  proteklo {fmt(elapsed)}  |  preostalo ~{fmt(eta)}   ",
                  end="", flush=True)
    if not quiet:
        print()
    return x


def fmt(seconds):
    seconds = int(seconds)
    if seconds < 60:
        return f"{seconds}s"
    if seconds < 3600:
        return f"{seconds // 60}m {seconds % 60:02d}s"
    return f"{seconds // 3600}h {(seconds % 3600) // 60:02d}m"


# ---------------------------------------------------------------------------
# Wesolowski proof of exponentiation
# ---------------------------------------------------------------------------

def _fiat_shamir_prime(u, w, T, D):
    """Izvedeni 'izazovni' prost broj l ≈ 2^256 iz (u, w, T) — Fiat–Shamir."""
    h = hashlib.sha256(cg.serialize(u) + b"|" + cg.serialize(w)
                       + b"|" + str(T).encode() + b"|" + str(D).encode())
    l = int.from_bytes(h.digest(), "big") | (1 << 255) | 1
    return cg.next_prime(l)


def prove(u, w, T, D, quiet=False):
    """
    Wesolowski dokaz: π = u^⌊2^T / l⌋, izračunat on-line algoritmom
    u T koraka (bez čuvanja gigantskog broja 2^T).
    """
    l = _fiat_shamir_prime(u, w, T, D)
    pi = cg.identity(D)
    r = 1
    start = time.time()
    report_every = max(1, T // 200)
    for i in range(1, T + 1):
        b, r = divmod(2 * r, l)
        pi = cg.square(pi)
        if b:
            pi = cg.compose(pi, u)
        if not quiet and (i % report_every == 0 or i == T):
            elapsed = time.time() - start
            rate = i / elapsed if elapsed > 0 else 0
            eta = (T - i) / rate if rate > 0 else 0
            print(f"\r  [Wesolowski dokaz] {100*i/T:5.1f}%  "
                  f"|  preostalo ~{fmt(eta)}   ", end="", flush=True)
    if not quiet:
        print()
    return pi


def verify(u, w, T, pi, D):
    """
    Provera: π^l · u^(2^T mod l) == w.
    Košta ~2×256 grupovnih operacija umesto T — ovo bi radio pametni ugovor.
    """
    l = _fiat_shamir_prime(u, w, T, D)
    r = pow(2, T, l)
    lhs = cg.compose(cg.power(pi, l, D), cg.power(u, r, D))
    return lhs == cg.reduce_form(w)


# ---------------------------------------------------------------------------
# Šifrovanje poruke ključem izvedenim iz grupnog elementa
# ---------------------------------------------------------------------------

def _keystream(key: bytes, n: int) -> bytes:
    out = b""
    counter = 0
    while len(out) < n:
        out += hashlib.sha256(key + counter.to_bytes(8, "big")).digest()
        counter += 1
    return out[:n]


def encrypt(group_element, plaintext: bytes) -> bytes:
    key = hashlib.sha256(b"timelock-key|" + cg.serialize(group_element)).digest()
    return bytes(a ^ b for a, b in zip(plaintext, _keystream(key, len(plaintext))))


decrypt = encrypt  # XOR je simetričan


def random_exponent(bits=256) -> int:
    return secrets.randbits(bits) | (1 << (bits - 1))
