# 1024-bit class group in Solidity: working code and measured gas

## What was built

A signed arbitrary-precision integer library (`LibBigInt.sol`) plus a class group
library over it (`LibClassGroupBig.sol`), so composition, reduction and powering run at
a real 1024-bit discriminant instead of the 96-bit toy. Everything is tested against the
Python reference: b^2 - 4ac = D holds under full bignum multiply, and g^2, g^3, g^5,
g^(2^4) match Python exactly. Division is separately property-tested (a = q*b + r,
0 <= r < b, and exact division a*b/b = a) over random inputs, Knuth edge cases, and a
256-run fuzz.

Why a new library rather than Cicada's `LibUint1024` directly: Cicada is modular-
arithmetic focused (mulMod, expMod, everything mod N), right for RSA. Class groups need
signed, non-modular integers with exact division and extended GCD. The limb layout and
the 256x256->512 word-multiply trick follow the same idea; the sign handling, multiply,
division and xgcd on top are specific to this use.

## Optimization trajectory (measured, each step tested against Python)

| step | one composition | note |
|---|---|---|
| bit-by-bit division | 16.3M gas | first working version |
| Knuth word-level division | 1.61M gas | 10x: divmod was ~1000x a multiply |
| native fast path (hi==0) | 589k gas | native `div` in the Euclidean tail |
| Warren 2-by-1 estimate | **463k gas** | native `div` replaces a 256-iter bit loop |

Net: **16.3M -> 463k per composition, a 35x improvement.** The whole thing was
division-bound; each step attacked the division inner loop, and correctness held against
the Python vectors and the fuzz suite throughout.

## What this means for on-chain verification

A Wesolowski verification is a Shamir double-exponentiation, about 120-140 compositions
for an 80-bit challenge. From 463k per composition:

| challenge | compositions | verify gas | vs 36M block |
|---|---|---|---|
| 80-bit (demo) | ~120-140 | ~56-65M | ~1.5-1.8x |
| 128-bit (production) | ~192 | ~89M | ~2.5x |

Before optimization this was ~2-3 **billion** gas (50-90x a block). We are now at the
doorstep of L1: a single 80-bit verification is ~1.5-1.8 blocks. Important framing for
a multi-bidder auction: **each `openBid` is its own transaction**, so the constraint is
per-verification, not the sum. Ten bidders is ten separate ~1.5-block transactions, not
one 15-block monster -- so the target is simply "one verification under 36M."

## Crossing the last step to L1

A single verification is still just over one block, so it does not yet fit in one L1
transaction as-is. The realistic ways across, in order:

1. **NUCOMP / NUDUPL composition.** The standard class-group speedup: partial Euclidean
   reduction keeps intermediates ~sqrt(|D|)-sized instead of letting them grow to |D|,
   which roughly halves composition cost again (~230k), putting an 80-bit verification
   near ~28-32M -- under a block. This is the genuine next optimization, but it is the
   most intricate piece (careful bounds, easy to get subtly wrong), so it is worth doing
   carefully rather than rushing.
2. **Split the verification across two transactions.** Checkpoint the multi-exp halfway;
   each half fits a block. Always works, costs one extra transaction.
3. **L2.** At ~56M an 80-bit verification is already an ordinary L2 transaction (cents).
   Nothing further needed.
4. **SNARK-wrapped verification.** Prove the check off-chain; the contract verifies a
   ~300k-gas SNARK regardless of discriminant size. The only path to RSA-comparable L1
   cost, and the right production answer at scale.

The remaining structural reason it is not cheaper: the EVM has a `modexp` precompile
that makes RSA exponentiation nearly free, but no precompile for class group arithmetic,
so every word operation runs as ordinary opcodes. Micro-optimization (NUCOMP, assembly
limb loops) can plausibly shave another 2-3x and cross the block boundary; getting to
RSA-cheap needs the SNARK path or a class-group precompile (an EIP).

## Files

- `solidity/src/LibBigInt.sol` -- signed bignum (add/sub/mul, Knuth+Warren divmod, xgcd)
- `solidity/src/LibClassGroupBig.sol` -- class group over bignum
- `solidity/test/LibBigInt.t.sol` -- primitive tests
- `solidity/test/DivEdge.t.sol` -- division property tests, Knuth edge cases, 256-run fuzz
- `solidity/test/LibClassGroupBig.t.sol` -- 1024-bit composition vs Python + gas
- Build note: needs `via_ir = true` (composition has many locals; the IR pipeline
  resolves the stack-too-deep).

The 96-bit `LibClassGroup.sol` / `SealedAuction.sol` remain the runnable live demo; this
1024-bit library is the "what it really costs" companion. One 80-bit verification is now
~1.5 blocks -- an L2-trivial cost and an L1-marginal one that NUCOMP or a two-transaction
split closes, rather than the non-starter it began as.
