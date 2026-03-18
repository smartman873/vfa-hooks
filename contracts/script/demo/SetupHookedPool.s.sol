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
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import {AddressConstants} from "hookmate/constants/AddressConstants.sol";

import {MockERC20} from "../../src/mocks/MockERC20.sol";

contract SetupHookedPoolScript is Script {
    using PoolIdLibrary for PoolKey;

    uint160 internal constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

    uint256 internal privateKey;
    address internal deployer;
    address internal hookAddress;
    IPoolManager internal poolManager;
    IPositionManager internal positionManager;
    IPermit2 internal permit2;
    uint24 internal fee;
    int24 internal tickSpacing;
    uint128 internal liquidityAmount;
    uint256 internal tokenMintAmount;
    uint256 internal deadlineBuffer;
    string internal suffix;

    function run() external {
        _loadConfig();

        vm.startBroadcast(privateKey);

        (MockERC20 token0, MockERC20 token1) = _deployAndApproveTokens();
        PoolKey memory poolKey = _initializePool(token0, token1);
        uint256 positionTokenId = _seedLiquidity(poolKey);

        vm.stopBroadcast();

        bytes32 poolId = PoolId.unwrap(poolKey.toId());
        console2.log("telemetryToken0", address(token0));
        console2.log("telemetryToken1", address(token1));
        console2.log("telemetryPoolId");
        console2.logBytes32(poolId);
        console2.log("telemetryPositionTokenId", positionTokenId);
    }

    function _loadConfig() internal {
        privateKey = vm.envUint("SEPOLIA_PRIVATE_KEY");
        deployer = vm.addr(privateKey);
        hookAddress = vm.envAddress("HOOK_ADDRESS");
        poolManager = IPoolManager(vm.envAddress("POOL_MANAGER_ADDRESS"));
        positionManager = IPositionManager(vm.envAddress("POSITION_MANAGER_ADDRESS"));
        permit2 = IPermit2(AddressConstants.getPermit2Address());

        fee = uint24(vm.envOr("DEMO_HOOK_FEE", uint256(3000)));
        tickSpacing = int24(int256(vm.envOr("DEMO_HOOK_TICK_SPACING", uint256(60))));
        liquidityAmount = uint128(vm.envOr("DEMO_HOOK_LIQUIDITY", uint256(100e18)));
        tokenMintAmount = vm.envOr("DEMO_HOOK_TOKEN_MINT", uint256(1_000_000e18));
        deadlineBuffer = vm.envOr("DEMO_HOOK_DEADLINE_SECONDS", uint256(900));
        suffix = vm.envOr("DEMO_HOOK_TOKEN_SUFFIX", string("LIVE"));
    }

    function _deployAndApproveTokens() internal returns (MockERC20 token0, MockERC20 token1) {
        MockERC20 tokenA = new MockERC20(string.concat("VFA Hook Token A ", suffix), "VFHA");
        MockERC20 tokenB = new MockERC20(string.concat("VFA Hook Token B ", suffix), "VFHB");
        tokenA.mint(deployer, tokenMintAmount);
        tokenB.mint(deployer, tokenMintAmount);

        (token0, token1) = address(tokenA) < address(tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);

        _approveForV4(token0);
        _approveForV4(token1);
    }

    function _initializePool(MockERC20 token0, MockERC20 token1) internal returns (PoolKey memory poolKey) {
        poolKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hookAddress)
        });
        poolManager.initialize(poolKey, SQRT_PRICE_1_1);
    }

    function _seedLiquidity(PoolKey memory poolKey) internal returns (uint256 positionTokenId) {
        int24 tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR), uint8(Actions.SWEEP), uint8(Actions.SWEEP)
        );
        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(
            poolKey, tickLower, tickUpper, liquidityAmount, amount0Expected + 1, amount1Expected + 1, deployer, bytes("")
        );
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        params[2] = abi.encode(poolKey.currency0, deployer);
        params[3] = abi.encode(poolKey.currency1, deployer);

        positionTokenId = positionManager.nextTokenId();
        positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp + deadlineBuffer);
    }

    function _approveForV4(IERC20 token) internal {
        token.approve(address(permit2), type(uint256).max);
        permit2.approve(address(token), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(token), address(poolManager), type(uint160).max, type(uint48).max);
    }
}
