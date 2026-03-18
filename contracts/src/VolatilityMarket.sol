// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {VolatilityShareToken} from "./VolatilityShareToken.sol";
import {IVolatilityMarket} from "./interfaces/IVolatilityMarket.sol";
import {EpochLibrary} from "./libraries/EpochLibrary.sol";
import {EncodingLibrary} from "./libraries/EncodingLibrary.sol";

contract VolatilityMarket is IVolatilityMarket, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant ONE = 1e18;
    uint256 public constant MAX_REALIZED_VOLATILITY = 1e24;

    struct VolatilityPool {
        bytes32 poolId;
        uint64 epochDuration;
        uint256 minTradeSize;
        uint256 maxTradeSize;
        uint256 baselineVolatility;
        uint256 currentEpochId;
        bool exists;
    }

    struct Epoch {
        uint64 startTime;
        uint64 endTime;
        uint256 realizedVolatility;
        uint256 settlementPrice;
        uint256 totalLong;
        uint256 totalShort;
        bool settled;
    }

    struct Position {
        address owner;
        bytes32 poolId;
        uint256 epochId;
        uint256 amount;
        bool isLong;
        bool closed;
        bool claimed;
    }

    event VolatilityPoolCreated(
        bytes32 indexed poolId,
        uint64 epochDuration,
        uint256 minTradeSize,
        uint256 maxTradeSize,
        uint256 baselineVolatility
    );

    event EpochStarted(
        bytes32 indexed poolId, uint256 indexed epochId, uint64 startTime, uint64 endTime, uint256 settlementPrice
    );

    event EpochFinalized(
        bytes32 indexed poolId,
        uint256 indexed epochId,
        uint256 realizedVolatility,
        uint256 settlementPrice,
        uint256 totalLong,
        uint256 totalShort
    );

    event PositionOpened(
        uint256 indexed positionId,
        address indexed owner,
        bytes32 indexed poolId,
        uint256 epochId,
        bool isLong,
        uint256 amount
    );

    event PositionClosed(uint256 indexed positionId, address indexed owner, uint256 amount, bool settledClose);

    event SettlementExecuted(
        bytes32 indexed poolId,
        uint256 indexed epochId,
        bytes32 indexed replayKey,
        uint256 realizedVolatility,
        uint256 settlementPrice
    );

    error UnknownPool();
    error InvalidEpoch();
    error NotSettlementExecutor();
    error InvalidPositionOwner();
    error EpochNotActive();
    error EpochNotEnded();
    error EpochNotSettled();
    error PositionClosedError();
    error TradeSizeOutOfBounds();
    error RealizedVolatilityOutOfBounds();
    error SettlementPriceMismatch();

    IERC20 public immutable collateralToken;
    VolatilityShareToken public immutable shareToken;

    address public settlementExecutor;
    uint256 public nextPositionId;

    mapping(bytes32 => VolatilityPool) public volatilityPools;
    mapping(bytes32 => mapping(uint256 => Epoch)) public epochs;
    mapping(uint256 => Position) public positions;

    mapping(bytes32 => mapping(uint256 => uint256)) public longPayoutPerShare;
    mapping(bytes32 => mapping(uint256 => uint256)) public shortPayoutPerShare;

    modifier onlySettlementExecutor() {
        if (msg.sender != settlementExecutor) {
            revert NotSettlementExecutor();
        }
        _;
    }

    constructor(IERC20 _collateralToken, VolatilityShareToken _shareToken, address _owner) Ownable(_owner) {
        collateralToken = _collateralToken;
        shareToken = _shareToken;
    }

    function setSettlementExecutor(address executor) external onlyOwner {
        require(executor != address(0), "zero executor");
        settlementExecutor = executor;
    }

    function createVolatilityPool(
        bytes32 poolId,
        uint64 epochDuration,
        uint256 minTradeSize,
        uint256 maxTradeSize,
        uint256 baselineVolatility
    ) external onlyOwner {
        require(!volatilityPools[poolId].exists, "pool exists");
        require(epochDuration > 0, "epochDuration=0");
        require(minTradeSize > 0 && maxTradeSize >= minTradeSize, "invalid trade bounds");
        require(baselineVolatility > 0, "baseline=0");

        VolatilityPool storage pool = volatilityPools[poolId];
        pool.poolId = poolId;
        pool.epochDuration = epochDuration;
        pool.minTradeSize = minTradeSize;
        pool.maxTradeSize = maxTradeSize;
        pool.baselineVolatility = baselineVolatility;
        pool.currentEpochId = 1;
        pool.exists = true;

        emit VolatilityPoolCreated(poolId, epochDuration, minTradeSize, maxTradeSize, baselineVolatility);
        _startEpoch(pool, 1, baselineVolatility);
    }

    function openPosition(bytes32 poolId, bool isLong, uint256 amount) external nonReentrant returns (uint256 positionId) {
        VolatilityPool storage pool = volatilityPools[poolId];
        if (!pool.exists) revert UnknownPool();

        if (amount < pool.minTradeSize || amount > pool.maxTradeSize) {
            revert TradeSizeOutOfBounds();
        }

        Epoch storage epoch = epochs[poolId][pool.currentEpochId];
        if (!EpochLibrary.isActive(epoch.startTime, epoch.endTime, epoch.settled, block.timestamp)) {
            revert EpochNotActive();
        }

        collateralToken.safeTransferFrom(msg.sender, address(this), amount);

        if (isLong) {
            epoch.totalLong += amount;
        } else {
            epoch.totalShort += amount;
        }

        positionId = ++nextPositionId;
        Position storage position = positions[positionId];
        position.owner = msg.sender;
        position.poolId = poolId;
        position.epochId = pool.currentEpochId;
        position.amount = amount;
        position.isLong = isLong;

        uint256 tokenId = EncodingLibrary.shareTokenId(poolId, pool.currentEpochId, isLong);
        shareToken.mint(msg.sender, tokenId, amount);

        emit PositionOpened(positionId, msg.sender, poolId, pool.currentEpochId, isLong, amount);
    }

    function closePosition(uint256 positionId) external nonReentrant {
        Position storage position = positions[positionId];
        if (position.owner != msg.sender) revert InvalidPositionOwner();
        if (position.closed || position.claimed) revert PositionClosedError();

        VolatilityPool storage pool = volatilityPools[position.poolId];
        if (!pool.exists) revert UnknownPool();

        Epoch storage epoch = epochs[position.poolId][position.epochId];
        if (!EpochLibrary.isActive(epoch.startTime, epoch.endTime, epoch.settled, block.timestamp)) {
            revert EpochNotActive();
        }

        position.closed = true;

        if (position.isLong) {
            epoch.totalLong -= position.amount;
        } else {
            epoch.totalShort -= position.amount;
        }

        uint256 tokenId = EncodingLibrary.shareTokenId(position.poolId, position.epochId, position.isLong);
        shareToken.burn(msg.sender, tokenId, position.amount);

        collateralToken.safeTransfer(msg.sender, position.amount);
        emit PositionClosed(positionId, msg.sender, position.amount, false);
    }

    function finalizeEpoch(
        bytes32 poolId,
        uint256 epochId,
        uint256 realizedVolatility,
        uint256 settlementPrice,
        bytes32 replayKey
    ) external onlySettlementExecutor nonReentrant {
        VolatilityPool storage pool = volatilityPools[poolId];
        if (!pool.exists) revert UnknownPool();

        if (epochId > pool.currentEpochId) revert InvalidEpoch();

        Epoch storage epoch = epochs[poolId][epochId];
        if (epoch.settled) {
            return;
        }

        if (pool.currentEpochId != epochId) revert InvalidEpoch();

        if (!EpochLibrary.hasEnded(epoch.endTime, block.timestamp)) {
            revert EpochNotEnded();
        }

        if (realizedVolatility > MAX_REALIZED_VOLATILITY) {
            revert RealizedVolatilityOutOfBounds();
        }

        if (settlementPrice != epoch.settlementPrice) {
            revert SettlementPriceMismatch();
        }

        epoch.realizedVolatility = realizedVolatility;
        epoch.settled = true;

        (uint256 longPps, uint256 shortPps) = _computePayoutPerShare(epoch);
        longPayoutPerShare[poolId][epochId] = longPps;
        shortPayoutPerShare[poolId][epochId] = shortPps;

        emit EpochFinalized(
            poolId,
            epochId,
            epoch.realizedVolatility,
            epoch.settlementPrice,
            epoch.totalLong,
            epoch.totalShort
        );
        emit SettlementExecuted(poolId, epochId, replayKey, realizedVolatility, settlementPrice);

        uint256 nextEpochId = epochId + 1;
        pool.currentEpochId = nextEpochId;
        uint256 nextSettlementPrice = realizedVolatility == 0 ? epoch.settlementPrice : realizedVolatility;
        _startEpoch(pool, nextEpochId, nextSettlementPrice);
    }

    function claim(uint256 positionId) external nonReentrant {
        Position storage position = positions[positionId];
        if (position.owner != msg.sender) revert InvalidPositionOwner();
        if (position.closed || position.claimed) revert PositionClosedError();

        Epoch storage epoch = epochs[position.poolId][position.epochId];
        if (!epoch.settled) revert EpochNotSettled();

        position.closed = true;
        position.claimed = true;

        uint256 pps = position.isLong
            ? longPayoutPerShare[position.poolId][position.epochId]
            : shortPayoutPerShare[position.poolId][position.epochId];

        uint256 payout = (position.amount * pps) / ONE;
        uint256 tokenId = EncodingLibrary.shareTokenId(position.poolId, position.epochId, position.isLong);
        shareToken.burn(msg.sender, tokenId, position.amount);

        if (payout > 0) {
            collateralToken.safeTransfer(msg.sender, payout);
        }

        emit PositionClosed(positionId, msg.sender, payout, true);
    }

    function isEpochSettled(bytes32 poolId, uint256 epochId) external view returns (bool) {
        return epochs[poolId][epochId].settled;
    }

    function _startEpoch(VolatilityPool storage pool, uint256 epochId, uint256 settlementPrice) internal {
        uint64 startTime = uint64(block.timestamp);
        uint64 endTime = uint64(block.timestamp + pool.epochDuration);

        Epoch storage epoch = epochs[pool.poolId][epochId];
        epoch.startTime = startTime;
        epoch.endTime = endTime;
        epoch.settlementPrice = settlementPrice;

        emit EpochStarted(pool.poolId, epochId, startTime, endTime, settlementPrice);
    }

    function _computePayoutPerShare(Epoch memory epoch) internal pure returns (uint256 longPps, uint256 shortPps) {
        if (epoch.totalLong == 0 && epoch.totalShort == 0) {
            return (ONE, ONE);
        }
        if (epoch.totalLong == 0) {
            return (0, ONE);
        }
        if (epoch.totalShort == 0) {
            return (ONE, 0);
        }

        if (epoch.realizedVolatility > epoch.settlementPrice) {
            longPps = ONE + ((epoch.totalShort * ONE) / epoch.totalLong);
            shortPps = 0;
            return (longPps, shortPps);
        }
        if (epoch.realizedVolatility < epoch.settlementPrice) {
            shortPps = ONE + ((epoch.totalLong * ONE) / epoch.totalShort);
            longPps = 0;
            return (longPps, shortPps);
        }

        return (ONE, ONE);
    }
}
