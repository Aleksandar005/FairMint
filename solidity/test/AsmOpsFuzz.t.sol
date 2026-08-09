// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
import {LibBigInt as B} from "../src/LibBigInt.sol";

/// Diferencijalni fuzz asemblerskih primitiva protiv referentnih implementacija.
contract AsmOpsFuzz is Test {
    function _mk(uint256 seed, uint256 nl, bool neg) private pure returns (B.Int memory z) {
        uint256[] memory L = new uint256[](nl);
        for (uint256 i = 0; i < nl; i++) L[i] = uint256(keccak256(abi.encode(seed, i)));
        if (seed % 3 == 0) L[nl - 1] = 0;       // trailing nule
        if (seed % 5 == 0) L[0] = 0;
        uint256 any;
        for (uint256 i = 0; i < nl; i++) any |= L[i];
        z.limbs = L; z.neg = neg && any != 0; // kanonicki: nikad "-0"
    }
    function testFuzz_MulMatchesRef(uint256 sa, uint256 sb, uint8 la, uint8 lb, bool na, bool nb) public pure {
        B.Int memory a = _mk(sa, 1 + la % 5, na);
        B.Int memory b = _mk(sb, 1 + lb % 5, nb);
        require(B.cmp(B.mul(a, b), B._mulRef(a, b)) == 0, "mul != ref");
        require(B.cmp(B.mul(a, B.fromUint(0)), B.fromUint(0)) == 0, "mul x0");
    }
    function testFuzz_AddSubMatchRef(uint256 sa, uint256 sb, uint8 la, uint8 lb, bool na, bool nb) public pure {
        B.Int memory a = _mk(sa, 1 + la % 5, na);
        B.Int memory b = _mk(sb, 1 + lb % 5, nb);
        // add/sub idu kroz _uadd/_usub; referentni rezultat preko mulRef-free staza:
        // uporedi (a+b)-b == a i (a-b)+b == a, plus komutativnost sabiranja
        require(B.cmp(B.sub(B.add(a, b), b), a) == 0, "(a+b)-b != a");
        require(B.cmp(B.add(B.sub(a, b), b), a) == 0, "(a-b)+b != a");
        require(B.cmp(B.add(a, b), B.add(b, a)) == 0, "add not comm");
    }
    function test_CloneAndEdges() public pure {
        B.Int memory a = _mk(7, 4, true);
        B.Int memory c = B.clone(a);
        require(B.cmp(a, c) == 0, "clone");
        require(B.cmp(B.mul(B.fromUint(0), a), B.fromUint(0)) == 0, "0*a");
    }

    /// _fms(wa,a,wb,b) mora biti identican sub(mul(wa,a), mul(wb,b))
    function testFuzz_FmsMatchesRef(uint256 sa, uint256 sb, uint128 wa, uint128 wb, uint8 la, uint8 lb, bool na, bool nb) public pure {
        B.Int memory a = _mk(sa, 1 + la % 5, na);
        B.Int memory b = _mk(sb, 1 + lb % 5, nb);
        B.Int memory got = B._fms(wa, a, wb, b);
        B.Int memory want = B.sub(B._mulRef(B.fromUint(wa), a), B._mulRef(B.fromUint(wb), b));
        require(B.cmp(got, want) == 0, "fms != ref");
        // ivice: nulti koeficijenti i jednake magnitude
        require(B.cmp(B._fms(0, a, 0, b), B.fromUint(0)) == 0, "fms 0,0");
        require(B.cmp(B._fms(wa, a, wa, a), B.fromUint(0)) == 0, "fms x-x");
    }

    /// NAF maske: e == P - N, P & N == 0, bez susednih ne-nula cifara
    function testFuzz_NafReconstruct(uint256 e) public pure {
        e >>= 8; // do 248 bita, da e+1 u algoritmu ne prekoraci
        (uint256 P, uint256 N) = (0, 0);
        {
            import0(); // no-op placeholder
        }
        (P, N) = CGN.nafOf(e);
        require(P & N == 0, "P&N != 0");
        unchecked { require(P - N == e, "P-N != e"); }
        uint256 nz = P | N;
        require(nz & (nz << 1) == 0, "adjacent nonzero");
    }
    function import0() private pure {}
}

import {LibClassGroupBig as CGN0} from "../src/LibClassGroupBig.sol";
library CGN {
    function nafOf(uint256 e) internal pure returns (uint256, uint256) {
        return CGN0._naf(e);
    }
}
