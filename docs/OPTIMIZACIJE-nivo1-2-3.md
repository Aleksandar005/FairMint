# Optimizacije klasnih grupa — izveštaj sesije

Svih 35 testova prolazi, uključujući Python diferencijalne vektore, e2e aukciju
i dva nova fuzz testa (512 slučajnih parova).

## Šta je urađeno (od najlakšeg ka težem)

**LibBigInt.sol**
1. `xgcd`: koristi ostatak koji `divmod` već izračuna (ranije: pun `mul` + `sub`
   po svakoj Euklidovoj iteraciji da se ostatak rekomputuje).
2. `xgcdHalf`: polu-prošireni gcd — vraća `(g, x)`, bez t-niza koji se bacao.
3. `gcd`: **binarni (Stein)** — nula deoba; svaki `divmod` košta ~12k gasa čak i
   na 2-limbnim brojevima, a binarni korak (shift/sub) ~0,5k.
4. `shl1` / `shr1`: množenje/deljenje sa 2 kao 1-bitni šift (floor za negativne).
5. `sub`: bez `negate`-klona celog niza limbova.
6. `_trim`: skraćivanje dužine niza in-place (assembly), bez realokacije.
7. `isOne` pomoćnik za brze staze.

**LibClassGroupBig.sol**
8. `compose`: `w == 1` brza staza (preskače 3 velike deobe), halvings kao šiftovi.
9. `_solveMod`: `xgcdHalf` umesto punog `xgcd` + `g == 1` brza staza.
10. `square`: **namensko kvadriranje (NUDUPL-lite)** — za `w = gcd(b,a) = 1`:
    `μ = b⁻¹c mod a; A = a²; B = b − 2aμ; C = μ² − (bμ−c)/a`.
    JEDAN `xgcdHalf` (koji vraća i `w` i inverz — spojeno) umesto gcd-a + dva
    puna `_solveMod`-a nad modulima duplo veće širine. Algebarski identično
    `compose(f,f)`; potvrđeno Python vektorima.
11. `pow`: MSB-first — bez kompozicija sa identitetom i bez bačenog finalnog
    kvadriranja.
12. **Kompaktovanje memorije** (`squareCompact` / `composeCompact`): snapshot
    free-memory pointera, operacija, kompaktna kopija rezultata, premotavanje.
    Bez ovoga lanac NE MOŽE da se izvrši: EVM naplaćuje 3w + w²/512, a jedna
    operacija ostavlja ~400KB smeća.

**foundry.toml**: `evm_version = "cancun"`.

## Izmereni brojevi

| metrika | pre | posle |
|---|---|---|
| kompozicija (test fixture, mali koef.) | 463.256 | 330.066 (−29%) |
| `pow g^(2^4)` | 4.681.167 | ~1.050.000 (−78%) |
| `test_Xgcd` | 132.364 | 78.850 (−40%) |
| lanac 10 kvadriranja bez kompaktovanja | 37M | — |
| lanac 20 kvadriranja bez kompaktovanja | 407M | — |
| lanac 30 kvadriranja bez kompaktovanja | MemoryOOG (>1B) | — |
| lanac 30 kvadriranja SA kompaktovanjem | — | FMP ravan (~36KB) |

## KLJUČNO OTKRIĆE — stare procene ne važe

Cifra „463k po kompoziciji" iz `docs/1024-bit-nalazi.md` merena je na test-formama
sa `a = 3` i `a = 9` (jednolimbni koeficijenti!). Tamo xgcd radi nad sićušnim
brojevima. Na formama PUNE veličine (redukovane, `a` ~ 512 bita) izmereno je:

- Euklid gcd(a, b): ~245 iteracija × ~13,8k po divmod-u ≈ **3,4M** (sada binarni: manje)
- jedno kvadriranje pune veličine: **8,7M**
- jedna kompozicija pune veličine: **21M**
- projekcija verifikacije (80 sq + 60 comp, izmereno na uzorku od 31 op):
  **~2,35 milijarde gasa**

