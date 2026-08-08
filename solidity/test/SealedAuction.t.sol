// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {LibClassGroup as CG} from "../src/LibClassGroup.sol";
import {SealedAuction} from "../src/SealedAuction.sol";

int256 constant VD = -64770550419156998147359728223;

// AUTO-GENERISANO iz gen_auction_vectors.js
// AUTO-GENERISANO iz gen_auction_vectors.js
uint256 constant VT = 600;
bytes32 constant VSALT = 0xce58ead8adbcf8a2d332dc040d56fb90281a61790f1dd23f4b954e855a64ba50;

library AVec {
    function G() internal pure returns (CG.Form memory) {
        return CG.Form(int256(85588352752381), int256(54312620317113), int256(197808489610708));
    }
    function H() internal pure returns (CG.Form memory) {
        return CG.Form(int256(120370258359443), int256(-101759355838989), int256(156030064950902));
    }
    address constant B0 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    uint256 constant AMT0 = 3250000000000000000;
    bytes32 constant CT0 = bytes32(0xe651a81cca8d1880ceb672e2c1a564372a8093a775ffbb691b2c2090c25219d0);
    bytes32 constant NM0 = bytes32(0x416e610000000000000000000000000000000000000000000000000000000000);
    function U0() internal pure returns (CG.Form memory) {
        return CG.Form(int256(76813060225138), int256(14170080096259), int256(211459292855477));
    }
    function W0() internal pure returns (CG.Form memory) {
        return CG.Form(int256(52741932309589), int256(-51531794668603), int256(319603744726022));
    }
    function PI0() internal pure returns (CG.Form memory) {
        return CG.Form(int256(16813214986237), int256(-3136199411003), int256(963236154104534));
    }
    address constant B1 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    uint256 constant AMT1 = 7500000000000000000;
    bytes32 constant CT1 = bytes32(0x1f9cb04f1fb6257cbb99cac8f90619f43263b24237caad90a822b36f1f5edafc);
    bytes32 constant NM1 = bytes32(0x426f726973000000000000000000000000000000000000000000000000000000);
    function U1() internal pure returns (CG.Form memory) {
        return CG.Form(int256(126426330276842), int256(-86754127498021), int256(142962365708923));
    }
    function W1() internal pure returns (CG.Form memory) {
        return CG.Form(int256(35296469673782), int256(-13796961746539), int256(460109092870873));
    }
    function PI1() internal pure returns (CG.Form memory) {
        return CG.Form(int256(29445211903607), int256(-2713598338109), int256(549986821687318));
    }
    address constant B2 = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
    uint256 constant AMT2 = 5000000000000000000;
    bytes32 constant CT2 = bytes32(0xc0b2955bb77fefaa081676abe5ad93c405b19746cdb8f5e33eda49723c3b5957);
    bytes32 constant NM2 = bytes32(0x5665726100000000000000000000000000000000000000000000000000000000);
    function U2() internal pure returns (CG.Form memory) {
        return CG.Form(int256(103618230063932), int256(-26216523237793), int256(157930357595974));
    }
    function W2() internal pure returns (CG.Form memory) {
        return CG.Form(int256(88933376561209), int256(-44117006964549), int256(187547305922734));
    }
    function PI2() internal pure returns (CG.Form memory) {
        return CG.Form(int256(81973485881368), int256(17564647434687), int256(198475966219261));
    }
}


contract SealedAuctionTest is Test {
    SealedAuction a;

    function setUp() public {
        a = new SealedAuction(VD, VT, VSALT, AVec.G(), AVec.H(), block.timestamp + 1 hours);
    }

    function _place() internal {
        vm.prank(AVec.B0); a.placeBid(AVec.U0(), AVec.CT0, AVec.NM0);
        vm.prank(AVec.B1); a.placeBid(AVec.U1(), AVec.CT1, AVec.NM1);
        vm.prank(AVec.B2); a.placeBid(AVec.U2(), AVec.CT2, AVec.NM2);
        a.closeBidding();
    }

    function test_FullAuctionOnChain() public {
        _place();
        assertEq(a.bidCount(), 3);

        // otvaranje pre zatvaranja / lazno otvaranje ne prolazi
        vm.expectRevert("invalid proof");
        a.openBid(0, AVec.W1(), AVec.PI0()); // tudje w uz tudji dokaz

        // posteno otvaranje: UGOVOR verifikuje i UGOVOR desifruje iznos
        a.openBid(0, AVec.W0(), AVec.PI0());
        a.openBid(1, AVec.W1(), AVec.PI1());

        // finalize pre svih otvaranja pada
        vm.expectRevert("bid not opened");
        a.finalize();

        a.openBid(2, AVec.W2(), AVec.PI2());

        (, , , , bool op0, uint256 am0) = a.bids(0);
        (, , , , , uint256 am1) = a.bids(1);
        (, , , , , uint256 am2) = a.bids(2);
        assertTrue(op0);
        assertEq(am0, AVec.AMT0); // 3.25 ETH — desifrovao ugovor, ne mi
        assertEq(am1, AVec.AMT1); // 7.5
        assertEq(am2, AVec.AMT2); // 5

        a.finalize();
        assertEq(a.winner(), AVec.B1);        // pobednik: 7.5 ETH
        assertEq(a.winningBid(), AVec.AMT1);
    }

    function test_CannotBidAfterClose() public {
        _place();
        vm.prank(AVec.B0);
        vm.expectRevert("bidding closed");
        a.placeBid(AVec.U0(), AVec.CT0, AVec.NM0);
    }

    function test_CannotOpenBeforeClose() public {
        vm.prank(AVec.B0); a.placeBid(AVec.U0(), AVec.CT0, AVec.NM0);
        vm.expectRevert("not closed");
        a.openBid(0, AVec.W0(), AVec.PI0());
    }

    function test_CannotDoubleOpen() public {
        _place();
        a.openBid(0, AVec.W0(), AVec.PI0());
        vm.expectRevert("already opened");
        a.openBid(0, AVec.W0(), AVec.PI0());
    }

    function test_GasOpenBid() public {
        _place();
        uint256 g0 = gasleft();
        a.openBid(1, AVec.W1(), AVec.PI1());
        console2.log("openBid (verify + on-chain decrypt) gas:", g0 - gasleft());
    }

    function test_AnyoneCanCloseAfterDeadline() public {
        vm.prank(AVec.B0); a.placeBid(AVec.U0(), AVec.CT0, AVec.NM0);
        // pre roka stranac ne moze
        vm.prank(AVec.B1);
        vm.expectRevert("not yet");
        a.closeBidding();
        // posle roka moze bilo ko
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(AVec.B1);
        a.closeBidding();
        assertTrue(a.closed());
    }

    function test_OpenAndFinalizeArePermissionless() public {
        _place();
        // otvaranje podnosi PONUDJAC (ne aukcionar) — ugovor verifikuje, ne veruje
        vm.prank(AVec.B2);
        a.openBid(0, AVec.W0(), AVec.PI0());
        vm.prank(AVec.B0);
        a.openBid(1, AVec.W1(), AVec.PI1());
        vm.prank(AVec.B1);
        a.openBid(2, AVec.W2(), AVec.PI2());
        // i finalize sme bilo ko
        vm.prank(AVec.B2);
        a.finalize();
        assertEq(a.winner(), AVec.B1);
    }
}
