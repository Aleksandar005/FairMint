// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test, console2} from "forge-std/Test.sol";
import {LibBigInt as B} from "../src/LibBigInt.sol";
import {LibClassGroupBig as CG} from "../src/LibClassGroupBig.sol";

contract LibClassGroupBigTest is Test {
    function _mk(bool neg, uint256[] memory limbs) internal pure returns (B.Int memory z) {
        z.neg = neg; z.limbs = limbs;
    }

    // AUTO-GENERISANO (1024-bit)
    function D() internal pure returns (B.Int memory) {
        uint256[] memory L = new uint256[](4);
        L[0] = 92325566918696944234767304319137366847153991194884342244635223870271662148071;
        L[1] = 32174161634477040966241220395732563175035854139341062605219251733148279181470;
        L[2] = 79158291431234642836385543944599643540406777840668402635541297532275410114020;
        L[3] = 114771056843020146160412573772694622931096687497452774663550018905897036661487;
        return _mk(true, L);
    }
    function G_a() internal pure returns (B.Int memory) {
        uint256[] memory L = new uint256[](1);
        L[0] = 3;
        return _mk(false, L);
    }
    function G_b() internal pure returns (B.Int memory) {
        uint256[] memory L = new uint256[](1);
        L[0] = 1;
        return _mk(false, L);
    }
    function G_c() internal pure returns (B.Int memory) {
        uint256[] memory L = new uint256[](4);
        L[0] = 65589841861882843064682767864272067830564491599060643873448393993145869998974;
        L[1] = 79875906294417217029567425038769652166766310955372131243406660316371109691746;
        L[2] = 35544546595265269092258208247555280591684727653132507896159504129667899919485;
        L[3] = 9564254736918345513367714481057885244258057291454397888629168242158086388457;
        return _mk(false, L);
    }
    function G() internal pure returns (CG.Form memory) {
        return CG.Form(G_a(), G_b(), G_c());
    }
    function G2_a() internal pure returns (B.Int memory) {
        uint256[] memory L = new uint256[](1);
        L[0] = 9;
        return _mk(false, L);
    }
    function G2_b() internal pure returns (B.Int memory) {
        uint256[] memory L = new uint256[](1);
        L[0] = 1;
        return _mk(false, L);
    }
    function G2_c() internal pure returns (B.Int memory) {
        uint256[] memory L = new uint256[](4);
        L[0] = 60460643699733012829417917624319991894611492088233735970968659333686333212970;
        L[1] = 103820028256349869292236465018715155957768760095551086440773942777399122990539;
        L[2] = 11848182198421756364086069415851760197228242551044169298719834709889299973161;
        L[3] = 3188084912306115171122571493685961748086019097151465962876389414052695462819;
        return _mk(false, L);
    }
    function G2() internal pure returns (CG.Form memory) {
        return CG.Form(G2_a(), G2_b(), G2_c());
    }
    function G3_a() internal pure returns (B.Int memory) {
        uint256[] memory L = new uint256[](1);
        L[0] = 27;
        return _mk(false, L);
    }
    function G3_b() internal pure returns (B.Int memory) {
        uint256[] memory L = new uint256[](1);
        L[0] = 17;
        return _mk(true, L);
    }
    function G3_c() internal pure returns (B.Int memory) {
        uint256[] memory L = new uint256[](4);
        L[0] = 97348274058121801225519962547231935867050487139838288016627942449837530830950;
        L[1] = 73204039164555354905269150009134354603679581587063883493410508928437417543491;
        L[2] = 42546757145245983929219018141513222683499409072228244446059139572600809871032;
        L[3] = 1062694970768705057040857164561987249362006365717155320958796471350898487606;
        return _mk(false, L);
    }
    function G3() internal pure returns (CG.Form memory) {
        return CG.Form(G3_a(), G3_b(), G3_c());
    }
    function G5_a() internal pure returns (B.Int memory) {
        uint256[] memory L = new uint256[](1);
        L[0] = 243;
        return _mk(false, L);
    }
    function G5_b() internal pure returns (B.Int memory) {
        uint256[] memory L = new uint256[](1);
        L[0] = 145;
        return _mk(false, L);
    }
    function G5_c() internal pure returns (B.Int memory) {
        uint256[] memory L = new uint256[](4);
        L[0] = 23682262588381999627676771950657760413368941311719872450676169606416740052342;
        L[1] = 98194295980640969207807338341105523286285497138505314641068177442647702780338;
        L[2] = 81922143618793684052293880910404518867013257451785736520311627068897731967849;
        L[3] = 118077218974300561893428573840220805484667373968572813439866274594544276400;
        return _mk(false, L);
    }
    function G5() internal pure returns (CG.Form memory) {
        return CG.Form(G5_a(), G5_b(), G5_c());
    }
    function W32_a() internal pure returns (B.Int memory) {
        uint256[] memory L = new uint256[](2);
        L[0] = 47743963917901201690785045616193027003081498744541868659238953067988809385644;
        L[1] = 34741994175786615383929904176673763816437266779533338658617299959399711649958;
        return _mk(false, L);
    }
    function W32_b() internal pure returns (B.Int memory) {
        uint256[] memory L = new uint256[](2);
        L[0] = 53678280258378673037327334469783930994075074432179681413964045330364641836893;
        L[1] = 12212809244767247580253663009929815376203227930772970745110685190818001457943;
        return _mk(true, L);
    }
    function W32_c() internal pure returns (B.Int memory) {
        uint256[] memory L = new uint256[](2);
        L[0] = 44173393688501350837071775469331542744220049488503867163708388550417822374993;
        L[1] = 96703812520664524214026624870987477108125462821092897030089899449708434699845;
        return _mk(false, L);
    }
    function W32() internal pure returns (CG.Form memory) {
        return CG.Form(W32_a(), W32_b(), W32_c());
    }


    function W4_a() internal pure returns (B.Int memory) {
        uint256[] memory L = new uint256[](1);
        L[0] = 43046721;
        return _mk(false, L);
    }
    function W4_b() internal pure returns (B.Int memory) {
        uint256[] memory L = new uint256[](1);
        L[0] = 16003349;
        return _mk(true, L);
    }
    function W4_c() internal pure returns (B.Int memory) {
        uint256[] memory L = new uint256[](4);
        L[0] = 25387235663887687039891734906740618304987193141120795647687760907342177526632;
        L[1] = 58317222531466068564942902656316224268367370079152301236955344096210651802113;
        L[2] = 260615046600115381364818743271792307205137355723646069220615816594231476280;
        L[3] = 666549357168343589749917152648482929344935979545647476050208440416966;
        return _mk(false, L);
    }
    function W4() internal pure returns (CG.Form memory) {
        return CG.Form(W4_a(), W4_b(), W4_c());
    }

    function test_DiscriminantHolds() public pure {
        CG.Form memory g = G();
        B.Int memory bb = B.mul(g.b, g.b);
        B.Int memory ac4 = B.mul(B.mul(B.fromUint(4), g.a), g.c);
        assertTrue(B.cmp(B.sub(bb, ac4), D()) == 0, "b^2-4ac != D");
    }

    function test_CompositionMatchesPython() public pure {
        B.Int memory d = D();
        CG.Form memory g = G();
        CG.Form memory g2 = CG.compose(g, g, d);
        assertTrue(CG.eq(g2, G2()), "g^2");
        CG.Form memory g3 = CG.compose(g2, g, d);
        assertTrue(CG.eq(g3, G3()), "g^3");
        CG.Form memory g5 = CG.compose(g2, g3, d);
        assertTrue(CG.eq(g5, G5()), "g^5");
    }

    function test_PowMatchesPython() public view {
        B.Int memory d = D();
        uint256 gas0 = gasleft();
        CG.Form memory w = CG.pow(G(), 1 << 4, d); // 4 squarings, keeps gas bounded
        console2.log("pow g^(2^4) [4 sq] gas:", gas0 - gasleft());
        assertTrue(CG.eq(w, W4()), "g^(2^4)");
    }

    function test_GasSingleComposition() public view {
        B.Int memory d = D();
        CG.Form memory g = G();
        uint256 gas0 = gasleft();
        CG.compose(g, g, d);
        console2.log("SINGLE composition @1024-bit gas:", gas0 - gasleft());
    }
}
