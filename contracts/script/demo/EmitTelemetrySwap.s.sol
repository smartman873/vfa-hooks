// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {IUniswapV4Router04} from "hookmate/interfaces/router/IUniswapV4Router04.sol";
import {AddressConstants} from "hookmate/constants/AddressConstants.sol";

contract EmitTelemetrySwapScript is Script {
    using PoolIdLibrary for PoolKey;

    function run() external {
        uint256 privateKey = vm.envUint("SEPOLIA_PRIVATE_KEY");
        PoolKey memory poolKey = _poolKeyFromEnv();
        uint256 amountIn = vm.envOr("DEMO_TELEMETRY_SWAP_AMOUNT_IN", uint256(1e18));
        bool zeroForOne = vm.envOr("DEMO_TELEMETRY_ZERO_FOR_ONE", true);

        _broadcastSwap(privateKey, poolKey, amountIn, zeroForOne);

        bytes32 poolId = PoolId.unwrap(poolKey.toId());
        console2.log("telemetrySwapPoolId");
        console2.logBytes32(poolId);
        console2.log("telemetrySwapAmountIn", amountIn);
        console2.log("telemetrySwapZeroForOne", zeroForOne);
    }

    function _poolKeyFromEnv() internal view returns (PoolKey memory) {
        address hookAddress = vm.envAddress("HOOK_ADDRESS");
        address token0Address = vm.envAddress("TELEMETRY_TOKEN0_ADDRESS");
        address token1Address = vm.envAddress("TELEMETRY_TOKEN1_ADDRESS");
        uint24 fee = uint24(vm.envOr("DEMO_HOOK_FEE", uint256(3000)));
        int24 tickSpacing = int24(int256(vm.envOr("DEMO_HOOK_TICK_SPACING", uint256(60))));

        return PoolKey({
            currency0: Currency.wrap(token0Address),
            currency1: Currency.wrap(token1Address),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hookAddress)
        });
    }

    function _broadcastSwap(uint256 privateKey, PoolKey memory poolKey, uint256 amountIn, bool zeroForOne) internal {
        address sender = vm.addr(privateKey);
        address tokenIn = zeroForOne ? Currency.unwrap(poolKey.currency0) : Currency.unwrap(poolKey.currency1);
        uint256 deadlineBuffer = vm.envOr("DEMO_TELEMETRY_DEADLINE_SECONDS", uint256(900));

        IPoolManager poolManager = IPoolManager(vm.envAddress("POOL_MANAGER_ADDRESS"));
        IPermit2 permit2 = IPermit2(AddressConstants.getPermit2Address());
        IUniswapV4Router04 swapRouter = IUniswapV4Router04(payable(vm.envAddress("HOOKMATE_SWAP_ROUTER_ADDRESS")));

        vm.startBroadcast(privateKey);
        IERC20(tokenIn).approve(address(permit2), type(uint256).max);
        IERC20(tokenIn).approve(address(swapRouter), type(uint256).max);
        permit2.approve(tokenIn, address(poolManager), type(uint160).max, type(uint48).max);
        swapRouter.swapExactTokensForTokens(
            amountIn,
            0,
            zeroForOne,
            poolKey,
            bytes(""),
            sender,
            block.timestamp + deadlineBuffer
        );
        vm.stopBroadcast();
    }
}
