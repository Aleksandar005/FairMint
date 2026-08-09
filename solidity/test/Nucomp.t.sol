// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test, console2} from "forge-std/Test.sol";
import {LibBigInt as B} from "../src/LibBigInt.sol";
import {LibClassGroupBig as CG} from "../src/LibClassGroupBig.sol";

contract NucompTest is Test {
    function _mk(bool neg, uint256[] memory limbs) internal pure returns (B.Int memory z){
        z.neg=neg; z.limbs=limbs;
    }
    function D() internal pure returns (B.Int memory){
        uint256[] memory L=new uint256[](4);
        L[0]=92325566918696944234767304319137366847153991194884342244635223870271662148071;
        L[1]=32174161634477040966241220395732563175035854139341062605219251733148279181470;
        L[2]=79158291431234642836385543944599643540406777840668402635541297532275410114020;
        L[3]=114771056843020146160412573772694622931096687497452774663550018905897036661487;
        return _mk(true,L);
    }
    function CF1_a() internal pure returns (B.Int memory){
        uint256[] memory L=new uint256[](2);
        L[0]=37221165354312864152557128126078352754902757937341451727353969200958347967750;
        L[1]=36872455765703503594300770337056989027418011066151010556255451791682987867229;
        return _mk(false,L);
    }
    function CF1_b() internal pure returns (B.Int memory){
        uint256[] memory L=new uint256[](2);
        L[0]=83894966728313284126472375795699075528518244308787968832902716771449451344005;
        L[1]=27205231844264628296229635227718935514319955085692096544145073934030495689048;
        return _mk(false,L);
    }
    function CF1_c() internal pure returns (B.Int memory){
        uint256[] memory L=new uint256[](2);
        L[0]=10586075004623001799400715589164714032738242354896567835889516703905068246176;
        L[1]=95123207853827297566357164734827568269309596650557076789623643879659753901436;
        return _mk(false,L);
    }
    function CF1() internal pure returns (CG.Form memory){
        return CG.Form(CF1_a(),CF1_b(),CF1_c());
    }
    function CF2_a() internal pure returns (B.Int memory){
        uint256[] memory L=new uint256[](2);
        L[0]=1177072468152160386012660390937566156399363902566707171861561303970196766485;
        L[1]=35453687506043773620092625219672413132772918821363393873835874268845311957321;
        return _mk(false,L);
    }
    function CF2_b() internal pure returns (B.Int memory){
        uint256[] memory L=new uint256[](2);
        L[0]=6008748037827129295885338001820889713247656429504162731367322234525847585397;
        L[1]=25016073522262804823982718015515606714088295197052596336959527789043662056405;
        return _mk(true,L);
    }
    function CF2_c() internal pure returns (B.Int memory){
        uint256[] memory L=new uint256[](2);
        L[0]=44562674051922427425629361447713695978028322729860723179787726805123029956472;
        L[1]=98123674638408116339550279547701300346077593441257829959691964414916439453276;
        return _mk(false,L);
    }
    function CF2() internal pure returns (CG.Form memory){
        return CG.Form(CF2_a(),CF2_b(),CF2_c());
    }
    function CRES_a() internal pure returns (B.Int memory){
        uint256[] memory L=new uint256[](2);
        L[0]=61036354419310234645540894444951277440171676598004873909507821133966393608885;
        L[1]=19128644972241958667174269225962544846830922652591058953349396138158079429211;
        return _mk(false,L);
    }
    function CRES_b() internal pure returns (B.Int memory){
        uint256[] memory L=new uint256[](2);
        L[0]=14409659826129733899794898017521489158228068859996828067797366979908697700175;
        L[1]=8335742569295200826109981012345346146565397555236849655819204328428086494285;
        return _mk(true,L);
    }
    function CRES_c() internal pure returns (B.Int memory){
        uint256[] memory L=new uint256[](3);
        L[0]=54783907870296079738559697296444360866212251667190146010842974601878586098186;
        L[1]=58802936696241857030636934488023654018972678859438636276529985452776062098785;
        L[2]=1;
        return _mk(false,L);
    }
    function CRES() internal pure returns (CG.Form memory){
        return CG.Form(CRES_a(),CRES_b(),CRES_c());
    }
    function NF1_a() internal pure returns (B.Int memory){
        uint256[] memory L=new uint256[](2);
        L[0]=96741010494962255380313972950142887881816934710050190569065597768041913907132;
        L[1]=37305924792372223052905286392787662941956186593464006047390646707456161268772;
        return _mk(false,L);
    }
    function NF1_b() internal pure returns (B.Int memory){
        uint256[] memory L=new uint256[](2);
        L[0]=22108182133002754182161539566056593221516405387567074423718779071292340898043;
        L[1]=27505983796961596847379208844484353503537919763079889254852553260759495088469;
        return _mk(true,L);
    }
    function NF1_c() internal pure returns (B.Int memory){
        uint256[] memory L=new uint256[](2);
        L[0]=63655095668655683157022683281577962630787120986085846717473100611170763174144;
        L[1]=94128209383906951117778227778527289129357569242688279320776714865157628620798;
        return _mk(false,L);
    }
    function NF1() internal pure returns (CG.Form memory){
        return CG.Form(NF1_a(),NF1_b(),NF1_c());
    }
    function NF2_a() internal pure returns (B.Int memory){
        uint256[] memory L=new uint256[](2);
        L[0]=17509228149541552618374837714178542348825902421135000305684077494178135599460;
        L[1]=49557041881661039846362230360605938086268866853291353117056297220521549492612;
        return _mk(false,L);
    }
    function NF2_b() internal pure returns (B.Int memory){
        uint256[] memory L=new uint256[](2);
        L[0]=52256940036980136318750744568125537785934635910809120674702588847816887253571;
        L[1]=23979829850561811806812440153182977976763717627757932255328297824724108191836;
        return _mk(false,L);
    }
    function NF2_c() internal pure returns (B.Int memory){
        uint256[] memory L=new uint256[](2);
        L[0]=42180626477072117269894694866355293216324815529366340490862789878329431198287;
        L[1]=69942697188210698167136365492404325561985530826787608075745612201754079753847;
        return _mk(false,L);
    }
    function NF2() internal pure returns (CG.Form memory){
        return CG.Form(NF2_a(),NF2_b(),NF2_c());
    }
    function NRES_a() internal pure returns (B.Int memory){
        uint256[] memory L=new uint256[](2);
        L[0]=63889106497180237923967581101162340814405841968298096739355556368555646548741;
        L[1]=35132718346497782667215077498115440817232186660700216641490055923705700766221;
        return _mk(false,L);
    }
    function NRES_b() internal pure returns (B.Int memory){
        uint256[] memory L=new uint256[](2);
        L[0]=91184340723108495337333873802371022202901284933456204914000029013322548335337;
        L[1]=31937684057082582873156091019609880761173795183317101331637873354493676245141;
        return _mk(true,L);
    }
    function NRES_c() internal pure returns (B.Int memory){
        uint256[] memory L=new uint256[](2);
        L[0]=21486518679764480845777549476259571127719618095654726648663339736290780261094;
        L[1]=101825284181180947809433717760269727198048623355650261247222571745965780713085;
        return _mk(false,L);
    }
    function NRES() internal pure returns (CG.Form memory){
        return CG.Form(NRES_a(),NRES_b(),NRES_c());
    }

    function test_NucompCoprimeMatchesCompose() public view {
        B.Int memory d=D();
        CG.Form memory got=CG.nucomp(CF1(),CF2(),d);
        assertTrue(CG.eq(got, CRES()), "nucomp coprime != compose");
        assertTrue(CG.eq(got, CG.compose(CF1(),CF2(),d)), "nucomp != compose (live)");
    }
    function test_NucompNoncoprimeMatchesCompose() public view {
        B.Int memory d=D();
        CG.Form memory got=CG.nucomp(NF1(),NF2(),d);
        assertTrue(CG.eq(got, NRES()), "nucomp noncoprime != compose");
    }
    function test_GasNucompVsCompose() public view {
        B.Int memory d=D();
        uint256 g0=gasleft(); CG.nucomp(CF1(),CF2(),d);   uint256 gN=g0-gasleft();
        g0=gasleft();        CG.compose(CF1(),CF2(),d);   uint256 gC=g0-gasleft();
        console2.log("NUCOMP  gas:", gN);
        console2.log("compose gas:", gC);
    }
}
