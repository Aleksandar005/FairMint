"""
gen_vectors.py — pravi test-vektore za Solidity verifikator.

Koristi MANJU diskriminantu (~96 bitova) tako da sva aritmetika staje u
int256 bez bignum biblioteke. Heš-izvođenje (sha256 + Miller-Rabin) je
bajt-za-bajt isto kao u ugovoru, da se l poklopi.
"""
import hashlib, secrets, sys, json
sys.path.insert(0, "/home/claude/timelock-demo")
import classgroup as cg

MR_BASES = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37]  # deterministicki < 3.3e24


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


def i256(x):
    return (x % (1 << 256)).to_bytes(32, "big")


def fs_seed(u, w, T, D):
    """sha256(abi.encodePacked(u.a,u.b,u.c,w.a,w.b,w.c,T,D)) — kao u ugovoru."""
    data = b"".join(i256(v) for v in (*u, *w, T, D))
    return hashlib.sha256(data).digest()


def hash_to_prime(seed):
    """80-bitni prost l: sha256(seed || counter), prvih 10 bajtova, MR test."""
    counter = 0
    while True:
        cand = int.from_bytes(
            hashlib.sha256(seed + counter.to_bytes(32, "big")).digest()[:10], "big")
        cand |= (1 << 79) | 1
        if mr_prime(cand):
            return cand, counter
        counter += 1


def small_discriminant(seed: bytes, bits: int) -> int:
    """Kao cg.discriminant_from_seed, ali stvarno skraćeno na `bits` bitova."""
    counter = 0
    while True:
        raw = hashlib.sha256(seed + counter.to_bytes(8, "big")).digest()
        p = int.from_bytes(raw, "big") >> (256 - bits)
        p |= (1 << (bits - 1)) | 3
        if p % 4 != 3:
            p += 2
        if p % 4 == 3 and mr_prime(p):
            return -p
        counter += 1


def compose_sol(f1, f2, D):
    """Kompozicija IDENTIČNA Solidity verziji: k se redukuje mod s*t
    da međuproizvodi stanu u int256."""
    a1, b1, c1 = f1; a2, b2, c2 = f2
    g = (b1 + b2) // 2
    h = (b2 - b1) // 2
    from math import gcd
    w = gcd(gcd(a1, a2), g)
    s, t, u = a1 // w, a2 // w, g // w
    k0, cap = cg.solve_mod(t * u, h * u + s * c1, s * t)
    n, _ = cg.solve_mod(t * cap, h - t * k0, s)
    k = (k0 + cap * n) % (s * t)          # <<< redukcija, jedina razlika
    l = (t * k - h) // s
    m = (t * u * k - h * u - s * c1) // (s * t)
    return cg.reduce_form((s * t, w * u - (k * t + l * s), k * l - w * m))


def power_sol(f, e, D):
    r = cg.identity(D); b = f
    while e > 0:
        if e & 1: r = compose_sol(r, b, D)
        b = compose_sol(b, b, D)
        e >>= 1
    return r


def prove_sol(u, w, T, D):
    seed = fs_seed(u, w, T, D)
    l, ctr = hash_to_prime(seed)
    pi, r = cg.identity(D), 1
    for _ in range(T):
        bbit, r = divmod(2 * r, l)
        pi = compose_sol(pi, pi, D)
        if bbit:
            pi = compose_sol(pi, u, D)
    return pi, l, ctr


def verify_sol(u, w, T, pi, D):
    seed = fs_seed(u, w, T, D)
    l, _ = hash_to_prime(seed)
    r = pow(2, T, l)
    lhs = compose_sol(power_sol(pi, l, D), power_sol(u, r, D), D)
    return lhs == cg.reduce_form(w)


# ---- 1) sanity: compose_sol daje istu klasu kao originalni compose ----
Dt = small_discriminant(b"cross-check", 96)
gt = cg.prime_form(Dt)
for i in range(30):
    x = cg.power(gt, 1000 + 37 * i, Dt)
    y = cg.power(gt, 777 + 91 * i, Dt)
    assert compose_sol(x, y, Dt) == cg.compose(x, y), i
print("OK compose_sol == compose (30 slučajnih parova)")

# ---- 2) generiši vektore ----
D = small_discriminant(b"solidity-demo-2026", 96)
g = cg.prime_form(D)
T = 4096
h = g
for _ in range(T):
    h = compose_sol(h, h, D)
assert h == cg.power(g, 1 << T, D)

r_secret = secrets.randbits(128)
u = power_sol(g, r_secret, D)
key_lock = power_sol(h, r_secret, D)       # h^r — ključ pri zaključavanju
w = u
for _ in range(T):
    w = compose_sol(w, w, D)               # u^(2^T) — ključ pri otključavanju
assert w == key_lock, "zakon stepena mora da važi"

pi, l, ctr = prove_sol(u, w, T, D)
assert verify_sol(u, w, T, pi, D)
assert not verify_sol(u, compose_sol(w, w, D), T, pi, D)
print("OK vektori: dokaz validan, lažni w odbijen")
print(f"D = {D}\nT = {T}\nl = {l} (counter={ctr})")

vec = {"D": D, "T": T,
       "g": list(g), "h": list(h), "u": list(u), "w": list(w), "pi": list(pi),
       "w_bad": list(compose_sol(w, w, D))}
with open("vectors.json", "w") as f:
    json.dump(vec, f, indent=1)

# ---- 3) ispiši kao Solidity konstante za test ----
def sol_form(name, f):
    return (f"    function {name}() internal pure returns (LibClassGroup.Form memory) {{\n"
            f"        return LibClassGroup.Form(int256({f[0]}), int256({f[1]}), int256({f[2]}));\n"
            f"    }}")

with open("Vectors.sol.txt", "w") as f:
    f.write(f"int256 constant D = {D};\nuint256 constant T = {T};\n")
    for name, form in [("G", g), ("H", h), ("U", u), ("W", w), ("PI", pi), ("W_BAD", vec["w_bad"])]:
        f.write(sol_form(name, form) + "\n")
print("vectors.json i Vectors.sol.txt upisani")
