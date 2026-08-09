#!/usr/bin/env python3
"""
demo.py — timelock demo nad klasnim grupama.

Komande:
  python3 demo.py calibrate                    izmeri brzinu kvadriranja
  python3 demo.py setup --seconds 120          javni parametri (D, g, h=g^(2^T))
  python3 demo.py lock --message "..."         zaključaj poruku (trenutno)
  python3 demo.py unlock                       otključaj (traje T kvadriranja)
  python3 demo.py verify                       proveri Wesolowski dokaz (ms)
  python3 demo.py run --seconds 60 -m "..."    sve odjednom, za brzi test
"""

import argparse
import json
import sys
import time

import classgroup as cg
import timelock as tl

PARAMS = "params.json"
PUZZLE = "puzzle.json"
SOLUTION = "solution.json"

BITS = 512          # veličina diskriminante — DEMO parametar (vidi README)
SEED = b"petnica-demo-2026"   # u produkciji: block hash


def measure_rate(sample_seconds=3.0):
    D = cg.discriminant_from_seed(SEED, bits=BITS)
    g = cg.prime_form(D)
    x = g
    n = 0
    start = time.time()
    while time.time() - start < sample_seconds:
        for _ in range(50):
            x = cg.square(x)
        n += 50
    return n / (time.time() - start)


def cmd_calibrate(args):
    print(f"Merim brzinu kvadriranja u klasnoj grupi ({BITS}-bitna diskriminanta)...")
    rate = measure_rate()
    print(f"\n  ≈ {rate:,.0f} kvadriranja/sekundi na ovoj mašini\n")
    for label, s in [("1 minut", 60), ("10 minuta", 600), ("1 sat", 3600)]:
        print(f"  za odlaganje od {label:>9}:  T = {int(rate * s):,}")
    print("\nNapomena: T se u praksi bira prema NAJBRŽEM poznatom hardveru, ne ovoj mašini.")


def save(path, obj):
    with open(path, "w") as f:
        json.dump(obj, f, indent=2)


def load(path):
    with open(path) as f:
        return json.load(f)


def cmd_setup(args):
    print(f"[1/4] Izvodim diskriminantu D = -p iz javnog seed-a {SEED!r}")
    print("      (u produkciji: block hash → niko ne bira grupu, niko ne zna njen red)")
    D = cg.discriminant_from_seed(SEED, bits=BITS)
    print(f"      D ima {abs(D).bit_length()} bitova, p ≡ 3 (mod 4)\n")

    g = cg.prime_form(D)
    print(f"[2/4] Generator g = {g_short(g)}\n")

    rate = measure_rate(2.0)
    T = max(64, int(rate * args.seconds))
    print(f"[3/4] Kalibracija: ≈{rate:,.0f} kvadriranja/s → za ~{tl.fmt(args.seconds)} "
          f"odlaganja biram T = {T:,}")
    print(f"      Računam h = g^(2^T) — ovo traje, ali se radi SAMO JEDNOM:")
    t0 = time.time()
    h = tl.sequential_square(g, T, D, label="setup h=g^(2^T)")
    setup_time = time.time() - t0

    print(f"\n[4/4] Wesolowski dokaz da je h zaista g^(2^T) (da niko ne mora da nam veruje):")
    pi = tl.prove(g, h, T, D)
    assert tl.verify(g, h, T, pi, D)
    print(f"      Dokaz verifikovan ✓\n")

    save(PARAMS, {"D": D, "g": list(g), "h": list(h), "T": T,
                  "h_proof": list(pi), "setup_seconds": round(setup_time, 1)})
    print(f"Javni parametri upisani u {PARAMS}.")
    print(f"Svaki UNLOCK od sada garantovano traje ≈{tl.fmt(setup_time)} sekvencijalnog rada.")


