// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {console2} from "forge-std/Test.sol";
import {LibBigInt as B} from "../src/LibBigInt.sol";
import {LibClassGroupBig as CG} from "../src/LibClassGroupBig.sol";
import {SegmentedWesolowski} from "../src/SegmentedWesolowski.sol";
import {WesolowskiE2E} from "./WesolowskiE2E.t.sol";

/// Segmentirana verifikacija nad ISTIM pravim fixture-om (nasledjuje ga).
contract SegmentedWesolowskiTest is WesolowskiE2E {
    function test_SegmentedRealProof() public {
        SegmentedWesolowski v = new SegmentedWesolowski();
        uint256 g0 = gasleft();
        bytes32 id = v.start(U_(), Wf_(), PI_(), T_, D_());
        console2.log("SEG start gas:", g0 - gasleft());
        uint256 steps;
        uint256 maxStep;
        while (true) {
            (, bool done, bool valid, ) = v.status(id);
            if (done) { require(valid, "segmented rejected real proof"); break; }
            g0 = gasleft();
            v.step(id, U_(), PI_(), T_, D_(), 10);
            uint256 used = g0 - gasleft();
            if (used > maxStep) maxStep = used;
            steps++;
            require(steps < 30, "runaway");
        }
        console2.log("SEG steps / max step gas:", steps, maxStep);
        require(maxStep < 16_770_000, "segment exceeds L1 tx cap");
    }

    function test_SegmentedTamperedFails() public {
        SegmentedWesolowski v = new SegmentedWesolowski();
        bytes32 id = v.start(U_(), Wf_(), U_(), T_, D_()); // pi = u
        for (uint256 i = 0; i < 30; i++) {
            (, bool done, bool valid, ) = v.status(id);
            if (done) { require(!valid, "accepted forged proof"); return; }
            v.step(id, U_(), U_(), T_, D_(), 16);
        }
        revert("did not finish");
    }

    function test_SegmentedBindsInputs() public {
        SegmentedWesolowski v = new SegmentedWesolowski();
        bytes32 id = v.start(U_(), Wf_(), PI_(), T_, D_());
        vm.expectRevert(bytes("inputs mismatch"));
        v.step(id, U_(), U_(), T_, D_(), 4); // podmetnut pi u step-u
    }
}
