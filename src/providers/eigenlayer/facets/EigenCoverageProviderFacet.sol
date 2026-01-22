// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EnumerableMap} from "@openzeppelin-v5/contracts/utils/structs/EnumerableMap.sol";
import {IAllocationManager, IAllocationManagerTypes} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";
import {IPermissionController} from "eigenlayer-contracts/interfaces/IPermissionController.sol";
import {Refundable} from "src/interfaces/ICoverageProvider.sol";
import {
    IEigenServiceManager,
    CreatePositionAddtionalData,
    EigenCoveragePosition
} from "../interfaces/IEigenServiceManager.sol";
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
import {ISlashCoordinator, SlashStatus} from "src/interfaces/ISlashCoordinator.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";

/// @title EigenCoverageProviderFacet
/// @author p-dealwis, Infinality
/// @notice Facet contract implementing ICoverageProvider interface
/// @dev This contract is designed to be called via delegatecall from EigenCoverageDiamond
contract EigenCoverageProviderFacet is EigenCoverageStorage, ICoverageProvider {
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
    /// @dev The caller must have the `modifyAllocations` permission for the operator
    function createPosition(CoveragePosition memory data, bytes calldata additionalData)
        external
        returns (uint256 positionId)
    {
        if (data.expiryTimestamp < block.timestamp) revert TimestampInvalid(data.expiryTimestamp);
        if (data.minRate > 10000) revert MinRateInvalid(data.minRate);

        CreatePositionAddtionalData memory createPositionAddtionalData =
            abi.decode(additionalData, (CreatePositionAddtionalData));

        if (!_checkOperatorPermissions(
                createPositionAddtionalData.operator,
                _eigenAddresses.allocationManager,
                IAllocationManager.modifyAllocations.selector
            )) revert IEigenServiceManager.NotOperatorAuthorized(createPositionAddtionalData.operator, msg.sender);

        if (!_strategyWhitelist.contains(createPositionAddtionalData.strategy)) {
            revert IEigenOperatorProxy.StrategyNotWhitelisted(createPositionAddtionalData.strategy);
        }

        if (address(IStrategy(createPositionAddtionalData.strategy).underlyingToken()) != data.asset) {
            revert IEigenServiceManager.InvalidAsset(createPositionAddtionalData.strategy, data.asset);
        }

        // Ensure strategy is in operator set and operator has non-zero allocations
        IEigenServiceManager(address(this))
            .ensureAllocations(
                createPositionAddtionalData.operator, data.coverageAgent, createPositionAddtionalData.strategy
            );

        positionId = _registerPosition(data.coverageAgent, data, createPositionAddtionalData);
    }

    /// @inheritdoc ICoverageProvider
    /// @dev The caller must have the `modifyAllocations` permission for the operator
    function closePosition(uint256 positionId) external {
        EigenCoveragePosition storage positionData = positions[positionId];

        if (!_checkOperatorPermissions(
                positionData.operator, _eigenAddresses.allocationManager, IAllocationManager.modifyAllocations.selector
            )) revert IEigenServiceManager.NotOperatorAuthorized(positionData.operator, msg.sender);

        require(positionData.data.expiryTimestamp >= block.timestamp, PositionExpired(positionId));
        positions[positionId].data.expiryTimestamp = block.timestamp;
        emit PositionClosed(positionId);
    }

    /// @inheritdoc ICoverageProvider
    function issueClaim(uint256 positionId, uint256 amount, uint256 duration, uint256 reward)
        external
        returns (uint256 claimId)
    {
        if (amount == 0) revert InvalidAmount();

        EigenCoveragePosition storage positionData = positions[positionId];
        if (msg.sender != positionData.data.coverageAgent) {
            revert NotCoverageAgent(msg.sender, positionData.data.coverageAgent);
        }

        _validatePosition(positionData.data, amount, duration, reward);

        // Capture rewards funds from coverage agent
        bool success = IERC20(ICoverageAgent(positionData.data.coverageAgent).asset())
            .transferFrom(msg.sender, address(this), reward);
        if (!success) revert RewardTransferFailed();

        address strategy = assetToStrategy[positionData.data.asset];
        _modifyCoverageForAgent(positionData.operator, strategy, positionData.data.coverageAgent, int256(amount));
        _checkCoverageForAgent(positionData.operator, strategy, positionData.data.coverageAgent);

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
        if (positionData.data.refundable != Refundable.Full) {
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
        if (amount == 0) revert InvalidAmount();

        EigenCoveragePosition storage positionData = positions[positionId];
        if (msg.sender != positionData.data.coverageAgent) {
            revert NotCoverageAgent(msg.sender, positionData.data.coverageAgent);
        }

        // Check if reservations are allowed for this position
        if (positionData.data.maxReservationTime == 0) {
            revert ReservationNotAllowed(positionId);
        }

        _validatePosition(positionData.data, amount, duration, reward);

        // Reserve coverage in the coverage map (without transferring rewards yet)
        address strategy = assetToStrategy[positionData.data.asset];
        _modifyCoverageForAgent(positionData.operator, strategy, positionData.data.coverageAgent, int256(amount));
        _checkCoverageForAgent(positionData.operator, strategy, positionData.data.coverageAgent);

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
        EigenCoveragePosition storage positionData = positions[_claim.positionId];

        // Verify claim is in Reserved status
        if (_claim.status != CoverageClaimStatus.Reserved) revert ClaimNotReserved(claimId);

        // Verify caller is the coverage agent
        if (msg.sender != positionData.data.coverageAgent) {
            revert NotCoverageAgent(msg.sender, positionData.data.coverageAgent);
        }

        // Check reservation hasn't expired
        if (block.timestamp > _claim.createdAt + positionData.data.maxReservationTime) {
            revert ReservationExpired(claimId);
        }

        // Verify amount and duration are not larger than reserved
        if (amount > _claim.amount) {
            revert AmountExceedsReserved(claimId, amount, _claim.amount);
        }
        if (duration > _claim.duration) {
            revert DurationExceedsReserved(claimId, duration, _claim.duration);
        }
        if (amount == 0) revert InvalidAmount();

        // Calculate minimum reward pro-rata based on the new amount and duration
        uint256 minimumReward = (amount * positionData.data.minRate * duration) / (10000 * 365 days);
        if (minimumReward > reward) revert InsufficientReward(minimumReward, reward);

        // If amount is less than reserved, update coverage tracking
        if (amount < _claim.amount) {
            address strategy = assetToStrategy[positionData.data.asset];
            int256 releasedAmount = int256(_claim.amount - amount);
            _modifyCoverageForAgent(positionData.operator, strategy, positionData.data.coverageAgent, -releasedAmount);
        }

        // Capture rewards funds from coverage agent
        bool success = IERC20(ICoverageAgent(positionData.data.coverageAgent).asset())
            .transferFrom(msg.sender, address(this), reward);
        if (!success) revert RewardTransferFailed();

        // Update claim to Issued status with new values
        _claim.amount = amount;
        _claim.duration = duration;
        _claim.reward = reward;
        _claim.createdAt = block.timestamp; // Reset createdAt to current time
        _claim.status = CoverageClaimStatus.Issued;

        // Initialize the claim reward distribution
        if (positionData.data.refundable != Refundable.Full) {
            claimRewardDistributions[claimId] =
                ClaimRewardDistribution({amount: 0, lastDistributedTimestamp: uint32(block.timestamp)});
        }

        emit ClaimIssued(_claim.positionId, claimId, amount, duration);
    }

    /// @inheritdoc ICoverageProvider
    function closeClaim(uint256 claimId) external {
        CoverageClaim storage _claim = claims[claimId];
        EigenCoveragePosition storage positionData = positions[_claim.positionId];

        // Determine if this is a reservation that can be closed by anyone
        bool isReservation = _claim.status == CoverageClaimStatus.Reserved;
        bool isIssued = _claim.status == CoverageClaimStatus.Issued;

        if (!isReservation && !isIssued) revert InvalidClaim(claimId);

        bool isCoverageAgent = msg.sender == positionData.data.coverageAgent;
        bool reservationExpired =
            isReservation && (block.timestamp > _claim.createdAt + positionData.data.maxReservationTime);
        bool claimDurationElapsed = isIssued && (block.timestamp >= _claim.createdAt + _claim.duration);

        // Anyone can close an expired reservation or an issued claim whose duration has elapsed
        // Only the coverage agent can close their own claim early
        if (!reservationExpired && !claimDurationElapsed && !isCoverageAgent) {
            if (isReservation) {
                revert ClaimNotExpired(claimId);
            }
            revert NotCoverageAgent(msg.sender, positionData.data.coverageAgent);
        }

        // Release the coverage from the coverage map
        address strategy = assetToStrategy[positionData.data.asset];
        _modifyCoverageForAgent(positionData.operator, strategy, positionData.data.coverageAgent, -int256(_claim.amount));

        // Update duration to reflect actual time coverage was active (only if closed early by coverage agent)
        if (isIssued && block.timestamp < _claim.createdAt + _claim.duration) {
            _claim.duration = block.timestamp - _claim.createdAt;
        }

        _claim.status = CoverageClaimStatus.Completed;
        emit ClaimClosed(claimId);
    }

    /// @inheritdoc ICoverageProvider
    function liquidateClaim(uint256) external pure {
        //TODO: Implement liquidateClaim
        revert IEigenServiceManager.NotImplemented();
    }

    /// @inheritdoc ICoverageProvider
    function slashClaims(uint256[] calldata claimIds, uint256[] calldata amounts)
        external
        returns (CoverageClaimStatus[] memory slashStatuses)
    {
        slashStatuses = new CoverageClaimStatus[](claimIds.length);
        for (uint256 i = 0; i < claimIds.length; i++) {
            CoverageClaim storage _claim = claims[claimIds[i]];
            EigenCoveragePosition storage _position = positions[_claim.positionId];
            if (msg.sender != _position.data.coverageAgent) {
                revert NotCoverageAgent(msg.sender, _position.data.coverageAgent);
            }

            // Status needs to be Issused to start the slashing process
            if (_claim.status != CoverageClaimStatus.Issued) revert InvalidClaim(claimIds[i]);

            // Ensure the claim cannot be slashed before after its duration has elapsed
            if (block.timestamp > _claim.createdAt + _claim.duration) {
                revert TimestampInvalid(_claim.createdAt + _claim.duration);
            }

            if (amounts[i] > _claim.amount) revert SlashAmountExceedsClaim(claimIds[i], amounts[i], _claim.amount);

            claimSlashAmounts[claimIds[i]] = amounts[i];

            if (_position.data.slashCoordinator == address(0)) {
                // If no slash coordinator is set, the coverage provider will instantly slash the coverage position.
                slashStatuses[i] = CoverageClaimStatus.Slashed;
                _initiateSlash(claimIds[i], amounts[i]);
            } else {
                slashStatuses[i] = CoverageClaimStatus.PendingSlash;
                _claim.status = CoverageClaimStatus.PendingSlash;
                ISlashCoordinator(_position.data.slashCoordinator).initiateSlash(claimIds[i], amounts[i]);
                emit ClaimSlashPending(claimIds[i], _position.data.slashCoordinator);
            }
        }
    }

    /// @inheritdoc ICoverageProvider
    function completeSlash(uint256 claimId) external {
        CoverageClaim storage _claim = claims[claimId];
        if (_claim.status != CoverageClaimStatus.PendingSlash) revert InvalidClaim(claimId);
        if (
            ISlashCoordinator(positions[_claim.positionId].data.slashCoordinator).status(claimId)
                != SlashStatus.Completed
        ) {
            revert SlashFailed(claimId);
        }
        _initiateSlash(claimId, claimSlashAmounts[claimId]);
    }

    /// @inheritdoc ICoverageProvider
    function position(uint256 positionId) external view returns (CoveragePosition memory) {
        return positions[positionId].data;
    }

    /// @inheritdoc ICoverageProvider
    function positionMaxAmount(uint256 positionId) external view returns (uint256 maxAmount) {
        EigenCoveragePosition memory _position = positions[positionId];

        uint256 allocatedCoverage = IEigenServiceManager(address(this))
            .coverageAllocated(_position.operator, _position.strategy, _position.data.coverageAgent);
        uint256 totalCoverageByOperator =
            _totalCoverageByOperatorStrategy(_position.operator, _position.strategy, _position.data.coverageAgent);
        if (allocatedCoverage > totalCoverageByOperator) {
            maxAmount = allocatedCoverage - totalCoverageByOperator;
        }
    }

    /// @inheritdoc ICoverageProvider
    function claim(uint256 claimId) external view returns (CoverageClaim memory data) {
        return claims[claimId];
    }

    /// @inheritdoc ICoverageProvider
    function claimBacking(uint256 claimId) external view returns (int256 backing) {
        EigenCoveragePosition memory _position = positions[claims[claimId].positionId];
        return _coverageBackingAmount(_position.operator, _position.strategy, _position.data.coverageAgent);
    }

    /// @inheritdoc ICoverageProvider
    function claimTotalSlashAmount(uint256 claimId) external view returns (uint256 slashAmount) {
        return claimSlashAmounts[claimId];
    }

    /// ============ Internal functions ============ //

    /// @notice Validates the claim parameters meet the position requirements
    function _validatePosition(CoveragePosition memory data, uint256 amount, uint256 duration, uint256 reward)
        private
        view
    {
        uint256 minimumReward = (amount * data.minRate * duration) / (10000 * 365 days);
        if (minimumReward > reward) revert InsufficientReward(minimumReward, reward);

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
            newValue = current + uint256(amount);
        } else {
            uint256 decrease = uint256(-amount);
            newValue = current >= decrease ? current - decrease : 0;
        }

        coverageMap.set(coverageAgent, newValue);
    }

    /// @notice Checks if the operator has sufficient coverage available for the coverage agent
    /// @dev Reverts only if the operator does not have enough allocated to safely cover the agent.
    function _checkCoverageForAgent(address operator, address strategy, address coverageAgent) private view {
        int256 backing = _coverageBackingAmount(operator, strategy, coverageAgent);
        // Check to see if agent has a deficit of coverage (negative backing)
        if (backing < 0) {
            // casting to 'uint256' is safe because backing is negative and we are converting it to a positive value
            // forge-lint: disable-next-line(unsafe-typecast)
            revert InsufficientCoverageAvailable(uint256(-backing));
        }
    }

    /// @notice Calculate the coverage backing for an operator, strategy, and coverage agent.
    /// @dev Returns positive value if fully backed, negative value if there's a deficit.
    /// @param operator The operator address.
    /// @param strategy The strategy address.
    /// @param coverageAgent The coverage agent address.
    /// @return backing The coverage backing (positive = fully backed, negative = deficit).
    function _coverageBackingAmount(address operator, address strategy, address coverageAgent)
        private
        view
        returns (int256 backing)
    {
        uint256 totalAllocatedCoverage =
            IEigenServiceManager(address(this)).coverageAllocated(operator, strategy, coverageAgent);
        uint256 totalCoverageByOperator = _totalCoverageByOperatorStrategy(operator, strategy, coverageAgent);

        // Calculate backing: positive = fully backed, negative = deficit
        // casting to 'int256' is safe because both won't possibly hold more than 2^256 - 1
        // forge-lint: disable-next-line(unsafe-typecast)
        backing = int256(totalAllocatedCoverage) - int256(totalCoverageByOperator);
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

    function _registerPosition(
        address coverageAgent,
        CoveragePosition memory data,
        CreatePositionAddtionalData memory createPositionAddtionalData
    ) private returns (uint256 positionId) {
        positions.push(
            EigenCoveragePosition({
                data: data,
                operator: createPositionAddtionalData.operator,
                strategy: createPositionAddtionalData.strategy
            })
        );
        positionId = positions.length - 1;

        emit PositionCreated(positionId);

        // Notify the coverage agent that the position has been registered
        ICoverageAgent(coverageAgent).onRegisterPosition(positionId);
    }

    function _initiateSlash(uint256 claimId, uint256 amount) private {
        CoverageClaim storage _claim = claims[claimId];
        EigenCoveragePosition storage eigenPosition = positions[_claim.positionId];
        CoveragePosition storage _position = eigenPosition.data;

        // Get balance of strategy asset in this address
        address strategyAsset = address(IStrategy(eigenPosition.strategy).underlyingToken());
        uint256 openingStrategyAssetBalance = IERC20(strategyAsset).balanceOf(address(this));

        // Slash the operator through EigenLayer and claim redistributed tokens
        IEigenServiceManager(address(this))
            .slashOperator(eigenPosition.operator, eigenPosition.strategy, _position.coverageAgent, amount);

        // Swap the slashed strategy asset to the coverage agent's asset
        IAssetPriceOracleAndSwapper(address(this))
            .swapForOutput(amount, ICoverageAgent(_position.coverageAgent).asset(), _position.asset);

        // Transfer swapped tokens to coverage agent
        bool success = IERC20(ICoverageAgent(_position.coverageAgent).asset()).transfer(_position.coverageAgent, amount);
        if (!success) revert SlashFailed(claimId);

        _claim.status = CoverageClaimStatus.Slashed;
        ICoverageAgent(_position.coverageAgent).onSlashCompleted(claimId, amount);
        emit ClaimSlashed(claimId, amount);

        _modifyCoverageForAgent(eigenPosition.operator, eigenPosition.strategy, _position.coverageAgent, -int256(amount));

        // Calculate the difference in strategy asset balance
        uint256 closingStrategyAssetBalance = IERC20(strategyAsset).balanceOf(address(this));

        // If the closing strategy asset balance is less than the opening strategy asset balance then more than
        // the slashed amount was used to swap for the coverage agent's asset. This is unlikely but is stil an edge case
        // that needs to be handled.
        if (closingStrategyAssetBalance < openingStrategyAssetBalance) revert SlashFailed(claimId);

        // Redistribute any remaining amount of staked assets back to the operator as a reward
        uint256 difference = closingStrategyAssetBalance - openingStrategyAssetBalance;

        if (difference > 0) {
            IRewardsCoordinator rewardsCoordinator = IRewardsCoordinator(_eigenAddresses.rewardsCoordinator);
            uint32 calculationInterval = rewardsCoordinator.CALCULATION_INTERVAL_SECONDS();

            // Pass 0 for startTimestamp to auto-calculate using the next interval
            IEigenServiceManager(address(this))
                .submitOperatorReward(
                    eigenPosition.operator,
                    IStrategy(eigenPosition.strategy),
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
}

