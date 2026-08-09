# Rezime ideje + analiza rupa u tajmingu

## 1. Šta trenutno imamo (rezime u osam tačaka)

1. **Grupa bez poverenja:** diskriminanta D = −p se izvodi heširanjem javnog
   seed-a (block hash) → niko ne bira grupu, niko ne zna njen red → ne
   postoji prečica kroz puzzle, ni za tvorca sistema.
2. **Jednokratni setup:** h = g^(2^T) se izračuna jednom (T sekvencijalnih
   kvadriranja) uz Wesolowski dokaz ispravnosti; posle služi svima zauvek.
3. **Lock (trenutan):** ponuđač bira slučajno r, objavi u = g^r i šifrat
   (ključ h^r), obriše r. Alternativa za "ni tvorac nema prečicu":
   hash-to-group — u se izvede heširanjem, pa r ne postoji ni za koga.
4. **Unlock (garantovano spor):** jedini put do ključa je w = u^(2^T) —
   T uzastopnih kvadriranja; paralelizacija ne pomaže jer korak k čeka
   korak k−1. Ovo je "sat".
5. **Dokaz (jeftin uz checkpoint trik):** solver iz međurezultata koraka
   unlock sastavi Wesolowski π za ~⅓ vremena kvadriranja (i deljivo na
   više jezgara) — izmereno u live_demo.py.
6. **On-chain verifikacija:** ugovor proveri π^ℓ · u^(2^T mod ℓ) == w za
   ~2,7M gasa (posle optimizacija: unchecked + Shamir; sa 20M), nezavisno
   od T; ℓ izvodi sam (sha256 + Miller–Rabin). Lažna rešenja padaju.
7. **Svežina izazova:** puzzle ne sme biti poznat unapred (inače
   prekomputacija) — u nastaje tek objavom na lancu / iz podatka koji ne
   postoji ranije (budući block hash, fraza na licu mesta).
8. **Demo parametri su igračka** (96/512-bitna diskriminanta); produkcija
   traži hiljade bitova i bignum aritmetiku on-chain.

Vremenska garancija koju sistem daje: **sadržaj puzzle-a objavljenog u
trenutku t niko ne može saznati pre t + T** (na referentnom hardveru).
Sve rupe ispod su načini da ta garancija bude tačna, a aukcija ipak
izigrana — jer aukcija zavisi i od tajminga *okolo* garancije.

## 2. Rupe u tajmingu, od najozbiljnije

### R1 — Sat kreće od LOCK-a, ne od zatvaranja aukcije  ★ najvažnija

Ponuda zaključana u 10:00 sa T = 1h postaje čitljiva u 11:00 — a aukcija
traje do 12:00. Napadač počne kvadriranje čim ponuda padne na lanac,
pročita rivalske rane ponude PRE zatvaranja, pa licitira +1 dinar preko
najveće. Timelock garancija nije prekršena — ali aukcija jeste.

**Odbrana:** T ≥ celo trajanje prozora za licitiranje (+ margina), tako da
se i najranija ponuda otvara tek posle zatvaranja. Posledice: (a) dužina
aukcije je ograničena praktičnim T; (b) anti-sniping produžeci aukcije su
ZABRANJENI — produžetak posle zadnje ponude znači da rane ponude pucaju
pre novog kraja. Ovo je dizajnersko ograničenje koje treba reći unapred.

### R2 — Zagušenje/cenzura NA ULAZU (oko zatvaranja)

Ovo je verovatno ono na šta mentor cilja. Rok "ponude do bloka N": napadač
pred sam rok zakupi blockspace (stuffing) ili je mreža prirodno zagušena —
rivalske ponude poslate na vreme uđu u blok N+2, ugovor ih odbije, napadač
pobedi jer je konkurencija "zakasnila". Nije prevara nad kriptografijom,
nego nad redom ulaska u blokove.

**Odbrana:** dug prozor za licitiranje (stuffing od 10 blokova je izvodljiv
i jeftin, od 1000 blokova nije); rok izražen u blokovima, ne u sekundama;
na L2 sa force-inclusion mehanizmom (transakcija se može naterati kroz L1);
i pošteno priznanje: protiv base-layer cenzure poslednje linije odbrane
nema ni jedan on-chain protokol.

### R3 — Zagušenje/cenzura NA IZLAZU (oko roka za otvaranje)

