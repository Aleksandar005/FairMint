// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {LibClassGroup} from "../src/LibClassGroup.sol";
import {TimelockVault} from "../src/TimelockVault.sol";

int256 constant D = -64770550419156998147359728223;
uint256 constant T = 4096;

/// Vektori generisani Python referencom (gen_vectors.py):
/// u = g^r, w = u^(2^T) == h^r, pi = Wesolowski dokaz.
library Vec {
    function G() internal pure returns (LibClassGroup.Form memory) {
        return LibClassGroup.Form(int256(11), int256(3), int256(1472057964071749957894539278));
    }

    function H() internal pure returns (LibClassGroup.Form memory) {
        return LibClassGroup.Form(int256(83052130260413), int256(-74382244990149), int256(211623917919062));
    }

    function U() internal pure returns (LibClassGroup.Form memory) {
        return LibClassGroup.Form(int256(89542685153864), int256(-31836632694465), int256(183666933506183));
    }

    function W() internal pure returns (LibClassGroup.Form memory) {
        return LibClassGroup.Form(int256(100323020502629), int256(42736611964295), int256(165956348023828));
    }

    function PI() internal pure returns (LibClassGroup.Form memory) {
        return LibClassGroup.Form(int256(38732689378156), int256(27232993451137), int256(422848163936258));
    }

    function W_BAD() internal pure returns (LibClassGroup.Form memory) {
        return LibClassGroup.Form(int256(107941753210118), int256(97493978178993), int256(172027097928776));
    }
}

contract TimelockVaultTest is Test {
    TimelockVault vault;

    function setUp() public {
        vault = new TimelockVault(D, T);
    }

    // ---------- aritmetika se poklapa sa Python referencom ----------

    function test_ArithmeticMatchesPython() public pure {
        // diskriminanta se čuva
        LibClassGroup.Form memory g = Vec.G();
        assertEq(g.b * g.b - 4 * g.a * g.c, D);

        // 12 uzastopnih kvadriranja == pow(g, 4096) — mini timelock
        LibClassGroup.Form memory x = g;
        for (uint256 i = 0; i < 12; i++) x = LibClassGroup.square(x);
        assertTrue(LibClassGroup.eq(x, LibClassGroup.pow(g, 4096, D)));

        // grupovni zakoni
        LibClassGroup.Form memory y = LibClassGroup.pow(g, 12345, D);
        LibClassGroup.Form memory z = LibClassGroup.pow(g, 67890, D);
        assertTrue(
            LibClassGroup.eq(
                LibClassGroup.compose(LibClassGroup.compose(x, y), z),
                LibClassGroup.compose(x, LibClassGroup.compose(y, z))
            )
        );
        assertTrue(LibClassGroup.eq(LibClassGroup.compose(x, LibClassGroup.identity(D)), x));
    }

    // ---------- Wesolowski verifikacija ----------

    function test_ValidProofAccepted() public view {
        assertTrue(vault.verify(Vec.U(), Vec.W(), Vec.PI()));
    }

    function test_ForgedSolutionRejected() public view {
        assertFalse(vault.verify(Vec.U(), Vec.W_BAD(), Vec.PI()));
    }

    function test_WrongProofRejected() public view {
        assertFalse(vault.verify(Vec.U(), Vec.W(), Vec.G()));
    }

    // ---------- ceo tok: zaključaj ETH → otključaj dokazom ----------

    function test_VaultFlow() public {
        address marko = makeAddr("marko");

        // LOCK: 1 ETH iza puzzle-a u = g^r ("posalji 1 ETH Marku, ne pre T")
        uint256 id = vault.lock{value: 1 ether}(Vec.U(), marko);
        assertEq(address(vault).balance, 1 ether);
        assertEq(marko.balance, 0);

        // niko ne moze sa pogresnim resenjem
        vm.expectRevert("invalid proof");
        vault.claim(id, Vec.W_BAD(), Vec.PI());

        // CLAIM: solver (bilo ko) prilaze (w, pi) — off-chain je odradio T kvadriranja
        vault.claim(id, Vec.W(), Vec.PI());
        assertEq(marko.balance, 1 ether);

        // ne moze dvaput
        vm.expectRevert("already claimed");
        vault.claim(id, Vec.W(), Vec.PI());
    }

    // ---------- merenje gasa (poenta projekta!) ----------

    function test_GasReport() public view {
        uint256 g0 = gasleft();
        vault.verifyNaive(Vec.U(), Vec.W(), Vec.PI());
        uint256 naive = g0 - gasleft();

        g0 = gasleft();
        vault.verify(Vec.U(), Vec.W(), Vec.PI());
        uint256 opt = g0 - gasleft();

        console2.log("verifyNaive() gas:", naive);
        console2.log("verify() [Shamir + unchecked] gas:", opt);
        console2.log("usteda (%):", 100 - (opt * 100) / naive);
        console2.log("(Riggs/RSA referenca ~2.5M; ovo je 96-bitni demo)");
    }

    function test_OptimizedMatchesNaive() public view {
        assertTrue(vault.verify(Vec.U(), Vec.W(), Vec.PI()));
        assertTrue(vault.verifyNaive(Vec.U(), Vec.W(), Vec.PI()));
        assertFalse(vault.verify(Vec.U(), Vec.W_BAD(), Vec.PI()));
        assertFalse(vault.verifyNaive(Vec.U(), Vec.W_BAD(), Vec.PI()));
    }
}
