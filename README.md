# Zapečaćena aukcija nad klasnim grupama (timelock enkripcija)

Radni prototip **sealed-bid aukcije bez ijednog subjekta od poverenja**:
ponude se šifruju timelock kovertama nad klasnom grupom imaginarnog
kvadratnog polja (grupa nepoznatog reda → nema prečice, nema trusted
setupa), otvaranje zahteva T sekvencijalnih kvadriranja, a pametni ugovor
verifikuje Wesolowski dokaz, **sam dešifruje iznose** i **sam proglašava
pobednika**. Motivacija: klasne grupe su u a16z Cicada repou navedene kao
neimplementiran pravac.

## Živi demo sa više računara (aukcionar + ponuđači)

Potrebno: [Foundry](https://getfoundry.sh) na aukcionarovoj mašini;
ponuđačima samo browser. Svi na istoj (WiFi) mreži.

**Aukcionar:**
```
anvil --host 0.0.0.0
```
(`--host 0.0.0.0` je obavezan da bi te mreža videla; kad Windows Firewall
pita — dozvoli. Ako je prozor promakao:
`netsh advfirewall firewall add rule name="anvil" dir=in action=allow protocol=TCP localport=8545`)

Zatim otvori `aukcija.html` → **„Vodim aukciju"** → fraza iz publike +
trajanje → sajt izračuna h = g^(2^T), postavi ugovor i prikaže **adresu
ugovora** i tvoj RPC (`http://TVOJA-IP:8545`; IP saznaš sa `ipconfig`).

**Ponuđači (mentori):** skinu `aukcija.html` iz ovog repoa i otvore ga
lokalno → **„Dajem ponudu"** → unesu RPC i adresu ugovora sa aukcionarovog
ekrana → ime + tajni iznos → **„Zapečati i pošalji na lanac"**. Ponuda se
pečati lokalno (tajna ne napušta njihov računar; na lanac ide u = g^r i
šifrat), a na ekranu gledaju uživo kako koverte stižu, kako ih aukcionarova
mašina otvara i kako **ugovor** dešifruje iznose i bira pobednika.

> ⚠ `aukcija.html` se otvara **lokalno** (dupli klik), ne preko GitHub
> Pages: https stranica ne sme da priča sa http RPC-om (mixed content).

## Šta je stvarno (ništa nije hardkodovano)

- Puzzle nastaje iz fraze ukucane na licu mesta; svaka ponuda ima svež r.
- Koverte, parametri (g, h, T, salt) i sva stanja žive **u ugovoru** —
  ponuđački klijenti sve čitaju sa lanca, aukcionar otvara iz lanca.
- Ugovor odbija nevalidne dokaze (revert), dešifruje on-chain
  (ključ izvodljiv tek iz w = u^(2^T), vezan za adresu ponuđača i salt),
  `finalize()` bira pobednika on-chain.
- Kriptografija u browseru je bajt-za-bajt usklađena sa Python i Solidity
  referencom (diferencijalno testirano); Foundry testovi: `cd solidity &&
  forge install foundry-rs/forge-std --no-git && forge test`.

## Struktura

```
aukcija.html      web demo (1 fajl: UI + kriptografija + web workeri + JSON-RPC)
python-demo/      referentna implementacija + CLI (setup/lock/unlock/verify)
solidity/         LibClassGroup.sol, TimelockVault.sol, SealedAuction.sol,
                  forge testovi sa vektorima, live_demo.py (CLI tok na anvil-u)
docs/             rezime ideje, analiza tajming napada
```

## Izmerene brojke

- on-chain Wesolowski verifikacija: 19,96M → **2,62M gasa** posle
  optimizacija (unchecked ~4,6×, Shamirovo simultano stepenovanje ~40%)
- `openBid` (verifikacija + on-chain dešifrovanje): ~2,7M gasa
- generisanje dokaza: checkpoint metoda ~3× brže od naivnog prolaza

## Pošteno o ograničenjima

96-bitna diskriminanta je demo igračka (produkcija: hiljade bitova + bignum
on-chain, realan put je SNARK omotač ili agregacija); dokaz postavke h u
web demou je izostavljen radi trajanja (u punom protokolu postoji, Python
demo ga generiše); anvil je lokalni demo lanac; kod je proof-of-concept
bez revizije. Detaljna analiza napada: `docs/rezime-i-tajming-rupe.md`.

---
Studentski istraživački projekat (Petnica, 2026).
