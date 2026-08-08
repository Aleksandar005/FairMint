// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test, console2} from "forge-std/Test.sol";
import {LibBigInt as B} from "../src/LibBigInt.sol";

contract LehmerBench is Test {
    function _mk(uint256 seed, uint256 nLimbs) private pure returns (B.Int memory z) {
        uint256[] memory L = new uint256[](nLimbs);
        for (uint256 i = 0; i < nLimbs; i++) L[i] = uint256(keccak256(abi.encode(seed, i)));
        L[nLimbs - 1] >>= 2;
        z.limbs = L;
    }
    function test_GasLehmerVsClassic() public view {
        B.Int memory a2 = _mk(1, 2); B.Int memory b2 = _mk(2, 2);
        B.Int memory a4 = _mk(3, 4); B.Int memory b4 = _mk(4, 4);

        uint256 g0 = gasleft();
        (B.Int memory g1, ) = B.xgcdHalf(a2, b2);
        console2.log("LEHMER  xgcdHalf 512-bit gas:", g0 - gasleft());
        g0 = gasleft();
        (B.Int memory g2, ) = B.xgcdHalfClassic(a2, b2);
        console2.log("CLASSIC xgcdHalf 512-bit gas:", g0 - gasleft());
        require(B.cmp(g1, g2) == 0);

        g0 = gasleft();
        (B.Int memory g3, ) = B.xgcdHalf(a4, b4);
        console2.log("LEHMER  xgcdHalf 1024-bit gas:", g0 - gasleft());
        g0 = gasleft();
        (B.Int memory g4, ) = B.xgcdHalfClassic(a4, b4);
        console2.log("CLASSIC xgcdHalf 1024-bit gas:", g0 - gasleft());
        require(B.cmp(g3, g4) == 0);
    }
}
