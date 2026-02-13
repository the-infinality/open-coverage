// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin-v5/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-v5/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableMap} from "@openzeppelin-v5/contracts/utils/structs/EnumerableMap.sol";
import {IAllocationManager, IAllocationManagerTypes} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";
import {IPermissionController} from "eigenlayer-contracts/interfaces/IPermissionController.sol";
import {Refundable} from "src/interfaces/ICoverageProvider.sol";
import {IEigenServiceManager} from "../interfaces/IEigenServiceManager.sol";
import {IEigenOperatorProxy} from "../interfaces/IEigenOperatorProxy.sol";
import {
    ICoverageProvider,
    CoveragePosition,
    CoverageClaim,
    CoverageClaimStatus
} from "src/interfaces/ICoverageProvider.sol";
import {ICoverageAgent} from "src/interfaces/ICoverageAgent.sol";
import {IAssetPriceOracleAndSwapper} from "src/interfaces/IAssetPriceOracleAndSwapper.sol";
import {EigenCoverageStorage, ClaimRewardDistribution} from "../EigenCoverageStorage.sol";
import {ISlashCoordinator, SlashCoordinationStatus} from "src/interfaces/ISlashCoordinator.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {ICoverageLiquidatable} from "src/interfaces/ICoverageLiquidatable.sol";
import {LibDiamond} from "src/diamond/libraries/LibDiamond.sol";