Ako protokol ima rok "rešenja do bloka M" sa default ishodom po isteku
(poništenje aukcije, vraćanje depozita, kazna za neotvorene ponude) —
strana kojoj default odgovara (npr. gubitnik, ili pobednik koji se
pokajao) može zagušenjem/cenzurom da drži claim van blokova do isteka.
"Prevara nakon transakcije": solve je pošten, w je tačan, ali ne može da
uđe u blok na vreme.

**Odbrana:** velikodušan rok za otvaranje (red veličine dana, u blokovima);
permissionless otvaranje — pošto SVAKO može da rešava i podnese (naša šema
to već ima!), napadač mora da cenzuriše sve solvere, ne jednog; više
nezavisnih solvera sa različitim putevima slanja (javni mempool + privatni
relayi); bez oštrih default ishoda gde je moguće.

### R4 — Krađa solver-nagrade u mempoolu (MEV front-running)

Ako se solveru plaća nagrada za podneto rešenje: njegov claim sa (w, π)
stoji u mempoolu; bot ga kopira i pošalje isti sadržaj sa većim gasom —
uđe pre njega i uzme nagradu. Rad od sat vremena, plata botu.

**Odbrana:** u našem demo vault-u nema mete (primalac je fiksiran pri
lock-u, front-runner samo pokloni gas); u pravoj aukciji: nagrada vezana
za adresu kroz commit-reveal (prvo hash(w,π,moja adresa), pa otkrivanje),
ili slanje kroz privatni relay (Flashbots), ili nagrada koja se deli.

### R5 — "Đubre" ponude (garbage-bid DoS)

Ponuđač pošalje u i šifrat koji ne dešifruje ni u šta validno. Solver
pošteno plati T kvadriranja i dobije đubre; sa 50 takvih ponuda, otvaranje
aukcije košta 50T uzalud. Tajming ugao: napadač time i rasteže ukupno
vreme otvaranja preko roka iz R3.

**Odbrana:** depozit uz svaku ponudu koji propada ako otvaranje da
nevalidan sadržaj; paralelno otvaranje različitih ponuda (nezavisni
lanci kvadriranja — različite koverte SMEJU paralelno, samo jedna ne može
brže); ekonomsko dimenzionisanje: depozit > trošak solvera.

### R6 — Brži hardver (tiha rupa u samom T)

Ne zagušenje, ali tajming: "1h" važi na referentnom hardveru. ASIC za
kvadriranje u klasnoj grupi (Chia ekosistem ih je proizveo!) može biti
red veličine brži od laptopa — napadač sa njim čita ponude pre ostalih,
možda i pre zatvaranja ako je T tesno uz R1.

**Odbrana:** T se bira po NAJBRŽEM poznatom hardveru sa marginom (pa
prozor licitiranja još kraći od T/margina); ovo je poznata, otvorena
slabost svih VDF sistema i pošteno se navodi.

### R7 — Sitnice: timestamp i reorg

Proposer može block.timestamp da pomeri za sekunde (rokove vezivati za
blokove); plitki reorg može da "izbriše" uključen claim pa se šalje
ponovo (čekati potvrde za konačnost). Oba minorna naspram R1–R3.

## 3. Šta naš demo pokriva, a šta ne (za iskren razgovor)

Pokriva: garanciju t+T po puzzle-u, nemogućnost prečice i prekomputacije,
odbijanje lažnih rešenja, jeftinu verifikaciju, permissionless otvaranje.
Ne pokriva (i ne treba, ali se kaže): pravila aukcije oko rokova — R1
(T ≥ trajanje), R2/R3 (prozori u blokovima, bez oštrih defaulta), R4
(commit za nagradu), R5 (depoziti). To je sledeći sloj dizajna — sloj
PROTOKOLA nad kriptografijom, i tačno mesto gde mentor s pravom kopa.

## 4. Jedna rečenica za mentora

„Kriptografska garancija je po-puzzle: ništa pre t+T — a rupe koje
pominjete su realne i žive u sloju protokola oko nje: sat koji kreće od
lock-a (zato T ≥ trajanje aukcije i nema produžetaka), cenzura ulaza i
izlaza oko rokova (zato dugi prozori u blokovima, permissionless solveri
i bez oštrih default ishoda), i MEV na nagradi (zato commit ili privatni
relay). Nijedna ne obara timelock; sve obaraju loše izabrana pravila oko
njega — i zato su ta pravila deo dizajna, ne fusnota."