def cmd_lock(args):
    p = load(PARAMS)
    D, g, h, T = p["D"], tuple(p["g"]), tuple(p["h"]), p["T"]
    msg = args.message.encode()

    t0 = time.time()
    r = tl.random_exponent()
    u = cg.power(g, r, D)          # u = g^r  (brzo: ~256-bitni eksponent)
    hr = cg.power(h, r, D)         # h^r      (brzo)
    ct = tl.encrypt(hr, msg)
    dt = (time.time() - t0) * 1000

    save(PUZZLE, {"u": list(u), "ciphertext": ct.hex(), "T": T})
    print(f"Poruka zaključana za {dt:.0f} ms → {PUZZLE}")
    print(f"  u = g^r = {g_short(u)}")
    print(f"  šifrat  = {ct.hex()[:64]}...")
    print(f"\nSlučajni eksponent r i ključ su OBRISANI iz memorije.")
    print(f"Jedini put do poruke: izračunati u^(2^T) — tačno {T:,} sekvencijalnih kvadriranja.")
    print(f"Ni mi više ne možemo brže. Paralelizacija ne pomaže: kvadriranje #k")
    print(f"zahteva rezultat kvadriranja #k−1.")


def cmd_unlock(args):
    p = load(PARAMS)
    z = load(PUZZLE)
    D, T = p["D"], z["T"]
    u = tuple(z["u"])
    ct = bytes.fromhex(z["ciphertext"])

    print(f"Otključavam: računam w = u^(2^T), T = {T:,} — nema prečice.\n")
    t0 = time.time()
    w = tl.sequential_square(u, T, D, label="otključavanje")
    unlock_time = time.time() - t0
    msg = tl.decrypt(w, ct)
    print(f"\n  ✓ Ključ otkriven posle {tl.fmt(unlock_time)}")
    print(f"  PORUKA: {msg.decode(errors='replace')!r}\n")

    print("Generišem Wesolowski dokaz (da ugovor/verifikator ne mora da ponovi T koraka):")
    pi = tl.prove(u, w, T, D)
    save(SOLUTION, {"w": list(w), "proof": list(pi),
                    "unlock_seconds": round(unlock_time, 1)})
    print(f"\nRešenje + dokaz upisani u {SOLUTION}. Sada pokreni: python3 demo.py verify")


def cmd_verify(args):
    p = load(PARAMS)
    z = load(PUZZLE)
    s = load(SOLUTION)
    D, T = p["D"], z["T"]
    u, w, pi = tuple(z["u"]), tuple(s["w"]), tuple(s["proof"])

    t0 = time.time()
    ok = tl.verify(u, w, T, pi, D)
    dt = (time.time() - t0) * 1000

    print(f"Wesolowski verifikacija: {'✓ VALIDNO' if ok else '✗ NEVALIDNO'}  ({dt:.1f} ms)")
    if ok and "unlock_seconds" in s:
        ratio = s["unlock_seconds"] * 1000 / dt if dt > 0 else 0
        print(f"\nAsimetrija koja je poenta cele priče:")
        print(f"  otključavanje : {tl.fmt(s['unlock_seconds'])} sekvencijalnog rada")
        print(f"  verifikacija  : {dt:.1f} ms   (≈{ratio:,.0f}× brže)")
        print(f"\nOvo je tačno ono što bi pametni ugovor radio on-chain:")
        print(f"  primi (w, π) → proveri π^l · u^r == w → pusti transakciju.")


def cmd_run(args):
    class A:
        pass
    a = A()
    a.seconds = args.seconds
    cmd_setup(a)
    print("\n" + "=" * 70 + "\n")
    a.message = args.message
    cmd_lock(a)
    print("\n" + "=" * 70 + "\n")
    cmd_unlock(a)
    print("\n" + "=" * 70 + "\n")
    cmd_verify(a)


def g_short(f):
    a, b, c = f
    sa, sb = str(a), str(b)
    cut = lambda s: s if len(s) <= 12 else s[:6] + "…" + s[-4:]
    return f"({cut(sa)}, {cut(sb)}, …)"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("calibrate")

    p = sub.add_parser("setup")
    p.add_argument("--seconds", type=int, default=60,
                   help="ciljano trajanje odlaganja (default 60)")

    p = sub.add_parser("lock")
    p.add_argument("--message", "-m", required=True)

    sub.add_parser("unlock")
    sub.add_parser("verify")

    p = sub.add_parser("run")
    p.add_argument("--seconds", type=int, default=30)
    p.add_argument("--message", "-m", default="posalji 1 ETH na 0xMarko...")

    args = ap.parse_args()
    {"calibrate": cmd_calibrate, "setup": cmd_setup, "lock": cmd_lock,
     "unlock": cmd_unlock, "verify": cmd_verify, "run": cmd_run}[args.cmd](args)


if __name__ == "__main__":
    main()