/// @title EigenCoverageProviderFacet
/// @author p-dealwis, Infinality
/// @notice Facet contract implementing ICoverageProvider interface
/// @dev This contract is designed to be called via delegatecall from EigenCoverageDiamond
contract EigenCoverageProviderFacet is EigenCoverageStorage, ICoverageProvider, ICoverageLiquidatable {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    /// @inheritdoc ICoverageProvider
    function onIsRegistered() external {
        if (coverageAgentToOperatorSetId[msg.sender] != 0) {
            revert IEigenServiceManager.CoverageAgentAlreadyRegistered();
        }

        IAllocationManagerTypes.CreateSetParams[] memory params = new IAllocationManager.CreateSetParams[](1);

        uint32 operatorSetId = ++_operatorSetCount;

        // Setup a new operator set with the default predefined strategies
        params[0] =
            IAllocationManagerTypes.CreateSetParams({operatorSetId: operatorSetId, strategies: new IStrategy[](0)});

        address[] memory redistributionRecipients = new address[](1);
        // Diamond receives slashed tokens to swap before forwarding back to coverage agent
        redistributionRecipients[0] = address(this);

        IAllocationManager(_eigenAddresses.allocationManager)
            .createRedistributingOperatorSets(address(this), params, redistributionRecipients);

        coverageAgentToOperatorSetId[msg.sender] = operatorSetId;
    }

    /// @inheritdoc ICoverageProvider
    /// @dev The caller must have the `modifyAllocations` permission for the operator.
    /// @dev The operator address must be set in data.operatorId (as bytes32).
    /// @dev The strategy is derived from assetToStrategy[data.asset].
    function createPosition(CoveragePosition memory data, bytes calldata) external returns (uint256 positionId) {
        if (data.expiryTimestamp < block.timestamp) revert TimestampInvalid(data.expiryTimestamp);
        if (data.minRate > 10000) revert MinRateInvalid(data.minRate);

        // Derive operator from operatorId and strategy from asset
        address operator = address(uint160(uint256(data.operatorId)));
        address strategy = assetToStrategy[data.asset];

        if (strategy == address(0)) {
            revert IEigenOperatorProxy.StrategyNotWhitelisted(address(0));
        }

        if (!_checkOperatorPermissions(
                operator, _eigenAddresses.allocationManager, IAllocationManager.modifyAllocations.selector
            )) revert IEigenServiceManager.NotOperatorAuthorized(operator, msg.sender);

        if (!_strategyWhitelist.contains(strategy)) {
            revert IEigenOperatorProxy.StrategyNotWhitelisted(strategy);
        }

        // Ensure strategy is in operator set and operator has non-zero allocations
        IEigenServiceManager(address(this)).ensureAllocations(operator, data.coverageAgent, strategy);

        positionId = _registerPosition(data.coverageAgent, data);
    }

    /// @inheritdoc ICoverageProvider
    /// @dev The caller must have the `modifyAllocations` permission for the operator
    function closePosition(uint256 positionId) external {
        CoveragePosition storage positionData = positions[positionId];
        address operator = address(uint160(uint256(positionData.operatorId)));
        address strategy = assetToStrategy[positionData.asset];

        if (
            _strategyWhitelist.contains(strategy)
                && !_checkOperatorPermissions(
                    operator, _eigenAddresses.allocationManager, IAllocationManager.modifyAllocations.selector
                )
        ) revert IEigenServiceManager.NotOperatorAuthorized(operator, msg.sender);

        require(
            positionData.expiryTimestamp >= block.timestamp, PositionExpired(positionId, positionData.expiryTimestamp)
        );
        positions[positionId].expiryTimestamp = block.timestamp;
        emit PositionClosed(positionId);
    }

    /// @inheritdoc ICoverageProvider
    function issueClaim(uint256 positionId, uint256 amount, uint256 duration, uint256 reward)
        external
        returns (uint256 claimId)
    {
        if (amount == 0) revert ZeroAmount();

        CoveragePosition storage positionData = positions[positionId];
        if (msg.sender != positionData.coverageAgent) {
            revert NotCoverageAgent(msg.sender, positionData.coverageAgent);
        }

        _validatePosition(positionData, amount, duration, reward);

        // Capture rewards funds from coverage agent
        SafeERC20.safeTransferFrom(
            IERC20(ICoverageAgent(positionData.coverageAgent).asset()), msg.sender, address(this), reward
        );

        address operator = address(uint160(uint256(positionData.operatorId)));
        address strategy = assetToStrategy[positionData.asset];
        // casting to 'int256' is safe because amount won't exceed max int256 for practical coverage amounts
        // forge-lint: disable-next-line(unsafe-typecast)
        _modifyCoverageForAgent(operator, strategy, positionData.coverageAgent, int256(amount));
        _checkCoverageForAgent(operator, strategy, positionData.coverageAgent);

        claimId = claims.length;
        claims.push(
            CoverageClaim({
                positionId: positionId,
                amount: amount,
                duration: duration,
                createdAt: block.timestamp,
                status: CoverageClaimStatus.Issued,
                reward: reward
            })
        );

        // Initialize the claim reward distribution
        if (positionData.refundable != Refundable.Full) {
            claimRewardDistributions[claimId] =
                ClaimRewardDistribution({amount: 0, lastDistributedTimestamp: uint32(block.timestamp)});
        }

        emit ClaimIssued(positionId, claimId, amount, duration);
    }

    /// @inheritdoc ICoverageProvider
    function reserveClaim(uint256 positionId, uint256 amount, uint256 duration, uint256 reward)
        external
        returns (uint256 claimId)
    {
        if (amount == 0) revert ZeroAmount();

        CoveragePosition storage positionData = positions[positionId];
        if (msg.sender != positionData.coverageAgent) {
            revert NotCoverageAgent(msg.sender, positionData.coverageAgent);
        }

        // Check if reservations are allowed for this position
        if (positionData.maxReservationTime == 0) {
            revert ReservationNotAllowed(positionId);
        }

        _validatePosition(positionData, amount, duration, reward);

        // Reserve coverage in the coverage map (without transferring rewards yet)
        address operator = address(uint160(uint256(positionData.operatorId)));
        address strategy = assetToStrategy[positionData.asset];
        // casting to 'int256' is safe because amount won't exceed max int256 for practical coverage amounts
        // forge-lint: disable-next-line(unsafe-typecast)
        _modifyCoverageForAgent(operator, strategy, positionData.coverageAgent, int256(amount));
        _checkCoverageForAgent(operator, strategy, positionData.coverageAgent);

        claimId = claims.length;
        claims.push(
            CoverageClaim({
                positionId: positionId,
                amount: amount,
                duration: duration,
                createdAt: block.timestamp,
                status: CoverageClaimStatus.Reserved,
                reward: reward
            })
        );

        emit ClaimReserved(positionId, claimId, amount, duration);
    }

    /// @inheritdoc ICoverageProvider
    function convertReservedClaim(uint256 claimId, uint256 amount, uint256 duration, uint256 reward) external {
        CoverageClaim storage _claim = claims[claimId];
        CoveragePosition storage positionData = positions[_claim.positionId];

        // Verify claim is in Reserved status
        if (_claim.status != CoverageClaimStatus.Reserved) revert ClaimNotReserved(claimId);

        // Verify caller is the coverage agent
        if (msg.sender != positionData.coverageAgent) {
            revert NotCoverageAgent(msg.sender, positionData.coverageAgent);
        }

        // Check reservation hasn't expired
        if (block.timestamp > _claim.createdAt + positionData.maxReservationTime) {
            revert ReservationExpired(claimId, _claim.createdAt + positionData.maxReservationTime);
        }

        // Verify amount and duration are not larger than reserved
        if (amount > _claim.amount) {
            revert AmountExceedsReserved(claimId, amount, _claim.amount);
        }
        if (duration > _claim.duration) {
            revert DurationExceedsReserved(claimId, duration, _claim.duration);
        }
        if (amount == 0) revert ZeroAmount();

        // Calculate minimum reward pro-rata based on the new amount and duration
        uint256 minimumReward = (amount * positionData.minRate * duration) / (10000 * 365 days);
        if (minimumReward > reward) revert InsufficientReward(minimumReward, reward);

        // If amount is less than reserved, update coverage tracking
        if (amount < _claim.amount) {
            address operator = address(uint160(uint256(positionData.operatorId)));
            address strategy = assetToStrategy[positionData.asset];
            // casting to 'int256' is safe because difference won't exceed max int256 for practical coverage amounts
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 releasedAmount = int256(_claim.amount - amount);
            _modifyCoverageForAgent(operator, strategy, positionData.coverageAgent, -releasedAmount);
        }

        // Capture rewards funds from coverage agent
        SafeERC20.safeTransferFrom(
            IERC20(ICoverageAgent(positionData.coverageAgent).asset()), msg.sender, address(this), reward
        );

        // Update claim to Issued status with new values
        _claim.amount = amount;
        _claim.duration = duration;
        _claim.reward = reward;
        _claim.createdAt = block.timestamp; // Reset createdAt to current time
        _claim.status = CoverageClaimStatus.Issued;

        // Initialize the claim reward distribution
        if (positionData.refundable != Refundable.Full) {
            claimRewardDistributions[claimId] =
                ClaimRewardDistribution({amount: 0, lastDistributedTimestamp: uint32(block.timestamp)});
        }

        emit ClaimIssued(_claim.positionId, claimId, amount, duration);
    }

    /// @inheritdoc ICoverageProvider
    function closeClaim(uint256 claimId) external {
        CoverageClaim storage _claim = claims[claimId];
        CoveragePosition storage positionData = positions[_claim.positionId];

        // Determine if this is a reservation that can be closed by anyone
        bool isReservation = _claim.status == CoverageClaimStatus.Reserved;
        bool isIssued = _claim.status == CoverageClaimStatus.Issued;

        // Can not close claim that are not reserved or issued
        if (!(isReservation || isIssued)) revert InvalidClaim(claimId, _claim.status);

        // Anyone can close an expired reservation or an issued claim whose duration has elapsed
        // However, only the coverage agent can close their own reserved or issued claim early
        uint256 expiresAt =
            isReservation ? _claim.createdAt + positionData.maxReservationTime : _claim.createdAt + _claim.duration;
        if (
            ((isReservation || isIssued) && (block.timestamp <= expiresAt)) && msg.sender != positionData.coverageAgent // Ensure the caller is not the coverage agent
        ) {
            revert ClaimNotExpired(claimId, expiresAt);
        }

        _modifyCoverageForAgent(
            address(uint160(uint256(positionData.operatorId))), // Operator
            assetToStrategy[positionData.asset], // Strategy
            positionData.coverageAgent,
            -int256(_claim.amount)
        );

        // Calculate and process refund if claim is closed early with refundable policy
        if (isIssued && block.timestamp < _claim.createdAt + _claim.duration) {
            uint256 originalDuration = _claim.duration;
            uint256 elapsedTime = block.timestamp - _claim.createdAt;

            // Update duration to reflect actual time coverage was active
            _claim.duration = elapsedTime;

            // Both Full and TimeWeighted use time-proportional refund on early close.
            // Full refund (100%) only applies during liquidation, not closeClaim.
            if (positionData.refundable != Refundable.None) {
                uint256 refundAmount = (_claim.reward * (originalDuration - elapsedTime)) / originalDuration;

                // Reduce reward to match what remains for captureRewards distribution,
                // preventing over-distribution of tokens that were already refunded.
                _claim.reward -= refundAmount;

                address coverageAgent = positionData.coverageAgent;
                SafeERC20.safeTransfer(IERC20(ICoverageAgent(coverageAgent).asset()), coverageAgent, refundAmount);
                ICoverageAgent(coverageAgent).onClaimRefunded(claimId, refundAmount);
            }
            // Refundable.None: no refund — operator already earned the full reward via captureRewards
        }

        _claim.status = CoverageClaimStatus.Completed;
        emit ClaimClosed(claimId);
    }

    /// @inheritdoc ICoverageLiquidatable
    function liquidateClaim(uint256 claimId, uint256 positionId) external {
        CoverageClaim storage _claim = claims[claimId];
        CoveragePosition storage oldPosition = positions[_claim.positionId];
        CoveragePosition storage newPosition = positions[positionId];

        if (_claim.positionId == positionId) revert SamePosition(positionId);
        if (oldPosition.coverageAgent != newPosition.coverageAgent) {
            revert InvalidCoverageAgent(oldPosition.coverageAgent, newPosition.coverageAgent);
        }
        if (oldPosition.asset != newPosition.asset) revert InvalidCoverageAsset(oldPosition.asset, newPosition.asset);

        address operator = address(uint160(uint256(newPosition.operatorId)));

        if (!_checkOperatorPermissions(
                operator, _eigenAddresses.allocationManager, IAllocationManager.modifyAllocations.selector
            )) revert IEigenServiceManager.NotOperatorAuthorized(operator, msg.sender);

        if (_claim.status != CoverageClaimStatus.Issued) revert InvalidClaim(claimId, _claim.status);
        if (block.timestamp > _claim.createdAt + _claim.duration) {
            revert ClaimExpired(claimId, _claim.createdAt + _claim.duration);
        }

        (, uint16 coveragePercentage) = positionBacking(_claim.positionId);
        if (coveragePercentage < _liquidationThreshold) {
            revert MeetsLiquidationThreshold(_liquidationThreshold, coveragePercentage);
        }

        // Ensure that the claim's remaining duration does not exceed the new position's expiry, the reward check can be ignored since
        // the operator has designed to take on the new claim via this liquidation process.
        require(
            _claim.createdAt + _claim.duration <= newPosition.expiryTimestamp,
            DurationExceedsExpiry(_claim.createdAt + _claim.duration, newPosition.expiryTimestamp)
        );

        // Distribute the existing rewards to old operator
        captureRewards(claimId);

        // Reduce coverage from the previous operator
        _modifyCoverageForAgent(
            address(uint160(uint256(oldPosition.operatorId))), // Operator
            assetToStrategy[oldPosition.asset], // Strategy
            oldPosition.coverageAgent,
            -int256(_claim.amount)
        );

        // Increase coverage for the new operator
        _modifyCoverageForAgent(
            operator, // Operator
            assetToStrategy[newPosition.asset], // Strategy
            newPosition.coverageAgent,
            int256(_claim.amount)
        );

        _checkCoverageForAgent(
            operator, // Operator
            assetToStrategy[newPosition.asset], // Strategy
            newPosition.coverageAgent
        );

        emit ClaimLiquidated(claimId, _claim.positionId, positionId);

        // Update the claim to the new position and reset the createdAt to the current block timestamp
        _claim.positionId = positionId;
        _claim.createdAt = block.timestamp;
    }

    /// @inheritdoc ICoverageProvider
    function slashClaims(uint256[] calldata claimIds, uint256[] calldata amounts)
        external
        returns (CoverageClaimStatus[] memory slashStatuses)
    {
        slashStatuses = new CoverageClaimStatus[](claimIds.length);
        for (uint256 i = 0; i < claimIds.length; i++) {
            CoverageClaim storage _claim = claims[claimIds[i]];
            CoveragePosition storage _position = positions[_claim.positionId];
            if (msg.sender != _position.coverageAgent) {
                revert NotCoverageAgent(msg.sender, _position.coverageAgent);
            }

            // Status needs to be Issused to start the slashing process
            if (_claim.status != CoverageClaimStatus.Issued) revert InvalidClaim(claimIds[i], _claim.status);

            // Ensure the claim cannot be slashed before after its duration has elapsed
            if (block.timestamp > _claim.createdAt + _claim.duration) {
                revert ClaimExpired(claimIds[i], _claim.createdAt + _claim.duration);
            }

            if (amounts[i] > _claim.amount) revert SlashAmountExceedsClaim(claimIds[i], amounts[i], _claim.amount);

            claimSlashAmounts[claimIds[i]] = amounts[i];

            if (_position.slashCoordinator == address(0)) {
                // If no slash coordinator is set, the coverage provider will instantly slash the coverage position.
                slashStatuses[i] = CoverageClaimStatus.Slashed;
                _initiateSlash(claimIds[i], amounts[i]);
            } else {
                slashStatuses[i] = CoverageClaimStatus.PendingSlash;
                _claim.status = CoverageClaimStatus.PendingSlash;
                SlashCoordinationStatus status =
                    ISlashCoordinator(_position.slashCoordinator).initiateSlash(address(this), claimIds[i], amounts[i]);
                if (status == SlashCoordinationStatus.Passed) {
                    _initiateSlash(claimIds[i], amounts[i]);
                } else {
                    emit ClaimSlashPending(claimIds[i], _position.slashCoordinator);
                }
            }
        }
    }

    /// @inheritdoc ICoverageProvider
    function completeSlash(uint256 claimId) external {
        CoverageClaim storage _claim = claims[claimId];
        if (_claim.status != CoverageClaimStatus.PendingSlash) revert InvalidClaim(claimId, _claim.status);
        if (
            ISlashCoordinator(positions[_claim.positionId].slashCoordinator).status(address(this), claimId)
                != SlashCoordinationStatus.Passed
        ) {
            revert SlashFailed(claimId);
        }
        _initiateSlash(claimId, claimSlashAmounts[claimId]);
    }

    /// @inheritdoc ICoverageProvider
    function repaySlashedClaim(uint256 claimId, uint256 amount) external {
        CoverageClaim storage _claim = claims[claimId];
        CoveragePosition memory positionData = positions[_claim.positionId];
        address _coverageAgent = positionData.coverageAgent;

        // Allow repayments for claims that are Slashed or already Repaid (for additional repayments)
        if (_claim.status != CoverageClaimStatus.Slashed && _claim.status != CoverageClaimStatus.Repaid) {
            revert InvalidClaim(claimId, _claim.status);
        }
        if (msg.sender != _coverageAgent) revert NotCoverageAgent(msg.sender, _coverageAgent);

        IERC20 coverageAgentAsset = IERC20(ICoverageAgent(_coverageAgent).asset());

        // Claim the funds to this contract first
        SafeERC20.safeTransferFrom(coverageAgentAsset, _coverageAgent, address(this), amount);

        if (_claim.status != CoverageClaimStatus.Repaid) {
            // Repayments amount greater than the slashed value is allowed
            if (amount >= claimSlashAmounts[claimId]) {
                claimSlashAmounts[claimId] = 0;
                _claim.status = CoverageClaimStatus.Repaid; // Update the status if the slashed claim is fully repaid
                emit ClaimRepaid(claimId);
            } else {
                claimSlashAmounts[claimId] -= amount;
            }
        }

        emit ClaimRepayment(claimId, amount);

        IRewardsCoordinator rewardsCoordinator = IRewardsCoordinator(_eigenAddresses.rewardsCoordinator);
        uint32 calculationInterval = rewardsCoordinator.CALCULATION_INTERVAL_SECONDS();

        // Pass 0 for startTimestamp to auto-calculate using the next interval
        IEigenServiceManager(address(this))
            .submitOperatorReward(
                address(uint160(uint256(positionData.operatorId))),
                IStrategy(assetToStrategy[positionData.asset]),
                coverageAgentAsset,
                amount,
                0, // Auto-calculate startTimestamp
                calculationInterval,
                "Slash Repayment"
            );
    }

    /// ============ Rewards ============

    /// @inheritdoc ICoverageProvider
    function captureRewards(uint256 claimId)
        public
        returns (uint256 amount, uint32 resolvedDuration, uint32 resolvedDistributionStartTime)
    {
        CoverageClaim memory _claim = claims[claimId];
        CoveragePosition memory _position = positions[_claim.positionId];
        ClaimRewardDistribution memory _claimRewardDistribution = claimRewardDistributions[claimId];
        address operator = address(uint160(uint256(_position.operatorId)));
        address strategy = assetToStrategy[_position.asset];

        uint32 distributionStartTime = _claimRewardDistribution.lastDistributedTimestamp;

        // Calculate the amount of time that has elapsed since the last distribution for the claim
        uint32 elapsedDuration = uint32(
            _min(block.timestamp - distributionStartTime, _claim.duration + _claim.createdAt - distributionStartTime)
        );

        if (elapsedDuration == 0) {
            return (0, 0, distributionStartTime);
        }

        if (_position.refundable == Refundable.None) {
            // No refund possible — operator earned the full reward on issuance
            amount = _claim.reward - _claimRewardDistribution.amount;
            claimRewardDistributions[claimId].amount += amount;
            claimRewardDistributions[claimId].lastDistributedTimestamp = uint32(block.timestamp);
        } else if (_position.refundable == Refundable.TimeWeighted) {
            uint256 claimableReward =
                _min(block.timestamp - _claim.createdAt, _claim.duration) * _claim.reward / _claim.duration;
            amount = claimableReward - _claimRewardDistribution.amount;
            claimRewardDistributions[claimId].amount += amount;
            claimRewardDistributions[claimId].lastDistributedTimestamp = uint32(block.timestamp);
        } else if (_position.refundable == Refundable.Full && _claim.status == CoverageClaimStatus.Completed) {
            amount = _claim.reward;
        } else {
            return (0, 0, distributionStartTime);
        }

        // Guard against submitting a zero-amount reward (e.g. already fully distributed,
        // or reward was reduced to 0 after refund on early close)
        if (amount == 0) {
            return (0, 0, distributionStartTime);
        }

        IERC20 coverageAsset = IERC20(ICoverageAgent(_position.coverageAgent).asset());

        (resolvedDistributionStartTime, resolvedDuration) = IEigenServiceManager(address(this))
            .submitOperatorReward(
                operator,
                IStrategy(strategy),
                coverageAsset,
                amount,
                distributionStartTime,
                elapsedDuration,
                "Coverage reward"
            );

        return (amount, resolvedDuration, resolvedDistributionStartTime);
    }

    /// @inheritdoc ICoverageLiquidatable
    function setLiquidationThreshold(uint16 threshold) external {
        LibDiamond.enforceIsContractOwner();
        if (threshold > 10000) revert ThresholdExceedsMax(10000, threshold);
        _liquidationThreshold = threshold;
    }

    /// @inheritdoc ICoverageLiquidatable
    function setCoverageThreshold(bytes32 operatorId, uint16 coverageThreshold_) external {
        address operator = address(uint160(uint256(operatorId)));
        if (coverageThreshold_ > 10000) revert ThresholdExceedsMax(10000, coverageThreshold_);
        if (!_checkOperatorPermissions(
                operator, _eigenAddresses.allocationManager, IAllocationManager.modifyAllocations.selector
            )) revert IEigenServiceManager.NotOperatorAuthorized(operator, msg.sender);

        operators[operator].coverageThreshold = coverageThreshold_;
    }

    /// ============ Discovery ============

    /// @inheritdoc ICoverageProvider
    function position(uint256 positionId) external view returns (CoveragePosition memory) {
        return positions[positionId];
    }

    /// @inheritdoc ICoverageProvider
    function positionMaxAmount(uint256 positionId) external view returns (uint256 maxAmount) {
        CoveragePosition memory _position = positions[positionId];
        address operator = address(uint160(uint256(_position.operatorId)));
        address strategy = assetToStrategy[_position.asset];

        uint256 allocatedCoverage =
            IEigenServiceManager(address(this)).coverageAllocated(operator, strategy, _position.coverageAgent);
        uint256 totalCoverageByOperator = _totalCoverageByOperatorStrategy(operator, strategy, _position.coverageAgent);
        if (allocatedCoverage > totalCoverageByOperator) {
            maxAmount = allocatedCoverage - totalCoverageByOperator;
        }
    }

    /// @inheritdoc ICoverageProvider
    function claim(uint256 claimId) external view returns (CoverageClaim memory data) {
        return claims[claimId];
    }

    /// @inheritdoc ICoverageProvider
    function positionBacking(uint256 positionId) public view returns (int256 backing, uint16 coveragePercentage) {
        CoveragePosition memory _position = positions[positionId];
        address operator = address(uint160(uint256(_position.operatorId)));
        address strategy = assetToStrategy[_position.asset];
        (backing, coveragePercentage) = _coverageBackingAmount(operator, strategy, _position.coverageAgent);
        return (backing, coveragePercentage);
    }

    /// @inheritdoc ICoverageProvider
    function claimTotalSlashAmount(uint256 claimId) external view returns (uint256 slashAmount) {
        return claimSlashAmounts[claimId];
    }

    /// @inheritdoc ICoverageLiquidatable
    function coverageThreshold(bytes32 operatorId) external view returns (uint16) {
        return operators[address(uint160(uint256(operatorId)))].coverageThreshold;
    }

    /// @inheritdoc ICoverageLiquidatable
    function liquidationThreshold() external view returns (uint16 threshold) {
        return _liquidationThreshold;
    }

    /// @inheritdoc ICoverageProvider
    function providerTypeId() external pure returns (uint256) {
        return 20;
    }

    /// ============ Internal functions ============ //

    /// @notice Validates the claim parameters meet the position requirements
    function _validatePosition(CoveragePosition memory data, uint256 amount, uint256 duration, uint256 reward)
        private
        view
    {
        uint256 minimumReward = (amount * data.minRate * duration) / (10000 * 365 days);
        if (minimumReward > reward) revert InsufficientReward(minimumReward, reward);
        if (!_strategyWhitelist.contains(assetToStrategy[data.asset])) {
            revert IEigenOperatorProxy.StrategyNotWhitelisted(assetToStrategy[data.asset]);
        }

        if (data.maxDuration > 0 && duration > data.maxDuration) revert DurationExceedsMax(data.maxDuration, duration);
        require(
            duration + block.timestamp <= data.expiryTimestamp,
            DurationExceedsExpiry(data.expiryTimestamp, duration + block.timestamp)
        );
    }

    /// @notice Modifies the operator's coverage tracking map for a strategy and coverage agent
    /// @param operator The operator address
    /// @param strategy The strategy address
    /// @param coverageAgent The coverage agent address
    /// @param amount Positive to increase coverage, negative to decrease coverage
    function _modifyCoverageForAgent(address operator, address strategy, address coverageAgent, int256 amount) private {
        EnumerableMap.AddressToUintMap storage coverageMap = operators[operator].coverageStrategies[strategy];

        // Get the current value, or 0 if the key doesn't exist
        (bool exists, uint256 currentValue) = coverageMap.tryGet(coverageAgent);
        uint256 current = exists ? currentValue : 0;

        uint256 newValue;
        if (amount >= 0) {
            // casting to 'uint256' is safe because we've checked amount >= 0
            // forge-lint: disable-next-line(unsafe-typecast)
            newValue = current + uint256(amount);
        } else {
            // casting to 'uint256' is safe because we've checked amount < 0, so -amount is positive
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 decrease = uint256(-amount);
            newValue = current >= decrease ? current - decrease : 0;
        }

        coverageMap.set(coverageAgent, newValue);
    }

    /// @notice Checks if the operator has sufficient coverage available for the coverage agent
    /// @dev Reverts only if the operator does not have enough allocated to safely cover the agent.
    function _checkCoverageForAgent(address operator, address strategy, address coverageAgent) private view {
        (int256 backing, uint16 coveragePercentage) = _coverageBackingAmount(operator, strategy, coverageAgent);

        if (coveragePercentage > operators[operator].coverageThreshold || backing < 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            revert InsufficientCoverageAvailable(uint256(-backing), coveragePercentage);
        }
    }

    /// @notice Calculate the coverage backing for an operator, strategy, and coverage agent.
    /// @dev Returns positive value if fully backed, negative value if there's a deficit.
    /// @param operator The operator address.
    /// @param strategy The strategy address.
    /// @param coverageAgent The coverage agent address.
    /// @return backing The coverage backing (positive = fully backed, negative = deficit).
    /// @return coveragePercentage The utilization percentage of the operator's allocated coverage where 10000 = 100%.
    function _coverageBackingAmount(address operator, address strategy, address coverageAgent)
        private
        view
        returns (int256 backing, uint16 coveragePercentage)
    {
        uint256 totalAllocatedCoverage =
            IEigenServiceManager(address(this)).coverageAllocated(operator, strategy, coverageAgent);
        uint256 totalCoverageByOperator = _totalCoverageByOperatorStrategy(operator, strategy, coverageAgent);

        // Calculate backing: positive = fully backed, negative = deficit
        // casting to 'int256' is safe because both won't possibly hold more than 2^256 - 1
        // forge-lint: disable-next-line(unsafe-typecast)
        backing = int256(totalAllocatedCoverage) - int256(totalCoverageByOperator);
        // Calculate coverage utilization: percentage of allocated coverage being used by claims
        if (totalAllocatedCoverage == 0) {
            coveragePercentage = type(uint16).max;
        } else {
            // casting to 'uint16' is safe because utilization percentage won't realistically exceed type(uint16).max
            // forge-lint: disable-next-line(unsafe-typecast)
            coveragePercentage = uint16((totalCoverageByOperator * 10000) / totalAllocatedCoverage);
        }
    }

    /// @notice Returns the total coverage by an operator for a strategy in the operators asset
    function _totalCoverageByOperatorStrategy(address operator, address strategy, address coverageAgent)
        private
        view
        returns (uint256)
    {
        (bool exists, uint256 value) = operators[operator].coverageStrategies[strategy].tryGet(coverageAgent);
        if (exists) {
            return value;
        }
        return 0;
    }

    function _registerPosition(address coverageAgent, CoveragePosition memory data)
        private
        returns (uint256 positionId)
    {
        positions.push(data);
        positionId = positions.length - 1;

        emit PositionCreated(positionId);

        // Notify the coverage agent that the position has been registered
        ICoverageAgent(coverageAgent).onRegisterPosition(positionId);
    }

    function _initiateSlash(uint256 claimId, uint256 amount) private {
        CoverageClaim storage _claim = claims[claimId];
        CoveragePosition storage _position = positions[_claim.positionId];

        if (_claim.status == CoverageClaimStatus.Slashed) revert InvalidClaim(claimId, _claim.status);

        address operator = address(uint160(uint256(_position.operatorId)));
        address strategy = assetToStrategy[_position.asset];

        // Get balance of strategy asset in this address
        address strategyAsset = address(IStrategy(strategy).underlyingToken());
        uint256 openingStrategyAssetBalance = IERC20(strategyAsset).balanceOf(address(this));

        // Slash the operator through EigenLayer and claim redistributed tokens
        IEigenServiceManager(address(this)).slashOperator(operator, strategy, _position.coverageAgent, amount);

        // Swap the slashed strategy asset to the coverage agent's asset
        IAssetPriceOracleAndSwapper(address(this))
            .swapForOutput(amount, ICoverageAgent(_position.coverageAgent).asset(), _position.asset);

        // Transfer swapped tokens to coverage agent
        SafeERC20.safeTransfer(IERC20(ICoverageAgent(_position.coverageAgent).asset()), _position.coverageAgent, amount);

        _claim.status = CoverageClaimStatus.Slashed;
        ICoverageAgent(_position.coverageAgent).onSlashCompleted(claimId, amount);
        emit ClaimSlashed(claimId, amount);

        _modifyCoverageForAgent(
            operator,
            strategy,
            _position.coverageAgent,
            // casting to 'int256' is safe because amount won't exceed max int256 for practical slash amounts
            // forge-lint: disable-next-line(unsafe-typecast)
            -int256(amount)
        );

        // Calculate the difference in strategy asset balance
        uint256 closingStrategyAssetBalance = IERC20(strategyAsset).balanceOf(address(this));

        // If the closing strategy asset balance is less than the opening strategy asset balance then more than
        // the slashed amount was used to swap for the coverage agent's asset. This is unlikely if the swapper is working as
        // intended but is stil an edge case that needs to be handled.
        if (closingStrategyAssetBalance < openingStrategyAssetBalance) revert SlashFailed(claimId);

        // Redistribute any remaining amount of staked assets back to the operator as a reward
        uint256 difference = closingStrategyAssetBalance - openingStrategyAssetBalance;

        if (difference > 0) {
            IRewardsCoordinator rewardsCoordinator = IRewardsCoordinator(_eigenAddresses.rewardsCoordinator);
            uint32 calculationInterval = rewardsCoordinator.CALCULATION_INTERVAL_SECONDS();

            // Pass 0 for startTimestamp to auto-calculate using the next interval
            IEigenServiceManager(address(this))
                .submitOperatorReward(
                    operator,
                    IStrategy(strategy),
                    IERC20(strategyAsset),
                    difference,
                    0, // Auto-calculate startTimestamp
                    calculationInterval,
                    "Slash Refund"
                );
        }
    }

    function _checkOperatorPermissions(address operator, address target, bytes4 selector) private returns (bool) {
        return
            IPermissionController(_eigenAddresses.permissionController).canCall(operator, msg.sender, target, selector);
    }

    /// @notice Returns the minimum of two uint256 values
    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