Dakle stara procena „~56–65M po verifikaciji" bila je potcenjena ~35×, iz dva
razloga: (1) per-op cena ekstrapolirana sa malih koeficijenata, (2) kvadratni
rast memorije koji bez kompaktovanja obara i 30 operacija. Head-to-head test
potvrdio je da divmod od ~12k na malim brojevima NIJE regresija — originalna
biblioteka košta isto (621k vs 605k za 50 deoba).

## Revidirana mapa puta

1. **Lehmer xgcd** — NEZAOBILAZAN sledeći korak. Batch-uje kvocijente u native
   256-bitnim rečima; očekivano 10–20× na Euklidovom delu koji sada dominira
   (verifikacija ~2,35B → ~150–300M). Namerno NIJE implementiran nabrzinu:
   suptilan je (Collins/Jebelean uslov ispravnosti kvocijenata) i zaslužuje
   diferencijalni fuzz naspram naivnog `xgcdHalf` + Python vektore, po
   disciplini projekta. `GcdFuzz.t.sol` je već postavljen kao šablon.
2. Assembly / fiksni limbovi za vruće petlje (2–4×).
3. NUCOMP/NUDUPL puna varijanta (drži međurezultate malim).
4. Tek posle Lehmer-a ima smisla ponovo raditi L1/L2 računicu; do tada je i
   Base tesan za jednu transakciju, pa nastavljiva verifikacija (checkpoint
   segmenti) ostaje obavezna arhitektura, ne opcija.

## Napomene

- `foundry.toml` u ovom paketu nema `solc = ...` putanju (bila je specifična za
  okruženje u kome je mereno).
- Novi testovi: `GcdFuzz.t.sol` (diferencijalni fuzz gcd/xgcdHalf),
  `VerifyShapedBench.t.sol` (pošten bench pune veličine + dokaz da kompaktne
  operacije daju identične forme kao obične).


---

# NIVO 2 — Lehmer xgcd (ova sesija)

Svih 39 testova prolazi: Python vektori (kompozicija, pow), e2e aukcija/vault,
i 5 fuzz suita (~1150 slucajnih slucajeva po punom prolazu).

## Sta je dodato

**LibBigInt.sol**
1. **Lehmer-ov `xgcdHalf`** — gornjih 255 bitova oba operanda u native reci;
   kvocijenti se sertifikuju Knuth 4.5.2 interval-uslovom (q1 == q2 uz
   najgori slucaj odsecenih bitova); batch koraka se akumulira u 2×2 matricu
   (magnitude + parnost znakova) i primenjuje odjednom na velike brojeve i na
   Bezout par. Ako sertifikacija ne uspe — JEDAN pun divmod korak, pa se
   nastavlja: korektnost nikad ne zavisi od aproksimacije. Zavrsnica u
   jednorecnom egzaktnom Euklidu sa flush-om matrice pred overflow.
2. `gcd` delegira na Lehmer engine. Stari algoritmi ostaju kao NEZAVISNE
   referentne familije za fuzz: `xgcdHalfClassic` (Euklid), `gcdBinary` (Stein).
3. `divmodFast` — floor divmod sa procenom kvocijenta iz gornjih reci
   (_div512by256) + korekcija ±1; egzaktno identican divmod-u, fallback za
   velike kvocijente. Koristi se u reduce/normalize petljama i Lehmer fallback-u.
4. `_clz` kao binarna pretraga (8 koraka umesto do 256 iteracija bit-petlje).

**LibClassGroupBig.sol**
5. `reduce`/`normalize`: trik sa ostatkom — `b' = c − rem` odnosno `b2 = a − rem`
   (nula mnozenja za novi b!), dedup dupliranih `mul` poziva (2 umesto 3-4 po koraku).

