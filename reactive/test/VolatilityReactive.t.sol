// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, Vm} from "forge-std/Test.sol";

import {VolatilityReactive} from "../src/VolatilityReactive.sol";
import {ReactiveVolatilityMath} from "../src/libraries/ReactiveVolatilityMath.sol";
import {IReactive} from "reactive-lib/interfaces/IReactive.sol";

contract MockSystemContract {
    uint256 public subscribeCount;

    function subscribe(uint256, address, uint256, uint256, uint256, uint256) external {
        subscribeCount++;
    }

    function unsubscribe(uint256, address, uint256, uint256, uint256, uint256) external {}

    function debt(address) external pure returns (uint256) {
        return 0;
    }

    receive() external payable {}
}

contract VolatilityReactiveTest is Test {
    bytes32 internal constant EPOCH_STARTED_TOPIC_0 =
        keccak256("EpochStarted(bytes32,uint256,uint64,uint64,uint256)");
    bytes32 internal constant TELEMETRY_TOPIC_0 =
        keccak256("TelemetryUpdated(bytes32,int24,uint256,uint256,uint256,uint256,uint256,uint256,uint256)");
    bytes32 internal constant CALLBACK_TOPIC_0 =
        keccak256("Callback(uint256,address,uint64,bytes)");
    address payable internal constant SYSTEM_CONTRACT = payable(0x0000000000000000000000000000000000fffFfF);

    VolatilityReactive internal reactiveContract;

    uint256 internal constant ORIGIN_CHAIN = 11155111;
    uint256 internal constant DEST_CHAIN = 84532;

    address internal constant ORIGIN_HOOK = address(0x1001);
    address internal constant ORIGIN_MARKET = address(0x1002);
    address internal constant EXECUTOR = address(0x1003);

    function setUp() public {
        reactiveContract = new VolatilityReactive(
            ORIGIN_CHAIN,
            DEST_CHAIN,
            ORIGIN_HOOK,
            ORIGIN_MARKET,
            EXECUTOR,
            900_000,
            _defaultParams()
        );
    }

    function testRevertWhen_CallbackGasLimitBelowMinimum() public {
        vm.expectRevert("callback gas too low");
        new VolatilityReactive(
            ORIGIN_CHAIN,
            DEST_CHAIN,
            ORIGIN_HOOK,
            ORIGIN_MARKET,
            EXECUTOR,
            99_999,
            _defaultParams()
        );
    }

    function testBuildsCallbackOnceAfterEpochEnd() public {
        bytes32 poolId = keccak256("pool-reactive");

        IReactive.LogRecord memory epochLog = _epochStartLog(poolId, 1, 100, 200, 100e18);
        reactiveContract.react(epochLog);

        IReactive.LogRecord memory preEndTelemetry = _telemetryLog(poolId, 10, 1000, 100_000, 1_000e18, 5, 1e18, 150, 10, 1);
        reactiveContract.react(preEndTelemetry);

        (, , , , , , , , , bool callbackSent) = reactiveContract.trackedEpochs(poolId);
        assertFalse(callbackSent);

        IReactive.LogRecord memory endTelemetry = _telemetryLog(poolId, 12, 2200, 240_000, 3_000e18, 9, 2e18, 220, 11, 2);

        vm.recordLogs();
        reactiveContract.react(endTelemetry);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertTrue(_containsTopic(logs, CALLBACK_TOPIC_0));

        (, , , , , , , , , callbackSent) = reactiveContract.trackedEpochs(poolId);
        assertTrue(callbackSent);

        vm.recordLogs();
        IReactive.LogRecord memory laterTelemetry = _telemetryLog(poolId, 15, 3200, 300_000, 4_000e18, 11, 2e18, 240, 12, 3);
        reactiveContract.react(laterTelemetry);
        Vm.Log[] memory laterLogs = vm.getRecordedLogs();

        assertFalse(_containsTopic(laterLogs, CALLBACK_TOPIC_0));
    }

    function testInitializeSubscriptionsRevertsOnVmInstance() public {
        vm.expectRevert("Reactive Network only");
        reactiveContract.initializeSubscriptions();
    }

    function testReactIgnoresUnknownTopic() public {
        IReactive.LogRecord memory unknownLog = _telemetryLog(
            keccak256("pool-unknown"), 1, 10, 20, 30, 2, 1, 222, 10, 1
        );
        unknownLog.topic_0 = uint256(keccak256("unknown"));

        vm.recordLogs();
        reactiveContract.react(unknownLog);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertFalse(_containsTopic(logs, CALLBACK_TOPIC_0));
    }

    function testConstructorAutoInitializesSubscriptionsOnReactiveNetwork() public {
        _installMockSystemContract();
        VolatilityReactive rnInstance = new VolatilityReactive(
            ORIGIN_CHAIN,
            DEST_CHAIN,
            ORIGIN_HOOK,
            ORIGIN_MARKET,
            EXECUTOR,
            900_000,
            _defaultParams()
        );

        assertTrue(rnInstance.subscriptionsInitialized());
        assertEq(MockSystemContract(SYSTEM_CONTRACT).subscribeCount(), 2);
    }

    function testInitializeSubscriptionsOwnerCheckOnReactiveNetwork() public {
        VolatilityReactive rnInstance = _deployRnInstance();

        vm.prank(address(0xBEEF));
        vm.expectRevert("owner only");
        rnInstance.initializeSubscriptions();
    }

    function testInitializeSubscriptionsCanReinitializeWhenFlagReset() public {
        VolatilityReactive rnInstance = _deployRnInstance();

        uint256 beforeCalls = MockSystemContract(SYSTEM_CONTRACT).subscribeCount();
        bytes32 packedSlot = vm.load(address(rnInstance), bytes32(uint256(2)));
        uint256 clearedSubscriptions = uint256(packedSlot) & ~(uint256(0xff) << (21 * 8));
        vm.store(address(rnInstance), bytes32(uint256(2)), bytes32(clearedSubscriptions));

        rnInstance.initializeSubscriptions();

        assertTrue(rnInstance.subscriptionsInitialized());
        assertEq(MockSystemContract(SYSTEM_CONTRACT).subscribeCount(), beforeCalls + 2);
    }

    function testInitializeSubscriptionsIdempotentWhenAlreadyInitialized() public {
        VolatilityReactive rnInstance = _deployRnInstance();
        uint256 beforeCalls = MockSystemContract(SYSTEM_CONTRACT).subscribeCount();

        rnInstance.initializeSubscriptions();

        assertEq(MockSystemContract(SYSTEM_CONTRACT).subscribeCount(), beforeCalls);
    }

    function testReactRevertsOutsideVm() public {
        VolatilityReactive rnInstance = _deployRnInstance();
        IReactive.LogRecord memory log = _telemetryLog(keccak256("rn-react"), 1, 2, 3, 4, 1, 1, 123, 1, 1);

        vm.expectRevert("VM only");
        rnInstance.react(log);
    }

    function _containsTopic(Vm.Log[] memory logs, bytes32 topic) internal pure returns (bool) {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == topic) {
                return true;
            }
        }
        return false;
    }

    function _defaultParams() internal pure returns (ReactiveVolatilityMath.Params memory) {
        return ReactiveVolatilityMath.Params({
            volumeScale: 10_000e18,
            spikeScale: 100e18,
            maxVolumeBoost: 1e18,
            maxSpikeBoost: 1e18
        });
    }

    function _installMockSystemContract() internal {
        MockSystemContract mock = new MockSystemContract();
        vm.etch(SYSTEM_CONTRACT, address(mock).code);
    }

    function _deployRnInstance() internal returns (VolatilityReactive) {
        _installMockSystemContract();
        return new VolatilityReactive(
            ORIGIN_CHAIN,
            DEST_CHAIN,
            ORIGIN_HOOK,
            ORIGIN_MARKET,
            EXECUTOR,
            900_000,
            _defaultParams()
        );
    }

    function _epochStartLog(bytes32 poolId, uint256 epochId, uint64 startTime, uint64 endTime, uint256 settlementPrice)
        internal
        pure
        returns (IReactive.LogRecord memory)
    {
        return IReactive.LogRecord({
            chain_id: ORIGIN_CHAIN,
            _contract: ORIGIN_MARKET,
            topic_0: uint256(EPOCH_STARTED_TOPIC_0),
            topic_1: uint256(poolId),
            topic_2: epochId,
            topic_3: 0,
            data: abi.encode(startTime, endTime, settlementPrice),
            block_number: 1,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 1
        });
    }

    function _telemetryLog(
        bytes32 poolId,
        int24 tick,
        uint256 cumulativeAbs,
        uint256 cumulativeSquared,
        uint256 cumulativeVolume,
        uint256 swapCount,
        uint256 spikeScore,
        uint256 timestamp,
        uint256 sourceBlock,
        uint256 logIndex
    ) internal pure returns (IReactive.LogRecord memory) {
        return IReactive.LogRecord({
            chain_id: ORIGIN_CHAIN,
            _contract: ORIGIN_HOOK,
            topic_0: uint256(TELEMETRY_TOPIC_0),
            topic_1: uint256(poolId),
            topic_2: 0,
            topic_3: 0,
            data: abi.encode(tick, cumulativeAbs, cumulativeSquared, cumulativeVolume, swapCount, spikeScore, timestamp, sourceBlock),
            block_number: sourceBlock,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: logIndex
        });
    }
}
