#!/usr/bin/env python3
"""
live_demo.py — PRAVI end-to-end demo na lokalnom lancu (anvil).

Ništa nije unapred izračunato: pri svakom pokretanju se pravi SVEŽ puzzle
(nov slučajan r), ugovor se deploy-uje iznova, lažno rešenje se uživo
odbija, pa se T kvadriranja odradi pred publikom i tek onda ETH legne.

Pokretanje (dva terminala):
    terminal 1:  anvil
    terminal 2:  python3 live_demo.py --seconds 600      # ~10 min kvadriranja

Zahteva: foundry (anvil, cast, forge) na PATH-u i classgroup.py
(iz Python dema) u istom folderu ili u ../timelock-demo.
"""
import argparse
import hashlib
import json
import secrets
import subprocess
import sys
import time
from math import gcd

# --- classgroup.py iz Python dema ---
sys.path[:0] = [".", "../timelock-demo", "/home/claude/timelock-demo"]
import classgroup as cg

RPC = "http://127.0.0.1:8545"
# standardni anvil nalozi (javni test ključevi koje anvil ispiše pri startu)
DEPLOYER_PK = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
RECIPIENT = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"  # "Marko"

D = -64770550419156998147359728223  # ista 96-bitna demo diskriminanta kao u testovima

MR_BASES = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37]


# ---------------- aritmetika identična ugovoru ----------------

def mr_prime(n):
    if n < 2:
        return False
    for p in MR_BASES:
        if n % p == 0:
            return n == p
    d, s = n - 1, 0
    while d % 2 == 0:
        d //= 2; s += 1
    for a in MR_BASES:
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


def compose_sol(f1, f2):
    a1, b1, c1 = f1; a2, b2, c2 = f2
    g = (b1 + b2) // 2
    h = (b2 - b1) // 2
    w = gcd(gcd(a1, a2), g)
    s, t, u = a1 // w, a2 // w, g // w
    k0, cap = cg.solve_mod(t * u, h * u + s * c1, s * t)
    n, _ = cg.solve_mod(t * cap, h - t * k0, s)
    k = (k0 + cap * n) % (s * t)
    l = (t * k - h) // s
    m = (t * u * k - h * u - s * c1) // (s * t)
    return cg.reduce_form((s * t, w * u - (k * t + l * s), k * l - w * m))


def power_sol(f, e):
    r = cg.identity(D); b = f
    while e > 0:
        if e & 1:
            r = compose_sol(r, b)
        b = compose_sol(b, b)
        e >>= 1
    return r


def i256(x):
    return (x % (1 << 256)).to_bytes(32, "big")


# ---------------- checkpoint dokaz (koristi međurezultate koraka 6) ----------------

CHECKPOINT_EVERY = 128  # k: svaki k-ti međurezultat u^(2^j) se pamti


def quotient_bits(T, l):
    """Svi bitovi q = ⌊2^T / l⌋ (samo celobrojna aritmetika — sekunde, ne sati)."""
    bits = bytearray(T)
    r = 1
    for i in range(1, T + 1):
        b, r = divmod(2 * r, l)
        bits[T - i] = b          # bit na poziciji T-i (od LSB)
    return bits


def _prove_slice(args):
    """Delimični proizvod za opseg blokova — nezavisno, pa ide i paralelno."""
    cps, bits, k, T, m_lo, m_hi = args
    acc = cg.identity(D)
    for t in range(k - 1, -1, -1):
        acc = compose_sol(acc, acc)
        for m in range(m_lo, m_hi):
            j = m * k + t
            if j < T and bits[j]:
                acc = compose_sol(acc, cps[m - m_lo])
    return acc


