// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibClassGroup as CG} from "./LibClassGroup.sol";

/// @title SealedAuction — zapečaćena aukcija nad class-group timelock kovertama
/// @notice Ceo tok presuđuje LANAC: ponude ulaze kao (u, šifrat), otvaranje
///         prolazi samo uz validan Wesolowski dokaz, a ugovor tada SAM
///         dešifruje iznos (ključ je izvodljiv iz w) i na kraju sam bira
///         pobednika. Frontend ništa ne odlučuje — samo prikazuje stanje.
contract SealedAuction {
    using CG for CG.Form;

    int256 public immutable D;
    uint256 public immutable T;
    bytes32 public immutable salt; // iz fraze publike — vezuje aukciju
    address public immutable auctioneer;
    uint256 public immutable deadline; // posle ovog trenutka BILO KO sme da zatvori
    CG.Form public g;              // generator — javno, sa lanca ga čitaju ponuđači
    CG.Form public h;              // h = g^(2^T) — javni parametar za brzo pečaćenje

    struct Bid {
        CG.Form u;        // brava: u = g^r (r zna samo ponuđač, pa ni on posle)
        bytes32 ct;       // šifrat iznosa (32B)
        address bidder;
        bytes32 name;     // ime za prikaz (UTF-8, do 32B)
        bool opened;
        uint256 amount;   // wei, upisuje ga UGOVOR posle validnog otvaranja
    }

    Bid[] public bids;
    bool public closed;
    bool public finalized;
    uint256 public winningBid;
    address public winner;

    event BidPlaced(uint256 indexed id, address indexed bidder);
    event BidOpened(uint256 indexed id, uint256 amount);
    event Finalized(address winner, uint256 amount);

    constructor(
        int256 _D, uint256 _T, bytes32 _salt,
        CG.Form memory _g, CG.Form memory _h, uint256 _deadline
    ) {
        D = _D;
        T = _T;
        salt = _salt;
        g = _g;
        h = _h;
        deadline = _deadline;
        auctioneer = msg.sender;
    }

    function bidCount() external view returns (uint256) { return bids.length; }

    /// @notice zapečaćena ponuda — trenutno; sadržaj ne zna niko, ni ugovor
    function placeBid(CG.Form calldata u, bytes32 ct, bytes32 name)
        external returns (uint256 id)
    {
        require(!closed, "bidding closed");
        id = bids.length;
        bids.push(Bid(u, ct, msg.sender, name, false, 0));
        emit BidPlaced(id, msg.sender);
    }

    /// @notice pre roka sme samo aukcionar; POSLE roka bilo ko — aukcija ne može
    ///         da ostane zaglavljena ako aukcionar nestane
    function closeBidding() external {
        require(msg.sender == auctioneer || block.timestamp >= deadline, "not yet");
        closed = true;
    }

    /// @notice bilo ko podnosi otvaranje; ugovor verifikuje dokaz pa
    ///         dešifruje iznos SAM — bez poverenja u podnosioca
    function openBid(uint256 id, CG.Form calldata w, CG.Form calldata pi) external {
        Bid storage b = bids[id];
        require(closed, "not closed");
        require(!b.opened, "already opened");
        require(verify(b.u, w, pi), "invalid proof");
        // ključ izvodljiv tek iz w = u^(2^T): sha256(w || bidder || salt)
        bytes32 key = sha256(abi.encodePacked(w.a, w.b, w.c, b.bidder, salt));
        bytes32 pad = sha256(abi.encodePacked(key, uint64(0)));
        b.amount = uint256(b.ct ^ pad);
        b.opened = true;
        emit BidOpened(id, b.amount);
    }

    /// @notice pobednika bira ugovor, tek kad su SVE koverte otvorene
    function finalize() external {
        require(closed && !finalized, "state");
        uint256 best;
        uint256 bestId;
        for (uint256 i = 0; i < bids.length; i++) {
            require(bids[i].opened, "bid not opened");
            if (bids[i].amount > best) { best = bids[i].amount; bestId = i; }
        }
        finalized = true;
        winningBid = best;
        winner = bids[bestId].bidder;
        emit Finalized(winner, best);
    }

    // ---------------- Wesolowski verifikacija (kao TimelockVault) ----------------

    function verify(CG.Form memory u, CG.Form memory w, CG.Form memory pi)
        public view returns (bool)
    {
        uint256 l = fiatShamirPrime(u, w);
        uint256 r = powmod(2, T, l);
        CG.Form memory lhs = CG.shamir(pi, l, u, r, D);
        return CG.eq(lhs, CG.reduce(w));
    }

    function fiatShamirPrime(CG.Form memory u, CG.Form memory w)
        public view returns (uint256)
    {
        bytes32 seed = sha256(abi.encodePacked(u.a, u.b, u.c, w.a, w.b, w.c, T, D));
        for (uint256 counter = 0;; counter++) {
            uint256 cand = uint256(sha256(abi.encodePacked(seed, counter))) >> 176;
            cand |= (1 << 79) | 1;
            if (millerRabin(cand)) return cand;
        }
    }

    function millerRabin(uint256 n) internal pure returns (bool) {
        uint256[12] memory bases =
            [uint256(2), 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37];
        for (uint256 i = 0; i < 12; i++) {
            if (n % bases[i] == 0) return n == bases[i];
        }
        uint256 d = n - 1;
        uint256 s = 0;
        while (d & 1 == 0) { d >>= 1; s++; }
        for (uint256 i = 0; i < 12; i++) {
            uint256 x = powmod(bases[i], d, n);
            if (x == 1 || x == n - 1) continue;
            bool passed = false;
            for (uint256 j = 0; j + 1 < s; j++) {
                x = mulmod(x, x, n);
                if (x == n - 1) { passed = true; break; }
            }
            if (!passed) return false;
        }
        return true;
    }

    function powmod(uint256 base, uint256 e, uint256 m)
        internal pure returns (uint256 r)
    {
        r = 1 % m;
        base %= m;
        while (e > 0) {
            if (e & 1 == 1) r = mulmod(r, base, m);
            base = mulmod(base, base, m);
            e >>= 1;
        }
    }
}
