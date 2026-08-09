# Timelock enkripcija nad klasnim grupama — celokupna ideja i dosadašnji zaključci

## 1. Šta je ovo (u dve rečenice)

Infrastruktura za **garantovano vremensko otkrivanje informacija bez ijednog
subjekta od poverenja**: podatak se zaključa tako da ga niko na svetu ne može
pročitati pre isteka T (jer otvaranje zahteva T sekvencijalnih kvadriranja u
grupi nepoznatog reda), a posle T ga svako može otvoriti i jeftino dokazati
pametnom ugovoru da je otvaranje pošteno. Ključna razlika prema svim
postojećim rešenjima: nema komiteta, nema trusted setupa, nema nikoga ko
"čuva ključ" — otkrivanje garantuje fizika sekvencijalnog računanja, ne
nečija dobra volja.

## 2. Zašto klasne grupe (srce ideje)

Timelock puzzle zahteva grupu u kojoj je g^(2^T) izračunljivo SAMO sa T
uzastopnih kvadriranja. Prečica postoji samo ako znaš red grupe.

- **RSA pristup (Cicada, Riggs):** red grupe je tajna koju je neko znao pri
  generisanju modula i "obećao da je obrisao" → trusted setup ili skupa
  MPC ceremonija.
- **Naš pristup (klasne grupe imaginarnih kvadratnih polja):** diskriminanta
  D = −p se izvodi heširanjem javnog seed-a (block hash) → niko ne bira
  grupu → red grupe h(D) je matematička nepoznanica koju **niko nikad nije
  znao**, pa prečica ne postoji ni za tvorca sistema. Trusted setup je
  eliminisan, ne zamenjen ceremonijom.

Motivacija dolazi i iz dokumentovane rupe na tržištu: a16z-ov Cicada repo
eksplicitno navodi klasne grupe kao "future direction" koju nisu
implementirali.

## 3. Kako radi (protokol)

1. **SETUP (jednom, javno, verifikabilno):** iz seed-a se izvede D i
   generator g; neko odradi T kvadriranja do javnog parametra h = g^(2^T)
   i priloži Wesolowski dokaz ispravnosti (verifikacija ~ms). Jednokratna
   investicija koja služi za neograničen broj zaključavanja.
2. **LOCK (~100 ms, po poruci):** pošiljalac bira tajni eksponent r
   (izveden kao hash(tajni_seed, auction_id, nonce) protiv reciklaže),
   objavi u = g^r i šifrat sa ključem hash(h^r, adresa, auction_id)
   (vezivanje protiv kopiranja/replay-a), obriše r. Varijanta bez ikakvog
   tajnog r: hash-to-group (u izveden heširanjem javnih podataka) — tada
   ni tvorac nema prečicu, ali ni mogućnost brzog šifrovanja.
3. **UNLOCK (tačno T, bilo ko):** w = u^(2^T) sekvencijalnim kvadriranjem;
   paralelizacija ne pomaže (korak k čeka korak k−1). Otvaranje je
   permissionless — svako sa računarom može biti solver.
4. **DOKAZ + VERIFIKACIJA:** solver iz kontrolnih tačaka snimljenih usput
   sastavi Wesolowski dokaz π (~⅓ vremena kvadiranja, deljivo na jezgra);
   ugovor proveri π^ℓ · u^(2^T mod ℓ) == w za ~2,7M gasa, **nezavisno od
   T**, i tek onda izvrši (isplata, objava, itd).
5. **HOMOMORFNA VARIJANTA (za glasanje/agregaciju):** koverte oblika
   (g^r, h^r·f^b) se množe neotvorene → proizvod je jedna koverta koja
   sadrži ZBIR svih b. Otvara se samo zbir; pojedinačni unosi se nikad ne
   otvaraju. Jedan solve po glasanju umesto po glasu.

## 4. Šta je implementirano i izmereno (sve radi, sve testirano)

**Python referentna implementacija** (bez ijedne biblioteke):
aritmetika klasne grupe (Gausova kompozicija, redukcija), testovi
grupovnih zakona + reprodukcija poznatog rezultata |Cl(−23)| = 3,
CLI sa setup/lock/unlock/verify fazama, kalibracija T prema mašini.

