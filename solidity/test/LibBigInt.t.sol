// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test, console2} from "forge-std/Test.sol";
import {LibBigInt as B} from "../src/LibBigInt.sol";

contract LibBigIntTest is Test {
    using B for B.Int;

    function _u(uint256 x) internal pure returns (B.Int memory) { return B.fromUint(x); }
    function _i(int256 x) internal pure returns (B.Int memory) { return B.fromInt(x); }

    function test_AddSub() public pure {
        assertEq(B.add(_u(5), _u(7)).limbs[0], 12);
        assertTrue(B.cmp(B.sub(_i(5), _i(7)), _i(-2)) == 0);
        assertTrue(B.cmp(B.add(_i(-5), _i(3)), _i(-2)) == 0);
        assertTrue(B.isZero(B.sub(_u(9), _u(9))));
    }

    function test_MulBig() public pure {
        // (2^200) * (2^200) = 2^400  -> proveri preko bita
        B.Int memory a = B.fromUint(1); a.limbs = new uint256[](1); a.limbs[0] = 1;
        // 2^128 * 2^128 = 2^256
        B.Int memory x; x.limbs = new uint256[](1); x.limbs[0] = uint256(1) << 128;
        B.Int memory p = B.mul(x, x); // 2^256
        assertEq(p.limbs.length, 2);
        assertEq(p.limbs[0], 0);
        assertEq(p.limbs[1], 1);
        // znak
        B.Int memory pn = B.mul(_i(-3), _i(4));
        assertTrue(pn.neg);
        assertEq(pn.limbs[0], 12);
    }

    function test_DivModSmall() public pure {
        (B.Int memory q, B.Int memory r) = B.divmod(_u(17), _u(5));
        assertEq(q.limbs[0], 3); assertEq(r.limbs[0], 2);
        // floor semantika: -17 / 5 = -4 rem 3
        (q, r) = B.divmod(_i(-17), _i(5));
        assertTrue(B.cmp(q, _i(-4)) == 0);
        assertTrue(B.cmp(r, _i(3)) == 0);
        // 17 / -5 = -4 rem -3
        (q, r) = B.divmod(_i(17), _i(-5));
        assertTrue(B.cmp(q, _i(-4)) == 0);
        assertTrue(B.cmp(r, _i(-3)) == 0);
    }

    function test_DivModBig() public pure {
        // (2^300 + 123) / 2^100 -> q = 2^200, r = 123
        B.Int memory a; a.limbs = new uint256[](2); a.limbs[0] = 123; a.limbs[1] = (uint256(1) << 44); // 2^(256+44)=2^300
        B.Int memory b; b.limbs = new uint256[](1); b.limbs[0] = 0; // build 2^100
        b.limbs[0] = uint256(1) << 100;
        (B.Int memory q, B.Int memory r) = B.divmod(a, b);
        // q should be 2^200
        assertEq(r.limbs[0], 123);
        assertEq(q.limbs[0], uint256(1) << 200);
    }

    function test_Xgcd() public pure {
        // gcd(240,46)=2, and 240*x+46*y=2
        (B.Int memory g, B.Int memory x, B.Int memory y) = B.xgcd(_u(240), _u(46));
        assertEq(g.limbs[0], 2);
        B.Int memory chk = B.add(B.mul(_u(240), x), B.mul(_u(46), y));
        assertTrue(B.cmp(chk, _u(2)) == 0);
    }
}
