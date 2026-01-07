// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NotImplemented} from "../Errors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EnumerableMap} from "@openzeppelin-v5/contracts/utils/structs/EnumerableMap.sol";
import {IAllocationManager, IAllocationManagerTypes} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";
import {OperatorSet} from "eigenlayer-contracts/libraries/OperatorSetLib.sol";
import {IPermissionController} from "eigenlayer-contracts/interfaces/IPermissionController.sol";
import {Refundable} from "src/interfaces/ICoverageProvider.sol";
import {CoverageAgentAlreadyRegistered, NotOperatorAuthorized, InvalidAsset} from "../Errors.sol";
import {
    IEigenServiceManager,
    CreatePositionAddtionalData,
    EigenCoveragePosition
} from "../interfaces/IEigenServiceManager.sol";
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

/// @title EigenCoverageProviderFacet
/// @author p-dealwis, Infinality
/// @notice Facet contract implementing ICoverageProvider interface
/// @dev This contract is designed to be called via delegatecall from EigenCoverageDiamond
contract EigenCoverageProviderFacet is EigenCoverageStorage, ICoverageProvider {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    /// @inheritdoc ICoverageProvider
    function onIsRegistered() external {
        if (coverageAgentToOperatorSetId[msg.sender] != 0) revert CoverageAgentAlreadyRegistered();

        IAllocationManagerTypes.CreateSetParams[] memory params = new IAllocationManager.CreateSetParams[](1);

        uint32 operatorSetId = ++_operatorSetCount;

        // Setup a new operator set with the default predefined strategies
        params[0] =
            IAllocationManagerTypes.CreateSetParams({operatorSetId: operatorSetId, strategies: new IStrategy[](0)});

        address[] memory redistributionRecipients = new address[](1);
        redistributionRecipients[0] = address(this); // Diamond receives slashed tokens to swap before forwarding

        IAllocationManager(_eigenAddresses.allocationManager)
            .createRedistributingOperatorSets(address(this), params, redistributionRecipients);

        coverageAgentToOperatorSetId[msg.sender] = operatorSetId;
    }

    /// @inheritdoc ICoverageProvider
    /// @dev The caller must have the `modifyAllocations` permission for the operator
    function createPosition(address coverageAgent, CoveragePosition memory data, bytes calldata additionalData)
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
            )) revert NotOperatorAuthorized(createPositionAddtionalData.operator, msg.sender);

        if (!strategyWhitelist[createPositionAddtionalData.strategy]) {
            revert IEigenServiceManager.StrategyNotWhitelisted(createPositionAddtionalData.strategy);
        }

        if (address(IStrategy(createPositionAddtionalData.strategy).underlyingToken()) != data.asset) {
            revert InvalidAsset(createPositionAddtionalData.strategy, data.asset);
        }

        // Ensure strategy is in operator set and operator has non-zero allocations
        IEigenServiceManager(address(this))
            .ensureAllocations(
                coverageAgent, createPositionAddtionalData.operator, createPositionAddtionalData.strategy
            );

        positionId = _registerPosition(coverageAgent, data, createPositionAddtionalData);
    }

    /// @inheritdoc ICoverageProvider
    /// @dev The caller must have the `modifyAllocations` permission for the operator
    function closePosition(uint256 positionId) external {
        EigenCoveragePosition storage positionData = positions[positionId];

        if (!_checkOperatorPermissions(
                positionData.operator, _eigenAddresses.allocationManager, IAllocationManager.modifyAllocations.selector
            )) revert NotOperatorAuthorized(positionData.operator, msg.sender);

        positions[positionId].data.expiryTimestamp = block.timestamp;
        emit PositionClosed(positionId);
    }

    /// @inheritdoc ICoverageProvider
    function claimCoverage(uint256 positionId, uint256 amount, uint256 duration, uint256 reward)
        external
        returns (uint256 claimId)
    {
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
        _updateCoverageMap(positionData.operator, strategy, positionData.data.coverageAgent, amount);
        _checkCoverage(positionData.operator, strategy, positionData.data.coverageAgent);

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
    function liquidateClaim(uint256) external pure {
        //TODO: Implement liquidateClaim
        revert NotImplemented();
    }

    /// @inheritdoc ICoverageProvider
    function completeClaims(uint256 claimId) external {
        CoverageClaim storage _claim = claims[claimId];
        if (_claim.status != CoverageClaimStatus.Issued) revert InvalidClaim(claimId);
        // Ensure the claim cannot be completed before its duration has elapsed
        if (block.timestamp < _claim.createdAt + _claim.duration) {
            revert TimestampInvalid(_claim.createdAt + _claim.duration);
        }

        _claim.status = CoverageClaimStatus.Completed;
        emit ClaimCompleted(claimId);
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

        uint256 allocatedCoverage =
            _totalAllocatedValueToCoverageAgent(_position.operator, _position.strategy, _position.data.coverageAgent);
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
    function claimDeficit(uint256 claimId) external view returns (uint256 deficit) {
        EigenCoveragePosition memory _position = positions[claims[claimId].positionId];
        return _coverageDeficitAmount(_position.operator, _position.strategy, _position.data.coverageAgent);
    }

    /// ============ Internal functions ============ //

    /// @notice Validates the claim parameters meet the position requirements
    function _validatePosition(CoveragePosition memory data, uint256 amount, uint256 duration, uint256 reward)
        private
        pure
    {
        uint256 minimumReward = (amount * data.minRate * duration) / (10000 * 365 days);
        if (minimumReward > reward) revert InsufficientReward(minimumReward, reward);

        if (data.maxDuration > 0 && duration > data.maxDuration) revert DurationExceedsMax(data.maxDuration, duration);
    }

    /// @notice Updates the operator's coverage tracking map for a strategy and coverage agent
    function _updateCoverageMap(address operator, address strategy, address coverageAgent, uint256 amount) private {
        EnumerableMap.AddressToUintMap storage coverageMap = operators[operator].coverageStrategies[strategy];

        // Get the current value, or 0 if the key doesn't exist
        (bool exists, uint256 currentValue) = coverageMap.tryGet(coverageAgent);
        uint256 newValue = (exists ? currentValue : 0) + amount;

        coverageMap.set(coverageAgent, newValue);
    }

    /// @notice Checks if the operator has sufficient coverage available for the coverage agent
    /// @dev Reverts only if the operator does not have enough allocated to safely cover the agent.
    function _checkCoverage(address operator, address strategy, address coverageAgent) private view {
        uint256 deficit = _coverageDeficitAmount(operator, strategy, coverageAgent);
        // Check to see if agent has a deficit of coverage
        if (deficit > 0) {
            revert InsufficientCoverageAvailable(deficit);
        }
    }

    function _coverageDeficitAmount(address operator, address strategy, address coverageAgent)
        private
        view
        returns (uint256 deficit)
    {
        uint256 totalAllocatedCoverage = _totalAllocatedValueToCoverageAgent(operator, strategy, coverageAgent);
        uint256 totalCoverageByOperator = _totalCoverageByOperatorStrategy(operator, strategy, coverageAgent);

        if (totalAllocatedCoverage < totalCoverageByOperator) {
            deficit = totalCoverageByOperator - totalAllocatedCoverage;
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

    /// @notice Returns the total coverage allocated to a coverage agent for a strategy in the operators asset
    function _totalAllocatedValueToCoverageAgent(address operator, address strategy, address coverageAgent)
        private
        view
        returns (uint256 total)
    {
        address[] memory _operators = new address[](1);
        _operators[0] = operator;
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = IStrategy(strategy);
        address strategyAsset = address(IStrategy(strategy).underlyingToken());
        address coverageAsset = address(ICoverageAgent(coverageAgent).asset());
        uint256[][] memory allocatedStake = IAllocationManager(_eigenAddresses.allocationManager)
            .getAllocatedStake(
                OperatorSet({avs: address(this), id: coverageAgentToOperatorSetId[coverageAgent]}),
                _operators,
                strategies
            );
        (total,) =
            IAssetPriceOracleAndSwapper(address(this)).getQuote(allocatedStake[0][0], coverageAsset, strategyAsset);
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

        // Slash the operator through EigenLayer and claim redistributed tokens
        IEigenServiceManager(address(this))
            .slashOperator(eigenPosition.operator, eigenPosition.strategy, _position.coverageAgent, amount);

        // Swap the slashed strategy asset to the coverage agent's asset
        IAssetPriceOracleAndSwapper(address(this)).
            // casting is safe because we know the amount can not be larger than a uint128
            // forge-lint: disable-next-line(unsafe-typecast)
            swapForOutput(uint128(amount), ICoverageAgent(_position.coverageAgent).asset(), _position.asset);

        // Transfer swapped tokens to coverage agent
        bool success = IERC20(ICoverageAgent(_position.coverageAgent).asset()).transfer(_position.coverageAgent, amount);
        if (!success) revert SlashFailed(claimId);

        _claim.status = CoverageClaimStatus.Slashed;
        ICoverageAgent(_position.coverageAgent).onSlashCompleted(claimId);
        emit ClaimSlashed(claimId, amount);
    }

    function _checkOperatorPermissions(address operator, address target, bytes4 selector) private returns (bool) {
        return
            IPermissionController(_eigenAddresses.permissionController).canCall(operator, msg.sender, target, selector);
    }
}

