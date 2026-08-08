# Sealed-Bid Auction over Class Groups

A working prototype of a **sealed-bid auction with no trusted party**. Each bid is
locked in a timelock envelope over the class group of an imaginary quadratic field
(a group of unknown order, so there is no shortcut and no trusted setup). Opening an
envelope takes T sequential squarings, and the smart contract verifies the Wesolowski
proof, **decrypts the amounts itself**, and **picks the winner itself**. Class groups
are listed as an unimplemented direction in a16z's Cicada repo, which is where this started.

## Live demo across machines (auctioneer + bidders)

You need [Foundry](https://getfoundry.sh) on the auctioneer machine; bidders only need a
browser. Everyone on the same (WiFi) network.

**Auctioneer:**
```
anvil --host 0.0.0.0
```
(`--host 0.0.0.0` is required so the network can reach you. Allow it when Windows Firewall
asks. If the prompt was missed:
`netsh advfirewall firewall add rule name="anvil" dir=in action=allow protocol=TCP localport=8545`)

Then open `auction.html`, pick **Run the auction**, click **Derive from block hash**,
choose how long bidding stays open, and deploy. The page shows the **contract address**
and your RPC URL (`http://YOUR-IP:8545`; find the IP with `ipconfig`).

**Bidders:** download `auction.html` from this repo and open it locally, pick
**Place a bid**, enter the RPC URL and contract address from the auctioneer screen, then
name and secret amount. The bid is sealed locally (the secret never leaves the machine;
only the ciphertext goes on chain), and they watch envelopes open and the contract decide.

> The page is opened **locally** (double-click), not via GitHub Pages: an https page
> cannot talk to an http RPC (mixed content).

## What is real

- The puzzle is derived from a fresh block hash; every bid uses a fresh random r.
- Envelopes, parameters (g, h, T, salt) and all state live **in the contract**. Bidder
  clients read everything from chain; the auctioneer opens from chain.
- Unlocking starts as each bid arrives, but T is set longer than the auction, so no
  envelope opens before closing time.
- The contract rejects invalid proofs (revert), decrypts on chain (the key is derivable
  only from w = u^(2^T), bound to the bidder address and salt), and `finalize()` picks the
  winner on chain.
- **Nobody depends on the auctioneer.** Opening and finalizing are permissionless: any
  bidder can click "Compute the opening on this machine" and their own browser does the
  squarings, builds the proof and submits it. Closing is auctioneer-only until the
  deadline, after which anyone can close. If the auctioneer machine disappears, the
  auction still finishes (covered by an end-to-end test).
- The browser crypto matches the Python and Solidity reference byte for byte. Foundry
  tests: `cd solidity && forge install foundry-rs/forge-std --no-git && forge test`.

## Layout

```
auction.html     web demo (one file: UI + crypto + web workers + JSON-RPC)
python-demo/     reference implementation + CLI (setup/lock/unlock/verify)
solidity/        LibClassGroup.sol, TimelockVault.sol, SealedAuction.sol, forge tests,
                 live_demo.py (CLI flow on anvil)
docs/            idea summary, timing-attack analysis
```

## Measured numbers

- on-chain Wesolowski verification: 19.96M -> **2.62M gas** after optimization
  (unchecked ~4.6x, Shamir simultaneous exponentiation ~40%)
- `openBid` (verify + on-chain decrypt): ~2.7M gas
- proof generation: checkpoint method ~3x faster than the naive pass, and the web demo
  splits the proof across all CPU cores (near-linear: ~5x on 4 cores, ~9x on 8)

## Honest limitations

The 96-bit discriminant is a toy (production needs thousands of bits and big-integer
arithmetic on chain; the realistic path is a SNARK wrapper or aggregation). The proof of
the h setup is skipped in the web demo (it exists in the full protocol; the Python demo
generates it). anvil is a local demo chain. The code is a proof of concept without audit.
See `docs/rezime-i-tajming-rupe.md` for the attack analysis.

---
Student research project (Petnica, 2026).
