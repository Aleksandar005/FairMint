#!/usr/bin/env python3
"""Masovna validacija nucomp() protiv compose() — reproducibilna zamena za
tvrdnju 'validirano na 1600+ slucajeva'. Pokriva: genericke parove (F=1),
translate parove (F = a1, retka grana F nedeljivo sa s), inverzne parove
(F = a1, s = 0), na 1024-bit diskriminanti."""
import random, sys
from classgroup import discriminant_from_seed, prime_form, reduce_form, compose, square, power, nucomp, inverse

random.seed(42)
D = discriminant_from_seed(b"petnica-2026", bits=1024)
g = prime_form(D)

def rand_form():
    return power(g, random.getrandbits(120) | 1, D)

fails = 0
N_GEN, N_TR, N_INV = 1500, 300, 200
for i in range(N_GEN):
    f1, f2 = rand_form(), rand_form()
    if f1 == f2: continue
    if nucomp(f1, f2, D) != reduce_form(compose(f1, f2)): fails += 1; print("GEN fail", i)
for i in range(N_TR):
    f1 = rand_form(); a, b, c = f1; t = random.randint(1, 5)
    f2 = (a, b + 2*a*t, c + b*t + a*t*t)   # ista klasa, gcd(a1,a2)=a1, F nedeljivo sa s
    want = reduce_form(compose(f1, f2))
    if nucomp(f1, f2, D) != want or want != reduce_form(square(f1)): fails += 1; print("TR fail", i)
for i in range(N_INV):
    f1 = rand_form(); f2 = inverse(f1)     # F = a1, s = 0
    if nucomp(f1, f2, D) != reduce_form(compose(f1, f2)): fails += 1; print("INV fail", i)

total = N_GEN + N_TR + N_INV
print(f"nucomp vs compose: {total} slucajeva, {fails} gresaka")
sys.exit(1 if fails else 0)