**Solidity implementacija (Foundry):**
- `LibClassGroup.sol` — aritmetika u čistom int256 (demo diskriminanta
  96 bitova, dimenzionisana da međuproizvodi stanu bez bignum biblioteke)
- `TimelockVault.sol` — ugovor drži ETH iza puzzle-a; claim prolazi samo
  uz validan (w, π); ℓ izvodi sam on-chain (sha256 + Miller–Rabin)
- diferencijalno testiranje: Python i ugovor izvode ℓ bajt-za-bajt isto;
  test vektori generisani Python referencom
- **live demo na anvil lancu:** svež puzzle iz fraze ukucane na licu mesta
  (hash-to-group → nema šta da se zna unapred), lažan claim uživo odbijen,
  T kvadriranja pred publikom, isplata tek posle validne verifikacije

**Izmerene brojke:**
- on-chain verifikacija: **19,96M gasa → 2,62M** posle optimizacija
  (unchecked aritmetika ~4,6×; Shamirovo simultano dvostruko stepenovanje
  još ~40%) — uporedivo sa RSA referencom (Riggs ~2,5M) iako klasne grupe
  nemaju modexp precompile
- generisanje dokaza: checkpoint metoda (π sastavljen iz međurezultata
  glavnog računanja) ~3× brže od naivnog prolaza, dodatno deljivo na
  procese; izmereno 19s kvadriranja + 9s dokaza
- Python: ~7k kvadriranja/s na 512-bitnoj diskriminanti (kalibracija bira
  T za željeno zidno vreme)

## 5. Bezbednosna analiza — nalazi

Kriptografska garancija je uska i tačna: "sadržaj puzzle-a objavljenog u
trenutku t niko ne čita pre t+T na referentnom hardveru". Svi nađeni
napadi žive u sloju PROTOKOLA oko nje:

- **Sat kreće od lock-a, ne od zatvaranja:** T mora pokriti ceo prozor
  prijema (inače rane ponude pucaju pre kraja); anti-sniping produžeci su
  nekompatibilni sa šemom.
- **Cenzura/zagušenje na ulazu i izlazu:** stuffing blokova oko rokova
  (isključivanje rivalskih prijava; sprečavanje poštenog claim-a pre
  deadline-a). Odbrane: dugi prozori u blokovima, permissionless solveri
  (napadač mora cenzurisati sve, ne jednog), bez oštrih default ishoda,
  L2 force-inclusion.
- **MEV na solver-nagradi:** kopiranje (w,π) iz mempoola → commit-reveal
  za nagradu ili privatni relay.
- **Garbage puzzle DoS:** nevalidan sadržaj otkriven tek posle plaćenih T
  → depoziti koji propadaju, ZK dokaz dobre formiranosti (Cicada pristup).
- **Brži hardver:** T se dimenzioniše prema najbržem poznatom (ASIC-i za
  ovu operaciju postoje iz Chia ekosistema) sa marginom.
- **Fork/reorg:** grinding block hasha ne pomaže napadaču (evaluacija
  kandidata zahteva rešavanje istog nerešivog problema — izvođenje je
  grinding-otporno, za razliku od blockhash lutrija); jedini trošak je
  bačen rad na siročetu-grani → sav skup rad kreće od finalizovanog bloka
  (~13 min na Ethereum PoS).
- **Kopiranje/replay koverti:** rešeno vezivanjem ključa za
  (adresa, auction_id) i izvođenjem r po aukciji.

## 6. Use case-ovi, rangirani po uklopljenosti

Lakmus test — šema je najjača gde važi bar jedno: (1) tajno tačno određeno
vreme pa javno (simultanost), (2) otkrivanje mora biti zagarantovano
(niko ga ne može uskratiti, ni autor), (3) ni organizator ne sme znati
ranije.

1. **Sealed-bid aukcije** (primarni fokus): ponude tajne do zatvaranja,
   otvaranje zagarantovano, bez aukcionara od poverenja. NFT/token
   lansiranja, domenske aukcije, likvidacije.
