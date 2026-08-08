// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test, console2} from "forge-std/Test.sol";
import {LibBigInt as B} from "../src/LibBigInt.sol";

contract DivEdgeTest is Test {
    function _big(uint256 bits, uint256 seed) internal pure returns (B.Int memory z) {
        uint256 n = bits/256 + 1;
        z.limbs = new uint256[](n);
        for (uint256 i=0;i<n;i++) z.limbs[i]=uint256(keccak256(abi.encode(seed,i)));
    }
    // property: for random a,b>0, a = (a/b)*b + (a%b), and 0<=a%b<b
    function test_DivIdentityRandom() public pure {
        for (uint256 s=1; s<=12; s++) {
            B.Int memory a=_big(1024,s);
            B.Int memory b=_big(512,s+100);
            (B.Int memory q, B.Int memory r)=B.divmod(a,b);
            B.Int memory chk=B.add(B.mul(q,b),r);
            assertTrue(B.cmp(chk,a)==0, "a=q*b+r fails");
            assertTrue(B.cmp(r,B.fromUint(0))>=0 && B.cmp(r,b)<0, "r out of range");
        }
    }
    // divide a*b by b must give exactly a
    function test_ExactDivision() public pure {
        for (uint256 s=1; s<=12; s++) {
            B.Int memory a=_big(768,s);
            B.Int memory b=_big(512,s+50);
            B.Int memory p=B.mul(a,b);
            (B.Int memory q, B.Int memory r)=B.divmod(p,b);
            assertTrue(B.isZero(r), "remainder not zero");
            assertTrue(B.cmp(q,a)==0, "quotient != a");
        }
    }

    // fuzz: native-div Warren path must match for arbitrary widths and shifts
    function testFuzz_DivIdentity(uint256 s1, uint256 s2, uint8 abits, uint8 bbits) public pure {
        uint256 aw = uint256(abits) % 1024 + 256;
        uint256 bw = uint256(bbits) % 512 + 256;
        B.Int memory a=_big(aw, s1==0?1:s1);
        B.Int memory b=_big(bw, s2==0?2:s2);
        if (B.isZero(b)) return;
        (B.Int memory q, B.Int memory r)=B.divmod(a,b);
        B.Int memory chk=B.add(B.mul(q,b),r);
        assertTrue(B.cmp(chk,a)==0, "a=q*b+r");
        assertTrue(B.cmp(r,B.fromUint(0))>=0 && B.cmp(r,b)<0, "0<=r<b");
    }
}