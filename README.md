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

Očekivano: 7/7 PASS, sa logom:

```
verifyNaive() gas: ~4,300,000
verify() [Shamir + unchecked] gas: ~2,620,000
```

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
3. **Izmerene brojke za projekat (96-bitna diskriminanta):**
   prva verzija 19.96M gasa → posle optimizacija **2.62M** (7.6× manje),
   čime je demo na nivou RSA reference (Riggs, 1024-bit: ~2.5M po ponudi).
   Primenjeno: `unchecked` aritmetika u vrućim petljama (samo to je dalo
   ~4.6×, jer su overflow provere u xgcd petlji bile dominantan trošak) i
   Shamirov trik — π^ℓ i u^r u jednom zajedničkom prolazu kvadriranja
   umesto dva stepenovanja (još ~40%). U ugovoru su obe verzije
   (`verify` i `verifyNaive`) pa test ispisuje poređenje.
   Sledeće poluge, neprimenjene: hint za ℓ (counter uz dokaz), NUCOMP/NUDUPL
   kompozicija (~1.5–2×), windowed stepenovanje. Na produkcijskim veličinama
   diskriminante ulazi bignum aritmetika i gas raste za red veličine — pravi
   put do minimuma je SNARK omotač (~300k, nezavisno od parametara) ili
   agregacija svih otvaranja u jedan dokaz.

## Pošteno o ograničenjima

- **96-bitna diskriminanta je igračka** — izabrana da sva aritmetika stane
  u native `int256`. Bez ikakve sigurnosti; svrha je demonstracija logike i
  merenje. Produkcijske veličine (~hiljade bitova) traže bignum biblioteku
  u stilu Cicadinog `LibUint1024.sol` (aritmetika nad `uint256[N]`) — to je
  glavni inženjerski posao „pravog" projekta i tu gas raste dalje.
- ℓ je 80-bitni (soundness 2⁻⁸⁰) — dovoljno za demo; produkcija ide na
  128+ bitova, gde deterministički Miller–Rabin traži pažljiviji izbor baza.
- Gas nije optimizovan (školska kompozicija bez NUCOMP-a, bez pretračunatih
  tabela za stepenovanje) — brojka je gornja granica, ne dometa šeme.

## Veza sa Python demoom

Isti algoritmi, ista šema; jedina razlika u kompoziciji je redukcija
`k mod s·t` (da međuproizvodi stanu u int256) — `gen_vectors.py` na startu
dokazuje da to daje identične klase kao referentna implementacija.