**Fuzz (GcdFuzz.t.sol)**: Lehmer vs klasicni Euklid (512-bit i 1024-bit, sa
znacima), Lehmer vs binarni Stein, zajednicki faktori, Bezout svojstvo,
divmodFast vs divmod — sve tri nezavisne familije algoritama se medjusobno
potvrdjuju.

## Izmereno (pune 1024-bit velicine)

| metrika | nivo 1 | nivo 2 | faktor |
|---|---|---|---|
| xgcdHalf 512-bit | 3.847.169 | 460.268 | 8,4× |
| xgcdHalf 1024-bit | 11.517.979 | 1.023.603 | 11,3× |
| kvadriranje pune velicine | 8.706.385 | 3.309.357 | 2,6× |
| kompozicija pune velicine | 21.088.639 | 5.802.830 | 3,6× |
| kompozicija (mali fixture) | 330.066 | 217.400 | 1,5× |
| pow g^(2^4) | ~1.050.000 | ~399.000 | 2,6× |
| **PUNA verifikacija (80 sq + 74 comp, IZMERENO)** | ~2,35B (OOG, projekcija) | **869.295.584** | 2,7× |

Puna verifikacija je prvi put IZVRSIVA u jednom pozivu (869M < 1B forge limita);
per-op prosek 5,64M.

## Gde je otislo usko grlo

`reduce()` je sada dominantan (~2,8M od 3,3M po kvadriranju): NUDUPL-lite izlaz
ima a₃ = a² pune 1024-bitne sirine, pa redukcija radi ~150 koraka po ~18k
(svaki korak = divmodFast + 2 mul + par add/sub, gde alokacioni overhead
Int operacija od ~1-2,5k po pozivu dominira). Mikro-optimizacije koraka su
iscrpljene — resenje je STRUKTURNO:

## Nivo 3 (sledeci): NUCOMP/NUDUPL

Parcijalni xgcd (Lehmer engine se direktno prenamenjuje: stani kad ostatak
padne ispod |D|^(1/4)) drzi SVE medjuproizvode na ~pola sirine, pa izlazna
forma izlazi skoro-redukovana (O(1) koraka reduce umesto ~150). Ocekivano:
kvadriranje ~0,6-1M, kompozicija ~1,5-2,5M, verifikacija ~100-250M.
Formule kofaktora uzeti iz reference (Cohen alg. 5.4.8-5.4.9 / Jacobson-van
der Poorten) i verifikovati protiv Python vektora — NE izvoditi napamet.

## Ekonomika (za proveru na tekucim parametrima mreza)

- L1 posle Fusaka/EIP-7825 (tx cap 16,77M): verifikacija = ~55-60 segmenata
  nastavljive verifikacije. Skupo, ali izvodljivo.
- Base/L2: 869M je i dalje vise od tipicnog bloka — nastavljiva verifikacija
  (openBidStart/openBidStep checkpoint arhitektura iz ranije analize) ostaje
  OBAVEZNA i posle nivoa 2; broj segmenata na Base ~3-10 zavisno od limita.
- Tek nivo 3 (NUCOMP, ~100-250M) otvara mogucnost verifikacije u 1-2 tx na L2.


---

# NIVO 3 — NUDUPL kvadriranje (ova sesija)

Svih 46 testova prolazi: Python vektori, e2e aukcija/vault, 6 fuzz suita +
novi diferencijalni lanac (25 punih iteracija NUDUPL == compose(f,f) uz
proveru diskriminante na svakom koraku).

## Sta je dodato

**LibBigInt.sol**
1. `xgcdPartial(a, mu, stopBits)` — parcijalni Euklid za NUDUPL: vraca
   (r_{k-1}, r_k, beta_{k-1}, beta_k, parnost). Ponovo koristi Lehmer
   `_certifiedLoop` (sada parametrizovan bound-om) sa dinamickim bound-om
   2^(gap+2) blizu praga, da batch ne prebaci prag znacajno. SVAKA tacka
   zaustavljanja daje validnu unimodularnu transformaciju — prag utice samo
   na balans velicina, ne na korektnost.
