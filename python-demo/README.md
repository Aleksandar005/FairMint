# Timelock demo nad klasnim grupama

Mini demo koji pokazuje da klasne grupe zaista rade ono što tvrdimo: poruka
("transakcija") se može zaključati tako da je **niko na svetu** ne može otvoriti
pre nego što odradi T sekvencijalnih kvadriranja u grupi — jer niko ne zna red
grupe, pa prečica ne postoji. Verifikacija rešenja je pritom skoro trenutna
(Wesolowski dokaz) — to je deo koji bi u punom projektu radio pametni ugovor.

## Fajlovi

Sva četiri fajla idu u **isti folder**, bilo koji:

    classgroup.py        aritmetika klasne grupe (forme, redukcija, Gausova kompozicija)
    timelock.py          timelock šema + Wesolowski proof of exponentiation
    demo.py              CLI koji pokrećeš
    test_classgroup.py   testovi korektnosti aritmetike

Treba ti samo Python 3.8+ — nula biblioteka, nula instalacije.

## Kako se pokreće

```bash
# 1. Proveri da aritmetika radi (grupovni zakoni, Cl(-23) reda 3):
python3 test_classgroup.py

# 2. Izmeri brzinu svoje mašine i vidi koje T odgovara kom vremenu:
python3 demo.py calibrate

# 3. Brzi test celog toka (30 sekundi odlaganja):
python3 demo.py run --seconds 30 -m "posalji 1 ETH Marku"
```

## Demo pred mentorom (preporučeni scenario)

```bash
# PRE sastanka (jednom, javno, verifikabilno — vidi napomenu ispod):
python3 demo.py setup --seconds 3600        # parametri za odlaganje od 1h

# UŽIVO:
python3 demo.py lock -m "tajna transakcija"  # trenutno (~100 ms)
python3 demo.py unlock                       # kreće 1h kvadriranja, sa progress barom
# ...posle sat vremena...
python3 demo.py verify                       # ~100 ms, ✓ VALIDNO
```

Za sastanak je zgodno pored toga uživo pustiti i kratku verziju
(`setup --seconds 120` u drugom folderu) da mentor vidi ceo krug od početka
do kraja za par minuta, a dugu verziju držati kao dokaz da skalira na 1h.

## Šta tačno demo pokazuje (i šta reći mentoru)

**1. Bez trusted setupa.** Diskriminanta D = −p se determinisano izvodi iz
javnog seed-a (u produkciji: block hash). Niko ne bira grupu → niko ne zna
njen red h(D) → niko nema prečicu. Ovo je ključna razlika u odnosu na RSA
timelock, gde je red grupe *tajna koju je neko nekad znao*.

**2. Zašto setup traje koliko i unlock.** Pošto prečica ne postoji ni za nas,
neko mora jednom da odradi T kvadriranja da bi izračunao javni parametar
h = g^(2^T) — ali to se radi **jednom**, javno, i uz Wesolowski dokaz da je h
ispravan (demo ga generiše i proverava u setup-u). Posle toga je svako
zaključavanje trenutno: r slučajan, u = g^r, ključ iz h^r. Ovo je ista
struktura koju koristi Cicada — samo što kod njih setup zahteva poverenje
(RSA), a kod nas ne.

**3. Zašto otključavanje ne može brže.** Ključ je h^r = u^(2^T), a r je
obrisan. Jedini put je T uzastopnih kvadriranja u, gde kvadriranje broj k
zahteva rezultat kvadriranja k−1 — **paralelizacija ne pomaže**, 1000 mašina
je sporo koliko i jedna. Vreme kontroliše samo brzina jednog jezgra.

**4. Asimetrija rad/provera.** Otključavanje = T operacija; Wesolowski
verifikacija = ~512 operacija, nezavisno od T. U našem testu: 15 s naspram
111 ms. To je tačno ono što on-chain verifikator (LibClassGroup.sol) treba
da radi: primi (w, π), proveri π^l · u^(2^T mod l) == w, pusti transakciju.
Verifikacija odbija lažno w i lažni T (testirano).

## Pošteno o ograničenjima (reci ovo sam, pre nego što pitaju)

- **Demo parametri.** Diskriminanta je 512-bitna radi brzine u Pythonu.
  Dobson–Galbraith procenjuju da za ozbiljnu sigurnost treba diskriminanta
  reda ~6656 bitova. Ovo je proof-of-concept, ne produkcija.
- **Python je spor.** ~7.000 kvadriranja/s; C/Rust implementacija sa GMP-om
  je 2–3 reda veličine brža. Zato se T u praksi bira prema **najbržem
  poznatom hardveru** (Chia je zbog ovoga pravila javno takmičenje za VDF
  hardver), sa rezervom — a ne prema svom laptopu.
- **"1h" znači "1h na referentnom hardveru".** Neko sa ASIC-om otključava
  brže; garancija je donja granica sekvencijalnog rada, ne zidni sat.
- **Nije post-kvantno.** Red klasne grupe se kvantno računa u polinomijalnom
  vremenu — ali timelock treba da izdrži sate, ne decenije.
- XOR-keystream šifrovanje je demo; u produkciji AES-GCM/ChaCha20-Poly1305.

## Kako se ovo uklapa u ostatak projekta

Ovaj demo je Python referentna implementacija iz plana — služi za
diferencijalno testiranje Rust verzije (isti seed → isti D, g, h → rezultati
moraju da se poklope) i kao izvor test-vektora za `LibClassGroup.sol`:
`params.json`, `puzzle.json` i `solution.json` su tačno ulazi/izlazi koje
on-chain verifikator treba da prihvati odnosno odbije.
