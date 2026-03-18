// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AbstractPayer} from "reactive-lib/abstract-base/AbstractPayer.sol";
import {IPayable} from "reactive-lib/interfaces/IPayable.sol";

import {IVolatilityMarket} from "./interfaces/IVolatilityMarket.sol";

contract SettlementExecutor is Ownable, ReentrancyGuard, AbstractPayer {
    error UnauthorizedCallbackProxy();
    error InvalidReactVmId();

    event EpochSettlementForwarded(
        address indexed reactVmId,
        bytes32 indexed poolId,
        uint256 indexed epochId,
        bytes32 replayKey,
        uint256 realizedVolatility,
        uint256 settlementPrice
    );

    IVolatilityMarket public immutable market;

    address public callbackProxy;
    address public expectedReactVmId;

    mapping(bytes32 => bool) public processedReplayKeys;

    constructor(IVolatilityMarket _market, address _callbackProxy, address _expectedReactVmId, address _owner)
        Ownable(_owner)
    {
        require(address(_market) != address(0), "zero market");
        require(_callbackProxy != address(0), "zero callbackProxy");
        require(_expectedReactVmId != address(0), "zero reactVmId");
        market = _market;
        callbackProxy = _callbackProxy;
        expectedReactVmId = _expectedReactVmId;
        vendor = IPayable(payable(_callbackProxy));
        addAuthorizedSender(_callbackProxy);
    }

    function setCallbackProxy(address newCallbackProxy) external onlyOwner {
        require(newCallbackProxy != address(0), "zero callbackProxy");
        removeAuthorizedSender(callbackProxy);
        callbackProxy = newCallbackProxy;
        vendor = IPayable(payable(newCallbackProxy));
        addAuthorizedSender(newCallbackProxy);
    }

    function setExpectedReactVmId(address newExpectedReactVmId) external onlyOwner {
        require(newExpectedReactVmId != address(0), "zero reactVmId");
        expectedReactVmId = newExpectedReactVmId;
    }

    // First argument is overwritten by Reactive callback infrastructure with the ReactVM ID.
    function settleEpoch(
        address reactVmId,
        bytes32 poolId,
        uint256 epochId,
        uint256 realizedVolatility,
        uint256 settlementPrice,
        bytes32 replayKey
    ) external nonReentrant {
        if (msg.sender != callbackProxy) {
            revert UnauthorizedCallbackProxy();
        }

        if (reactVmId != expectedReactVmId) {
            revert InvalidReactVmId();
        }

        if (processedReplayKeys[replayKey]) {
            return;
        }

        processedReplayKeys[replayKey] = true;

        market.finalizeEpoch(poolId, epochId, realizedVolatility, settlementPrice, replayKey);

        emit EpochSettlementForwarded(reactVmId, poolId, epochId, replayKey, realizedVolatility, settlementPrice);
    }

    function settleEpochManual(
        bytes32 poolId,
        uint256 epochId,
        uint256 realizedVolatility,
        uint256 settlementPrice,
        bytes32 replayKey
    ) external onlyOwner nonReentrant {
        if (processedReplayKeys[replayKey]) {
            return;
        }

        processedReplayKeys[replayKey] = true;
        market.finalizeEpoch(poolId, epochId, realizedVolatility, settlementPrice, replayKey);

        emit EpochSettlementForwarded(msg.sender, poolId, epochId, replayKey, realizedVolatility, settlementPrice);
    }
}