2. `bitLen(Int)` helper.
3. **Bugfix (nasao fuzz!)**: `xgcdHalf(0, b)` je posle swap-a zvao fallback
   divmod sa nulom. Dodata nula-provera + deterministicka regresija
   `test_ZeroEdges`. Pouka: fuzz familije drzati zauvek.

**LibClassGroupBig.sol**
4. `square` za viselimbno `a`: parcijalni Euklid na (a, mu) do praga
   **bitLen(D)/4**, pa forma iz kompaktne reprezentacije
   F(x,y) = (ax − mu*y)^2 + bxy − e*y^2 SL2 smenom:
   - A' = (a r'^2 − b r' β' + c β'^2)/a   (egzaktno deljenje + require tripwire)
   - C' = (a r^2 − b r β + c β^2)/a
   - B'0 = (2a r r' − b(β r' + β' r) + 2c β β')/a ; B' = ±B'0 po parnosti koraka
   Izvod verifikovan: k = 0 koraka reprodukuje TACNO klasicne formule
   (a², b−2aμ, klasicno C); k > 0 pokriva diferencijalni lanac.
   Male forme (a u jednoj reci) zadrzavaju direktne formule.
5. **Prag mora biti bitLen(D)/4, NE bitLen(a)/2**: balans A' ~ 2^(2t) naspram
   C' ~ 2^(|D|bits − 2t) ne zavisi od velicine a (za malo a, c je srazmerno
   vece). Pogresan prag je ostavljao ~60 koraka redukcije i ~2x sporije
   kvadriranje — nadjeno profilisanjem, potvrdjeno merenjem.

## Izmereno (pune 1024-bit velicine)

| metrika | nivo 1 | nivo 2 | nivo 3 | ukupno |
|---|---|---|---|---|
| kvadriranje pune velicine | 8.706.385 | 3.309.357 | **847.216** | 10,3× |
| kompozicija pune velicine | 21.088.639 | 5.802.830 | 5.606.024 | 3,8× |
| pow g^(2^4) | ~1.050.000 | ~399.000 | ~405.000 | — |
| **PUNA verifikacija (80 sq + 74 comp)** | ~2,35B (OOG) | 869.295.584 | **488.969.351** | ~4,8× |

Struktura verifikacije sada: kompozicije 74 × 5,6M ≈ 415M (85%!),
kvadriranja 80 × 0,85M ≈ 68M.

## Nivo 4 (sledeci): NUCOMP za kompoziciju

