# Solidity demo — TimelockVault nad klasnom grupom

Odgovor na pitanje „da li ovo može u Solidityju": **da — verifikacija ide
on-chain, teški rad ostaje off-chain.** Ovaj projekat je radan dokaz:

- `src/LibClassGroup.sol` — aritmetika klasne grupe (redukcija, Gausova
  kompozicija, stepenovanje) u čistom `int256`
- `src/TimelockVault.sol` — ugovor koji drži ETH iza puzzle-a `u` i pušta
  sredstva **samo** uz `(w, π)` koje prođe Wesolowski proveru
  `π^ℓ · u^(2^T mod ℓ) == w` (ℓ se izvodi on-chain: sha256 + Miller–Rabin)
- `test/TimelockVault.t.sol` — Foundry testovi sa vektorima iz Python
  reference: validan dokaz ✓, lažno w ✗, pogrešan π ✗, ceo lock→claim tok,
  merenje gasa
- `gen_vectors.py` — generiše vektore i **bajt-za-bajt isto** izvodi ℓ kao
  ugovor (diferencijalno testiranje Python ↔ Solidity)

## Pokretanje

```bash
# 1. Instaliraj Foundry (jednom): https://getfoundry.sh
curl -L https://foundry.paradigm.xyz | bash && foundryup
#    (Windows: najlakše kroz WSL, ili Git Bash sa foundryup)

# 2. Povuci forge-std (jednom):
forge install foundry-rs/forge-std --no-git

# 3. Testovi:
forge test -vv
```

Očekivano: 7/7 PASS (uz gas log koji test ispisuje za obe verzije verifikacije).

Vektori su već ugrađeni u test; ako menjaš parametre, regeneriši ih:
`python3 gen_vectors.py` (traži `classgroup.py` iz Python dema na putanji —
prilagodi `sys.path` na vrhu).


## LIVE demo pred mentorom (ne testovi — pravi lanac, ništa unapred)

Testovi sa ugrađenim vektorima dokazuju korektnost, ali za publiku je jači
`live_demo.py`: **svaki put iznova** deploy-uje ugovor na lokalni lanac,
napravi svež puzzle sa novim slučajnim r, zaključa ETH, uživo pokaže da
lažno rešenje puca, pa odradi T kvadriranja pred svima i tek onda isplati.
Nema nijednog unapred izračunatog broja — mentor može sam da izabere
trajanje i iznos.

Priprema: iskopiraj `classgroup.py` iz Python dema u ovaj folder.

```bash
# terminal 1 (ostavi da radi):
anvil

# terminal 2:
python3 live_demo.py --seconds 600     # ~10 min kvadriranja
python3 live_demo.py --seconds 30      # kratka proba
```

Šta se vidi, redom: kalibracija mašine → deploy → svež puzzle
**hash-to-group** (u se izvodi heširanjem block hasha + fraze koju mentor
sam ukuca — pa tajni eksponent r ne postoji ni za koga, ni tvorac dema
nema prečicu; bez toga bi tvorac koji zna r mogao da otvori odmah preko
h^r) → lock 1 ETH, stanje primaoca 0 → lažan claim: `revert: invalid proof` →
T kvadriranja sa progress barom → Wesolowski dokaz (traje ~isto, vidi
Python README zašto) → claim: verifikacija na lancu, **+1 ETH primaocu** →
dupli claim odbijen.

Napomena o trajanju: `--seconds` je faza kvadriranja. Dokaz se sastavlja
iz kontrolnih tačaka snimljenih usput (svaki 128. međurezultat u^(2^j) —
π = Π C_m^(q_m) po blokovima bitova količnika q = ⌊2^T/ℓ⌋), pa umesto
drugog punog prolaza traje ~⅓ toga, a sa `--workers 4` (podela nezavisnih
blokova na procese) još manje — izmereno: 20s kvadriranja + 9s dokaza.
Za 10-minutni demo dakle računaj ~13–14 min ukupno do isplate.

## Šta demo pokazuje

1. **Podela rada.** Solver off-chain odradi T kvadriranja (sat vremena) i
   napravi π; ugovor on-chain uradi ~2×80 grupovnih operacija verifikacije,
   **nezavisno od T**. Ugovor nikad ne vrti timelock — samo proverava.
2. **Bez poverenja i on-chain.** Izazov ℓ ugovor sam izvodi Fiat–Shamirom
   (sha256 → Miller–Rabin do prvog prostog), pa solver ne može da bira ℓ
   sebi u korist. Falsifikati padaju (testirano).
3. **Optimizovana verifikacija.** U ugovoru su obe verzije (`verify` i
   `verifyNaive`) pa test ispisuje poredjenje. Primenjeno je `unchecked` u
   vrucim petljama i Shamirov trik (pi^l i u^r u jednom zajednickom prolazu
   kvadriranja umesto dva stepenovanja).

Detaljne izmerene brojke, izbor parametara i mapa optimizacija su u `../docs/`
(namerno odvojeno od ovog README-a).

## Veza sa Python demoom

Isti algoritmi, ista šema; jedina razlika u kompoziciji je redukcija
`k mod s·t` (da međuproizvodi stanu u int256) — `gen_vectors.py` na startu
dokazuje da to daje identične klase kao referentna implementacija.
