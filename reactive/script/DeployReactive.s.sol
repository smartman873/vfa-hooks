// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";

import {VolatilityReactive} from "../src/VolatilityReactive.sol";
import {ReactiveVolatilityMath} from "../src/libraries/ReactiveVolatilityMath.sol";

contract DeployReactiveScript is Script {
    function run() external {
        uint256 privateKey = vm.envUint("REACTIVE_PRIVATE_KEY");

        uint256 originChainId = vm.envUint("ORIGIN_CHAIN_ID");
        uint256 destinationChainId = vm.envUint("DESTINATION_CHAIN_ID");

        address originHook = vm.envAddress("ORIGIN_HOOK_ADDRESS");
        address originMarket = vm.envAddress("ORIGIN_MARKET_ADDRESS");
        address settlementExecutor = vm.envAddress("SETTLEMENT_EXECUTOR_ADDRESS");

        uint64 callbackGasLimit = uint64(vm.envOr("CALLBACK_GAS_LIMIT", uint256(1_200_000)));
        uint256 deployValue = vm.envOr("REACTIVE_DEPLOY_VALUE_WEI", uint256(0.1 ether));

        ReactiveVolatilityMath.Params memory params = ReactiveVolatilityMath.Params({
            volumeScale: vm.envOr("VOLUME_SCALE", uint256(10_000e18)),
            spikeScale: vm.envOr("SPIKE_SCALE", uint256(100e18)),
            maxVolumeBoost: vm.envOr("MAX_VOLUME_BOOST", uint256(1e18)),
            maxSpikeBoost: vm.envOr("MAX_SPIKE_BOOST", uint256(1e18))
        });

        vm.startBroadcast(privateKey);

        VolatilityReactive reactive = new VolatilityReactive{value: deployValue}(
            originChainId,
            destinationChainId,
            originHook,
            originMarket,
            settlementExecutor,
            callbackGasLimit,
            params
        );

        reactive.initializeSubscriptions();

        vm.stopBroadcast();

        console2.log("volatilityReactive", address(reactive));
    }
}
