// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {VolatilityShareToken} from "../../src/VolatilityShareToken.sol";
import {VolatilityMarket} from "../../src/VolatilityMarket.sol";
import {SettlementExecutor} from "../../src/SettlementExecutor.sol";
import {VolatilityHook} from "../../src/VolatilityHook.sol";

contract DeploySepoliaScript is Script {
    error HookSaltNotFound();

    // Foundry CREATE2 deployer used by `new Contract{salt: ...}` under broadcast.
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() external {
        uint256 privateKey = vm.envUint("SEPOLIA_PRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        IPoolManager poolManager = IPoolManager(vm.envAddress("POOL_MANAGER"));

        address callbackProxy = vm.envAddress("CALLBACK_PROXY_ADDRESS");
        address expectedReactVmId = vm.envAddress("EXPECTED_REACT_VM_ID");

        uint256 minSwapVolume = vm.envOr("HOOK_MIN_SWAP_VOLUME", uint256(1e6));
        uint24 maxTickDelta = uint24(vm.envOr("HOOK_MAX_TICK_DELTA", uint256(500)));
        uint256 seededCollateral = vm.envOr("SEEDED_COLLATERAL_SUPPLY", uint256(10_000_000e18));

        vm.startBroadcast(privateKey);

        IERC20 collateral;
        if (vm.envExists("COLLATERAL_TOKEN")) {
            collateral = IERC20(vm.envAddress("COLLATERAL_TOKEN"));
        } else {
            MockERC20 mockCollateral = new MockERC20("VFA Collateral", "VFAC");
            mockCollateral.mint(deployer, seededCollateral);
            collateral = IERC20(address(mockCollateral));
        }

        VolatilityShareToken share = new VolatilityShareToken("ipfs://vfa/{id}.json", deployer);
        VolatilityMarket market = new VolatilityMarket(collateral, share, deployer);
        SettlementExecutor executor = new SettlementExecutor(market, callbackProxy, expectedReactVmId, deployer);

        share.setMarket(address(market));
        market.setSettlementExecutor(address(executor));

        bytes32 poolId = keccak256("VFA/SEPOLIA/POOL");
        market.createVolatilityPool(poolId, 1 days, 1e6, 1_000_000_000, 100e18);

        VolatilityHook hook = _deployHook(poolManager, minSwapVolume, maxTickDelta);

        vm.stopBroadcast();

        console2.log("deployer", deployer);
        console2.log("hook", address(hook));
        console2.log("share", address(share));
        console2.log("market", address(market));
        console2.log("executor", address(executor));
        console2.log("collateral", address(collateral));
    }

    function _deployHook(IPoolManager poolManager, uint256 minSwapVolume, uint24 maxTickDelta)
        internal
        returns (VolatilityHook)
    {
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        bytes memory constructorArgs = abi.encode(poolManager, minSwapVolume, maxTickDelta);
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(VolatilityHook).creationCode, constructorArgs));

        (address hookAddress, bytes32 salt) = _mineHookSalt(flags, Hooks.ALL_HOOK_MASK, initCodeHash);

        VolatilityHook hook = new VolatilityHook{salt: salt}(poolManager, minSwapVolume, maxTickDelta);
        require(address(hook) == hookAddress, "hook address mismatch");

        return hook;
    }

    function _mineHookSalt(uint160 requiredFlags, uint160 flagMask, bytes32 initCodeHash)
        internal
        view
        returns (address hookAddress, bytes32 salt)
    {
        for (uint256 i = 0; i < 1_000_000; i++) {
            salt = bytes32(i);
            hookAddress = _computeCreate2Address(CREATE2_DEPLOYER, salt, initCodeHash);
            if ((uint160(hookAddress) & flagMask) == requiredFlags && hookAddress.code.length == 0) {
                return (hookAddress, salt);
            }
        }

        revert HookSaltNotFound();
    }

    function _computeCreate2Address(address deployer, bytes32 salt, bytes32 initCodeHash)
        internal
        pure
        returns (address)
    {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash));
        return address(uint160(uint256(hash)));
    }
}
