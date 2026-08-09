// SPDX-License-Identifier: MIT
// AUTO-GENERISANO: python3 gen_wesolowski_fixture.py (T=4096, seed petnica-2026)
pragma solidity ^0.8.24;
import {Test, console2} from "forge-std/Test.sol";
import {LibBigInt as B} from "../src/LibBigInt.sol";
import {LibClassGroupBig as CG} from "../src/LibClassGroupBig.sol";
import {LibWesolowskiBig as W} from "../src/LibWesolowskiBig.sol";

contract WesolowskiE2E is Test {
    uint256 constant T_ = 4096;
    uint256 constant L_EXPECTED = 1162838376177928872738497;
    function D_() internal pure returns (B.Int memory z){
        uint256[] memory L=new uint256[](4);
        L[0]=60851157163359773000748138998255589057179020877401284953912450204635190909959;
        L[1]=58412528888617349947380374178250509351154879092605639648286064328478918373429;
        L[2]=103148164859766022864879456766396113615664520768862498401703524904534343226414;
        L[3]=72255451234169613298441781006176033194279977139139628387384232831823629386880;
        z.limbs=L; z.neg=true;
    }
    function U__a() internal pure returns (B.Int memory z){
        uint256[] memory L=new uint256[](2);
        L[0]=22720381616689874720907366993518778212944942984003041603819869378224965290678;
        L[1]=34323569876064913639172986265933501983045753964819356874525189676592301814830;
        z.limbs=L; z.neg=false;
    }
    function U__b() internal pure returns (B.Int memory z){
        uint256[] memory L=new uint256[](2);
        L[0]=45410693423222112824127040621515552919526009786939088448212659844511325927311;
        L[1]=17254159760326816174229022288568223218665530856568220131476542734265903018328;
        z.limbs=L; z.neg=true;
    }
    function U__c() internal pure returns (B.Int memory z){
        uint256[] memory L=new uint256[](2);
        L[0]=55910926602757780906814342222754711565249915699811605464337175520670258626247;
        L[1]=63107623402150422069354973797275968262087481133495729080627423376058247145967;
        z.limbs=L; z.neg=false;
    }
    function U_() internal pure returns (CG.Form memory){ return CG.Form(U__a(),U__b(),U__c()); }
    function Wf__a() internal pure returns (B.Int memory z){
        uint256[] memory L=new uint256[](2);
        L[0]=8878940925966719692773587727027159556495058433805572064877919445093162358026;
        L[1]=34972843820883983481156764056987517229866114668570781630452866055256612576435;
        z.limbs=L; z.neg=false;
    }
    function Wf__b() internal pure returns (B.Int memory z){
        uint256[] memory L=new uint256[](2);
        L[0]=58266785543457761871515385368028811555282520706742769664903948635142980130025;
        L[1]=25142801399075614380971663219548592764347416293691232355968010163699369395503;
        z.limbs=L; z.neg=true;
    }
    function Wf__c() internal pure returns (B.Int memory z){
        uint256[] memory L=new uint256[](2);
        L[0]=71297529903556218626495451507824319371570032907079620340146648178344461480423;
        L[1]=64326840029586559552901009480314348364390977921595264349388502727458073549856;
        z.limbs=L; z.neg=false;
    }
    function Wf_() internal pure returns (CG.Form memory){ return CG.Form(Wf__a(),Wf__b(),Wf__c()); }
    function PI__a() internal pure returns (B.Int memory z){
        uint256[] memory L=new uint256[](2);
        L[0]=92674669121086283354101209300289075336299329362924578024150457419777942692063;
        L[1]=49762363011140483370234807511204347448154317870453898223308820339201620654683;
        z.limbs=L; z.neg=false;
    }
    function PI__b() internal pure returns (B.Int memory z){
        uint256[] memory L=new uint256[](2);
        L[0]=2695651038904480643095480586660090858475758527446903765705641981883605457287;
        L[1]=41190341244083725261184613451000288823985035577628775396726814322155453175787;
        z.limbs=L; z.neg=false;
    }
    function PI__c() internal pure returns (B.Int memory z){
        uint256[] memory L=new uint256[](2);
        L[0]=106592109288730704218496300194444848008435892996710960121656014760147202925426;
        L[1]=50556551478175803354399513745659257516221990244407850960973777141500101120486;
        z.limbs=L; z.neg=false;
    }
    function PI_() internal pure returns (CG.Form memory){ return CG.Form(PI__a(),PI__b(),PI__c()); }

    function test_PrimeMatchesPython() public pure {
        require(W.fiatShamirPrime(U_(), Wf_(), T_, D_()) == L_EXPECTED, "l mismatch");
    }
    function test_RealProofVerifies() public view {
        uint256 g0 = gasleft();
        bool ok = W.verify(U_(), Wf_(), PI_(), T_, D_());
        console2.log("WESOLOWSKI e2e verify gas:", g0 - gasleft());
        require(ok, "real proof rejected");
    }
    function test_TamperedProofFails() public pure {
        require(!W.verify(U_(), Wf_(), U_(), T_, D_()), "accepted pi=u");
        require(!W.verify(U_(), U_(), PI_(), T_, D_()), "accepted w=u");
    }
}
