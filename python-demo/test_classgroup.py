"""Testovi korektnosti aritmetike klasne grupe."""
import classgroup as cg


def test_cl_minus_23():
    # Poznato: Cl(-23) ima red 3. Forme: (1,1,6), (2,1,3), (2,-1,3).
    D = -23
    e = cg.identity(D)
    f = cg.reduce_form((2, 1, 3))
    f2 = cg.square(f)
    f3 = cg.compose(f2, f)
    assert f2 == cg.reduce_form((2, -1, 3)), f2
    assert f3 == e, f3
    assert cg.inverse(f) == f2
    print("OK  Cl(-23) ima red 3, inverz i identitet rade")


def test_group_laws_random_D():
    D = cg.discriminant_from_seed(b"test-seed", bits=128)
    e = cg.identity(D)
    g = cg.prime_form(D)
    # diskriminanta se cuva
    a, b, c = g
    assert b * b - 4 * a * c == D
    x = cg.power(g, 12345, D)
    y = cg.power(g, 67890, D)
    z = cg.power(g, 11111, D)
    # asocijativnost
    assert cg.compose(cg.compose(x, y), z) == cg.compose(x, cg.compose(y, z))
    # komutativnost
    assert cg.compose(x, y) == cg.compose(y, x)
    # identitet i inverz
    assert cg.compose(x, e) == x
    assert cg.compose(x, cg.inverse(x)) == e
    # (g^a)^b == g^(a*b)
    assert cg.power(cg.power(g, 111, D), 13, D) == cg.power(g, 111 * 13, D)
    # diskriminanta se cuva kroz kompoziciju
    a, b, c = cg.compose(x, y)
    assert b * b - 4 * a * c == D
    print("OK  grupovni zakoni važe nad slučajnom 128-bitnom diskriminantom")


def test_squaring_consistency():
    D = cg.discriminant_from_seed(b"drugi-seed", bits=96)
    g = cg.prime_form(D)
    h = g
    for _ in range(10):
        h = cg.square(h)
    assert h == cg.power(g, 2 ** 10, D)
    print("OK  10 uzastopnih kvadriranja == g^(2^10)")


if __name__ == "__main__":
    test_cl_minus_23()
    test_group_laws_random_D()
    test_squaring_consistency()
    print("\nSvi testovi prošli.")