2. **On-chain glasanje / DAO governance** (homomorfna varijanta): niko ne
   vidi međurezultate tokom glasanja (rešava dokumentovano taktiziranje
   kitova), otvara se samo zbir, pojedinačni glasovi nikad. Uz ograde:
   trajna tajnost listića zahteva anonimno podnošenje (Semaphore-stil),
   receipt-freeness je nerešiv na javnom lancu.
3. **Lutrije/nasumičnost bez sabotaže:** eliminiše refuse-to-reveal napad
   RANDAO stila — otkrivanje nije odluka učesnika.
4. **Simultane igre na lancu:** commit-reveal bez "zaboravio sam da
   otkrijem" griefinga.
5. **Garantovano objavljivanje:** responsible disclosure sa neopozivim
   rokom, embargo, insurance file — kredibilna pretnja koju ni autor ne
   može povući.
6. **Fer lansiranja:** cene/metadata/alokacije zaključane do kraja minta.
7. **Šifrovani mempool / batch DEX bez MEV-a:** najveće tržište, ali
   najteži fit (T u sekundama, cena solva po batchu) — dugoročni pravac.
8. **Prognostički turniri / sealed peer review:** homomorfno otvaranje
   samo proseka, anti-herding.

## 7. Konkurentski pejzaž i diferencijacija

- **Shutter Network, Fairblock:** threshold komiteti — moraš verovati da
  se prag komiteta neće dogovoriti/nestati/biti prinuđen. Mi: nula
  subjekata od poverenja.
- **Cicada (a16z), Riggs:** ista klasa protokola, ali RSA → trusted setup
  ili MPC ceremonija; klasne grupe navedene kao njihov nerealizovan pravac.
- **Chia:** koristi iste klasne grupe, ali za VDF/konsenzus, ne za
  timelock enkripciju aplikacija; njihov ekosistem je izvor ASIC
  benchmarka za dimenzionisanje T.
- **drand/tlock:** timelock preko threshold BLS mreže — opet komitet.

Pozicija: jedini pristup gde otkrivanje garantuje sekvencijalno računanje
(fizika), bez komiteta i bez setup ceremonije, sa on-chain verifikacijom
dokazanom u kodu.

## 8. Ograničenja i otvoreni problemi (pošteno)

- **Demo parametri su igračka:** 96-bit (Solidity) / 512-bit (Python)
  diskriminante; literatura (Dobson–Galbraith) za ozbiljnu sigurnost
  traži ~6656 bitova. Produkcija zahteva bignum aritmetiku on-chain
  (stil LibUint1024) → gas raste za red veličine; realan put do jeftine
  verifikacije je SNARK omotač (~300k gasa nezavisno od parametara) ili
  agregacija svih otvaranja u jedan dokaz.
- **Nema modexp precompile-a za klasne grupe** → strukturni gas hendikep
  10–50× prema RSA na L1; EIP za precompile je hipotetički dugoročni fix.
- **Ko plaća solve:** neko mora odraditi T po otvaranju (ili po batchu);
  ekonomika solver mreže (nagrade, MEV zaštita) je dizajnersko pitanje.
- **Nije post-kvantno** (red grupe kvantno izračunljiv) — prihvatljivo za
  garancije od sati/dana, ne za arhivsku tajnost.
- **Tajnost je skupa, ne večna:** svako MOŽE otvoriti svaku kovertu za T;
  gde treba trajna privatnost pojedinačnih unosa, kombinuje se sa
  anonimnim podnošenjem i homomorfnim otvaranjem samo agregata.
- Kod je proof-of-concept bez revizije.

## 9. Status

Radni end-to-end prototip (Python referenca + Solidity/Foundry +
live demo na lokalnom lancu), izmerene performanse i gas, sistematska
analiza napada, studentski istraživački projekat (Petnica). Sledeći
tehnički koraci po prioritetu: bignum biblioteka za prave parametre,
SNARK omotač verifikacije, homomorfna agregacija, ekonomika solver mreže.
