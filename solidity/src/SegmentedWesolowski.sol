// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibBigInt as B} from "./LibBigInt.sol";
import {LibClassGroupBig as CG} from "./LibClassGroupBig.sol";
import {LibWesolowskiBig as W} from "./LibWesolowskiBig.sol";

/// @title Nastavljiva (segmentirana) Wesolowski verifikacija.
/// @notice Checkpoint oko joint-NAF petlje: NAF maske + pozicija bita +
///         akumulator + dva unakrsna proizvoda tabele. Ulazne forme se NE
///         skladiste — svaki step ih ponovo prima i vezuje keccak-om za job.
///         Sa nBits=10 svaki segment staje u L1 tx cap (16,77M).
contract SegmentedWesolowski {
    struct Job {
        bool started;
        bool done;
        bool valid;
        uint16 pos;        // sledeca NAF pozicija za obradu
        uint256 P1; uint256 N1; uint256 P2; uint256 N2;
        bytes32 bind;      // keccak(abi.encode(u, pi, T)) — vezuje ulaze
        bytes32 wRedHash;  // keccak(abi.encode(reduce(w)))
        bytes acc;         // abi.encode(Form) — akumulator
        bytes cross;       // abi.encode(pi*u, pi*u^{-1})
    }
    mapping(bytes32 => Job) internal jobs;

    function status(bytes32 id) external view returns (bool started, bool done, bool valid, uint16 pos) {
        Job storage j = jobs[id];
        return (j.started, j.done, j.valid, j.pos);
    }

    function jobId(CG.Form memory u, CG.Form memory w, CG.Form memory pi, uint256 T)
        public pure returns (bytes32)
    {
        return keccak256(abi.encode(u, w, pi, T));
    }

    function start(
        CG.Form memory u, CG.Form memory w, CG.Form memory pi,
        uint256 T, B.Int memory D
    ) external returns (bytes32 id) {
        id = jobId(u, w, pi, T);
        Job storage j = jobs[id];
        require(!j.started, "job exists");
        uint256 l = W.fiatShamirPrime(u, w, T, D);
        uint256 r = W.powmod(2, T, l);
        (uint256 P1, uint256 N1) = CG._naf(l);
        (uint256 P2, uint256 N2) = CG._naf(r);
        CG.Form memory t12 = CG.nucompCompact(pi, u, D);
        CG.Form memory t1m2 = CG.nucompCompact(pi, CG.inverse(u), D);
        uint256 all = P1 | N1 | P2 | N2;
        uint256 top = 255;
        while (all & (uint256(1) << top) == 0) top--;
        // inicijalni akumulator = tabelarni unos na najvisoj poziciji
        CG.Form memory acc = _tabEntry(pi, u, t12, t1m2, P1, N1, P2, N2, uint256(1) << top);
        j.started = true;
        j.pos = uint16(top); // sledece se obradjuje top-1
        j.P1 = P1; j.N1 = N1; j.P2 = P2; j.N2 = N2;
        j.bind = keccak256(abi.encode(u, pi, T));
        j.wRedHash = keccak256(abi.encode(CG.reduce(w)));
        j.acc = abi.encode(acc);
        j.cross = abi.encode(t12, t1m2);
    }

    struct Ctx {
        CG.Form u; CG.Form pi; CG.Form t12; CG.Form t1m2;
        uint256 P1; uint256 N1; uint256 P2; uint256 N2;
    }

    /// @notice izvrsi do nBits NAF pozicija; poslednji poziv postavlja done/valid
    function step(
        bytes32 id, CG.Form memory u, CG.Form memory pi,
        uint256 T, B.Int memory D, uint256 nBits
    ) external {
        Job storage j = jobs[id];
        require(j.started && !j.done, "bad job");
        require(keccak256(abi.encode(u, pi, T)) == j.bind, "inputs mismatch");
        Ctx memory c;
        c.u = u; c.pi = pi;
        (c.t12, c.t1m2) = abi.decode(j.cross, (CG.Form, CG.Form));
        (c.P1, c.N1, c.P2, c.N2) = (j.P1, j.N1, j.P2, j.N2);
        (bytes memory accEnc, uint256 pos) = _run(c, j.acc, D, j.pos, nBits);
        j.pos = uint16(pos);
        if (pos == 0) {
            j.done = true;
            j.valid = keccak256(accEnc) == j.wRedHash;
            delete j.acc;
            delete j.cross;
        } else {
            j.acc = accEnc;
        }
    }

    function _run(Ctx memory c, bytes memory accEnc, B.Int memory D, uint256 pos, uint256 nBits)
        private pure returns (bytes memory, uint256)
    {
        CG.Form memory acc = abi.decode(accEnc, (CG.Form));
        uint256 all = c.P1 | c.N1 | c.P2 | c.N2;
        while (nBits > 0 && pos > 0) {
            pos--;
            nBits--;
            acc = CG.squareCompact(acc, D);
            uint256 bit = uint256(1) << pos;
            if (all & bit != 0) {
                acc = CG.nucompCompact(acc, _tab(c, bit), D);
            }
        }
        return (abi.encode(acc), pos);
    }

    function _tab(Ctx memory c, uint256 bit) private pure returns (CG.Form memory) {
        return _tabEntry(c.pi, c.u, c.t12, c.t1m2, c.P1, c.N1, c.P2, c.N2, bit);
    }

    function _tabEntry(
        CG.Form memory f1, CG.Form memory f2,
        CG.Form memory t12, CG.Form memory t1m2,
        uint256 P1, uint256 N1, uint256 P2, uint256 N2, uint256 bit
    ) private pure returns (CG.Form memory) {
        uint256 d1 = P1 & bit != 0 ? 2 : (N1 & bit != 0 ? 0 : 1);
        uint256 d2 = P2 & bit != 0 ? 2 : (N2 & bit != 0 ? 0 : 1);
        uint256 idx = d1 * 3 + d2;
        if (idx == 8) return t12;
        if (idx == 7) return f1;
        if (idx == 6) return t1m2;
        if (idx == 5) return f2;
        if (idx == 3) return CG.inverse(f2);
        if (idx == 2) return CG.inverse(t1m2);
        if (idx == 1) return CG.inverse(f1);
        if (idx == 0) return CG.inverse(t12);
        revert("zero digit"); // idx == 4 se nikad ne trazi
    }
}