Kvadriranje je reseno; kompozicija je ostala na klasicnoj stazi (xgcd nad
1024-bit modulom s*t + puna redukcija) i sada nosi 85% cene. NUCOMP za
opsti slucaj trazi van der Poorten-ove formule sa dva kofaktorska niza —
za njih uzeti referencu (Jacobson & van der Poorten, "Computational aspects
of NUCOMP" / Cohen alg. 5.4.9) i generisati Python vektore PRE Solidity
implementacije; xgcdPartial i diferencijalna infrastruktura su vec spremni.
Ocekivano: kompozicija ~1-1,5M => verifikacija ~150-190M.

## Ekonomika posle nivoa 3 (proveriti na tekucim parametrima)

- L1 (tx cap 16,77M): ~30-35 segmenata nastavljive verifikacije.
- Base/L2: ~2-5 segmenata; sa nivoom 4 realno 1-2 transakcije.
- Nastavljiva verifikacija (openBidStart/openBidStep) i dalje obavezna
  arhitektura dok se ne isporuci nivo 4.


---

# NIVO 4 — NUCOMP za kompoziciju (ova sesija)

Svih 56 testova prolazi: Python vektori, e2e aukcija/vault, 6 fuzz suita,
NUDUPL diferencijalni lanac, i NOVO: NUCOMP diferencijalni testovi
(2 usmerena vektora oba puta + 12-vektorski fuzz na 1024-bit + fallback provera).

## Šta je dodato

Kompozicija je do sada bila na klasičnoj stazi (xgcd nad modulom s*t + puna
redukcija ~150 koraka) i nosila je 85% cene verifikacije. Nivo 4 uvodi pravu
NUCOMP kompoziciju po **van der Poorten, "A note on nucomp", Math. Comp. 72
(2003), Algoritam 3** (strana 1944) — formule prepisane iz rada, NE izvedene
napamet, pa validirane.

**LibClassGroupBig.sol**
1. `nucomp(f1, f2, D)` — Algoritam 3 bez Distance dela. Koraci 1-4 postave
   "magic matrix" (Bezout preko Lehmer `xgcdHalf`, konvencija b*u2 + c*u1 = F),
   korak 5 je parcijalni Euklid preko postojećeg Lehmer `xgcdPartial` (isti
   engine kao NUDUPL, batch-uje količnike u native reči), korak 6 sastavlja
   near-reduced formu. Pokriva obe grane (F=1 česta, F∤s retka) i z=0 specijalni
   slučaj (Cohen 5.4.9 / Note iv). Distinktne forme su preduslov — za f1==f2
   fallback na `square` (NUDUPL).
2. `nucompCompact` — memorijski-upravljan omotač (isti kao composeCompact).

**Ključne ispravke pri portu (nađene diferencijalnim testom protiv `compose`):**
- Konvencija Bezout-a u radu je `b*u2 + c*u1 = F` (b množi u2!), ne obrnuto.
- z=0 grana koristi w2, ne w1.
- Umesto `_isqrt` za prag L=|D|^(1/4), koristi se bitLen(D)/4 (kao NUDUPL) —
  `xgcdPartial` ionako radi na bitLen pragu, pa je ceo isqrt izbačen.
- Bezout preko `xgcdHalf` (Lehmer, 461k) umesto punog klasičnog `xgcd` (~3M) —
  ovo je bio glavni gas dobitak (9M → 983k po kompoziciji).

## Validacija (disciplina projekta)

- Python referentna NUCOMP validirana protiv `compose`: **1600/1600** tačno na
  256/512/1024/1792-bit, uz proveru da diskriminanta ostaje D na svakom rezultatu.
- Koprimni I nekoprimni put zasebno: 4210/4210 + 1952/1952 na 256-bit.
- Solidity: 2 usmerena 1024-bit vektora (oba puta) + 12-vektorski diferencijalni
  fuzz + provera da nucomp(f,f)==square(f).

## Izmereno (pune 1024-bit veličine)

| metrika | nivo 3 | nivo 4 | faktor |
|---|---|---|---|
| kompozicija (standalone) | 5.606.024 | ~983.000* | ~5,7× |
| **PUNA verifikacija (80 sq + 74 comp), IZMERENO u lancu** | 489.204.163 | **227.853.346** | 2,15× |
| per-op prosek | 3.176.650 | 1.479.567 | 2,15× |

*Standalone cifra je na test-vektoru sa malim koeficijentima rezultata; u lancu
pune veličine (accumulator × baza) NUCOMP+kompaktovanje košta ~2,1M po pozivu.
Poštena brojka za prezentaciju je **verifikacija u lancu: 489M → 228M**.

Ukupno od početka (nivo 0 → nivo 4): **~2,35 milijarde → 228M ≈ 10×.**

## Ekonomika posle nivoa 4 (proveriti na tekućim parametrima)

- Verifikacija 228M je i dalje iznad jednog L1 bloka (~36M), pa nastavljiva
  verifikacija (checkpoint segmenti kroz više transakcija) ostaje potrebna na L1:
  ~7 segmenata umesto ~14 na nivou 3.
- Na L2 (Base i sl.) 228M je 1-2 transakcije umesto 3-5.
- Sledeći strukturni koraci: assembly za vruće petlje množenja/deljenja (2-4×),
  ili SNARK omotač (verifikacija ~300k bez obzira na veličinu) za pravi L1.