def prove_from_checkpoints(cps, bits, T, workers=1):
    """
    π = Π_t ( Π_{m: bit(mk+t)=1} C_m )^(2^t),  C_m = u^(2^(mk)) iz koraka 6.
    Trošak: k kvadriranja + ~T/2 množenja (≈3× manje od naivnog prolaza),
    a blokovi su nezavisni pa se dele na više procesa.
    """
    k = CHECKPOINT_EVERY
    M = len(cps)
    if workers <= 1:
        return _prove_slice((cps, bits, k, T, 0, M))
    import multiprocessing as mp
    bounds = [(i * M) // workers for i in range(workers + 1)]
    jobs = [(cps[lo:hi], bits, k, T, lo, hi)
            for lo, hi in zip(bounds, bounds[1:]) if hi > lo]
    with mp.Pool(len(jobs)) as pool:
        parts = pool.map(_prove_slice, jobs)
    acc = parts[0]
    for p in parts[1:]:
        acc = compose_sol(acc, p)
    return acc


def fiat_shamir_prime(u, w, T):
    seed = hashlib.sha256(b"".join(i256(v) for v in (*u, *w, T, D))).digest()
    counter = 0
    while True:
        cand = int.from_bytes(
            hashlib.sha256(seed + counter.to_bytes(32, "big")).digest()[:10], "big")
        cand |= (1 << 79) | 1
        if mr_prime(cand):
            return cand
        counter += 1


def hash_to_group(seed: bytes):
    """
    Nothing-up-my-sleeve element: heš → mali prost q (D kvadratni ostatak
    mod q) → forma (q, b, c) → redukcija. Diskretni log ovakvog u u odnosu
    na g ne zna NIKO — pa prečica u^(2^T) = h^r ne postoji ni za tvorca.
    """
    counter = 0
    while True:
        q = int.from_bytes(
            hashlib.sha256(seed + counter.to_bytes(8, "big")).digest()[:6], "big") | 1
        counter += 1
        if q < 3 or not mr_prime(q):
            continue
        if pow(D % q, (q - 1) // 2, q) != 1:   # D mora biti QR mod q
            continue
        b = cg.tonelli_shanks(D % q, q)
        if b is None:
            continue
        if b % 2 == 0:                          # b mora biti neparan (D ≡ 1 mod 4)
            b = q - b
        return cg.reduce_form((q, b, (b * b - D) // (4 * q)))


def progress(i, T, start, label):
    if i % max(1, T // 200) and i != T:
        return
    el = time.time() - start
    rate = i / el if el else 0
    eta = (T - i) / rate if rate else 0
    print(f"\r  [{label}] {100*i/T:5.1f}%  {i:,}/{T:,}  |  proteklo {int(el)}s"
          f"  |  preostalo ~{int(eta)}s   ", end="", flush=True)


# ---------------- pomoćnici za lanac (cast/forge) ----------------

def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def cast_send(sig_args, expect_fail=False):
    r = run(["cast", "send", "--rpc-url", RPC, "--private-key", DEPLOYER_PK, *sig_args])
    ok = r.returncode == 0
    if expect_fail:
        return not ok, r.stderr.strip().splitlines()[-1] if r.stderr else ""
    if not ok:
        sys.exit(f"cast send neuspešan:\n{r.stderr}")
    return True, r.stdout


def tx_field(stdout, field):
    for line in stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] == field:
            return parts[1]
    return "?"


def balance(addr):
    return int(run(["cast", "balance", addr, "--rpc-url", RPC]).stdout.strip())


def form_arg(f):
    return f"({f[0]},{f[1]},{f[2]})"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seconds", type=int, default=600,
                    help="ciljano trajanje faze kvadriranja (default 600 = 10 min)")
    ap.add_argument("--amount", default="1ether")
    ap.add_argument("--workers", type=int, default=1,
                    help="broj procesa za sastavljanje dokaza (default 1)")
    ap.add_argument("--phrase", default=None,
                    help="seed fraza (ako se ne zada, trazi unos interaktivno)")
    args = ap.parse_args()

    # 0) lanac dostupan?
    if run(["cast", "chain-id", "--rpc-url", RPC]).returncode != 0:
        sys.exit("Ne vidim anvil na 127.0.0.1:8545 — pokreni `anvil` u drugom terminalu.")

    print("=" * 66)
    print(" LIVE DEMO: transakcija na lancu se otključava tek posle T rada")
    print("=" * 66)

    # 1) kalibracija na licu mesta
    print("\n[1] Kalibracija ove mašine...")
    g = cg.prime_form(D)
    x, n0, t0 = g, 0, time.time()
    while time.time() - t0 < 2:
        for _ in range(200):
            x = compose_sol(x, x)
        n0 += 200
    rate = n0 / (time.time() - t0)
    T = max(64, int(rate * args.seconds))
    print(f"    ≈{rate:,.0f} kvadriranja/s  →  za ~{args.seconds}s biram T = {T:,}")

    # 2) deploy ugovora — svež, pred publikom
    print("\n[2] Deploy TimelockVault(D, T) na anvil...")
    r = run(["forge", "create", "src/TimelockVault.sol:TimelockVault",
             "--rpc-url", RPC, "--private-key", DEPLOYER_PK, "--broadcast",
             "--constructor-args", str(D), str(T)])
    if r.returncode != 0:
        sys.exit(f"forge create neuspešan:\n{r.stderr or r.stdout}")
    vault = next(l.split()[-1] for l in r.stdout.splitlines() if "Deployed to:" in l)
    print(f"    Vault: {vault}")

    # 3) svež puzzle — HASH-TO-GROUP: u se izvodi heširanjem javnih podataka,
    #    pa eksponent r (diskretni log u odnosu na g) NE POSTOJI ni za koga —
    #    ni tvorac dema nema prečicu.
    print("\n[3] Pravim svež puzzle (hash-to-group, bez ikakvog tajnog r):")
    blk = run(["cast", "block", "latest", "--rpc-url", RPC, "--field", "hash"]).stdout.strip()
    phrase = args.phrase if args.phrase is not None else input(
        "    Neka MENTOR ukuca bilo koju frazu (ulazi u seed): ")
    seed = hashlib.sha256(blk.encode() + phrase.encode()).digest()
    u = hash_to_group(seed)
    print(f"    seed = sha256(block hash lanca + fraza)")
    print(f"    u = {u}")
    print("    Eksponent r za ovo u NIKAD NIJE POSTOJAO — u je heš, ne g^r.")
    print("    Ni mi nemamo prečicu: jedini put do isplate je T kvadriranja.")

    # 4) zaključaj ETH za primaoca
    print(f"\n[4] Zaključavam {args.amount} za primaoca {RECIPIENT[:10]}…")
    bal0 = balance(RECIPIENT)
    cast_send([vault, "lock((int256,int256,int256),address)",
               form_arg(u), RECIPIENT, "--value", args.amount])
    print(f"    Zaključano. Stanje primaoca sada: {(balance(RECIPIENT)-bal0)/1e18} ETH (nula, naravno)")

    # 5) pokušaj varanja — uživo mora da pukne
    print("\n[5] Pokušavam da PREVARIM ugovor lažnim rešenjem (bez odrađenog posla):")
    fake_w = compose_sol(u, u)
    fake_pi = g
    failed, msg = cast_send([vault,
        "claim(uint256,(int256,int256,int256),(int256,int256,int256))",
        "0", form_arg(fake_w), form_arg(fake_pi)], expect_fail=True)
    print(f"    Ugovor ODBIO lažan claim ✓  ({'revert: invalid proof' if failed else 'GREŠKA: prošao?!'})")

    # 6) pošten rad: T sekvencijalnih kvadriranja + kontrolne tačke usput
    print(f"\n[6] Sada pošteno: {T:,} sekvencijalnih kvadriranja (~{args.seconds}s)...")
    print(f"    (usput pamtim svaki {CHECKPOINT_EVERY}. međurezultat — besplatno,")
    print(f"     to je samo memorija — da bi dokaz u koraku 7 bio višestruko brži)")
    w, start = u, time.time()
    cps = [u]                                  # C_0 = u^(2^0)
    for i in range(1, T + 1):
        w = compose_sol(w, w)
        if i % CHECKPOINT_EVERY == 0:
            cps.append(w)                      # C_m = u^(2^(m*k))
        progress(i, T, start, "kvadriranje")
    squaring_time = time.time() - start
    print(f"\n    w = u^(2^T) izračunat posle {int(squaring_time)}s"
          f"  ({len(cps):,} kontrolnih tačaka sačuvano)")

    # 7) Wesolowski dokaz IZ KONTROLNIH TAČAKA (umesto novog prolaza od ~T)
    print(f"\n[7] Wesolowski dokaz — sastavljanje iz kontrolnih tačaka"
          + (f" ({args.workers} procesa)..." if args.workers > 1 else "..."))
    start = time.time()
    l = fiat_shamir_prime(u, w, T)
    bits = quotient_bits(T, l)                 # bitovi q = ⌊2^T/l⌋, jeftino
    pi = prove_from_checkpoints(cps, bits, T, workers=args.workers)
    proof_time = time.time() - start
    print(f"    Dokaz gotov za {int(proof_time)}s"
          f"  (naspram ~{int(squaring_time*1.5)}s koliko bi trajao naivni prolaz —"
          f" {squaring_time*1.5/max(proof_time,0.001):.1f}× brže)")

    # 8) claim — ugovor verifikuje i isplaćuje
    print("\n[8] Podnosim (w, π) ugovoru...")
    t0 = time.time()
    _, out = cast_send([vault,
        "claim(uint256,(int256,int256,int256),(int256,int256,int256))",
        "0", form_arg(w), form_arg(pi)])
    gas_used = tx_field(out, "gasUsed")
    tx_hash = tx_field(out, "transactionHash")
    print(f"    Ugovor verifikovao i isplatio za {time.time()-t0:.1f}s")
    print(f"    tx: {tx_hash}")
    print(f"    gasUsed on-chain: {int(gas_used):,} (od 30,000,000 po bloku)"
          if gas_used.isdigit() else f"    gasUsed: {gas_used}")
    print(f"\n    STANJE PRIMAOCA: +{(balance(RECIPIENT)-bal0)/1e18} ETH  ✓")

    # 9) dupli claim ne prolazi
    failed, _ = cast_send([vault,
        "claim(uint256,(int256,int256,int256),(int256,int256,int256))",
        "0", form_arg(w), form_arg(pi)], expect_fail=True)
    print(f"    Ponovni claim odbijen ✓" if failed else "    GREŠKA: dupli claim prošao?!")

    print("\n" + "=" * 66)
    print(" KRAJ: sredstva su bila nedostupna dok neko nije odradio T koraka,")
    print(" lažno rešenje je odbijeno, a provera poštenog je trajala sekunde.")
    print("=" * 66)


if __name__ == "__main__":
    main()
