// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20 as EigenIERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20} from "@openzeppelin-v5/contracts/token/ERC20/IERC20.sol";
import {EnumerableMap} from "@openzeppelin-v5/contracts/utils/structs/EnumerableMap.sol";
import {IAllocationManager, IAllocationManagerTypes} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";
import {IStrategyManager} from "eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {OperatorSet} from "eigenlayer-contracts/libraries/OperatorSetLib.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IRewardsCoordinatorTypes} from "eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {ICoverageProvider} from "src/interfaces/ICoverageProvider.sol";
import {LibDiamond} from "src/diamond/libraries/LibDiamond.sol";
import {EigenAddresses} from "../Types.sol";
import {IEigenServiceManager} from "../interfaces/IEigenServiceManager.sol";
import {ICoverageAgent} from "src/interfaces/ICoverageAgent.sol";
import {IAssetPriceOracleAndSwapper} from "src/interfaces/IAssetPriceOracleAndSwapper.sol";
import {EigenCoverageStorage} from "../EigenCoverageStorage.sol";
import {WAD} from "eigenlayer-contracts/libraries/SlashingLib.sol";

/// @title EigenServiceManagerFacet
/// @author p-dealwis, Infinality
/// @notice Facet contract implementing IEigenServiceManager interface
/// @dev This contract is designed to be called via delegatecall from EigenCoverageDiamond
contract EigenServiceManagerFacet is EigenCoverageStorage, IEigenServiceManager {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    /// @inheritdoc IEigenServiceManager
    function eigenAddresses() external view returns (EigenAddresses memory) {
        return _eigenAddresses;
    }

    /// @inheritdoc IEigenServiceManager
    function registerOperator(address operator, address _avs, uint32[] calldata, bytes calldata) external {
        require(msg.sender != _eigenAddresses.delegationManager, "Not delegation manager");
        if (_avs != address(this)) revert IEigenServiceManager.InvalidAVS(_avs);

        operators[operator].coverageThreshold = 7000; // Default coverage threshold to 70%
    }

    /// @inheritdoc IEigenServiceManager
    function setStrategyWhitelist(address strategyAddress, bool whitelisted) external {
        LibDiamond.enforceIsContractOwner();

        address underlyingToken = address(IStrategy(strategyAddress).underlyingToken());

        if (whitelisted) {
            address existingStrategy = assetToStrategy[underlyingToken];
            if (existingStrategy != address(0) && _strategyWhitelist.contains(existingStrategy)) {
                revert StrategyAssetAlreadyRegistered(underlyingToken);
            }
            assetToStrategy[underlyingToken] = strategyAddress;
            _strategyWhitelist.set(strategyAddress, 1);
        } else {
            // Do not remove it from the assetToStrategy mapping because existing claims may still reference it
            _strategyWhitelist.remove(strategyAddress);
        }
    }

    /// @inheritdoc IEigenServiceManager
    function isStrategyWhitelisted(address strategy) external view returns (bool) {
        return _strategyWhitelist.contains(strategy);
    }

    /// @inheritdoc IEigenServiceManager
    function whitelistedStrategies() external view returns (address[] memory strategies) {
        uint256 length = _strategyWhitelist.length();
        strategies = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            (strategies[i],) = _strategyWhitelist.at(i);
        }
    }

    /// @inheritdoc IEigenServiceManager
    function getOperatorSetId(address coverageAgent) external view returns (uint32) {
        return coverageAgentToOperatorSetId[coverageAgent];
    }

    /// @inheritdoc IEigenServiceManager
    function coverageAllocated(address operator, address strategy, address coverageAgent)
        external
        view
        returns (uint256)
    {
        return _totalAllocatedValueToCoverageAgent(operator, strategy, coverageAgent);
    }

    /// @inheritdoc IEigenServiceManager
    function submitOperatorReward(
        address operator,
        IStrategy strategy,
        IERC20 token,
        uint256 amount,
        uint32 distributionStartTime,
        uint32 duration,
        string memory description
    ) public returns (uint32 resolvedDistributionStartTime, uint32 resolvedDuration) {
        require(msg.sender == address(this), "Only internal calls");

        return _submitOperatorReward(operator, strategy, token, amount, distributionStartTime, duration, description);
    }

    /// @notice Submits an operator-directed reward to the RewardsCoordinator
    /// @dev If startTimestamp is 0, calculates distributionStartTime automatically using the next interval to avoid retroactive submissions
    /// @dev If duration is 0, uses CALCULATION_INTERVAL_SECONDS as the duration
    /// @param operator The operator to reward
    /// @param strategy The strategy associated with the reward
    /// @param token The token to distribute as reward
    /// @param amount The amount of tokens to reward
    /// @param distributionStartTime The start timestamp (0 to auto-calculate using next interval)
    /// @param duration The duration of the reward distribution (0 to use calculation interval)
    /// @param description Description of the reward
    function _submitOperatorReward(
        address operator,
        IStrategy strategy,
        IERC20 token,
        uint256 amount,
        uint32 distributionStartTime,
        uint32 duration,
        string memory description
    ) private returns (uint32 resolvedDistributionStartTime, uint32 resolvedDuration) {
        IRewardsCoordinator rewardsCoordinator = IRewardsCoordinator(_eigenAddresses.rewardsCoordinator);
        uint32 calculationInterval = rewardsCoordinator.CALCULATION_INTERVAL_SECONDS();

        // Dividing before multiplying to avoid overflow since we are using it to as a floor division
        // forge-lint: disable-next-line(divide-before-multiply)
        resolvedDuration = uint32((duration / calculationInterval) * calculationInterval);

        // Ensure minimum duration is at least one interval
        if (resolvedDuration == 0) {
            resolvedDuration = calculationInterval;
        }
        resolvedDuration = uint32(_min(resolvedDuration, rewardsCoordinator.MAX_REWARDS_DURATION()));

        resolvedDistributionStartTime = distributionStartTime;

        // Calculate distributionStartTime if not provided (0 means auto-calculate)
        if (resolvedDistributionStartTime == 0) {
            resolvedDistributionStartTime = uint32(block.timestamp - resolvedDuration);
        }

        // Dividing before multiplying to avoid overflow since we are using it to as a floor division
        // forge-lint: disable-next-line(divide-before-multiply)
        resolvedDistributionStartTime = (resolvedDistributionStartTime / calculationInterval) * calculationInterval;

        if ((resolvedDistributionStartTime + resolvedDuration) > block.timestamp) {
            resolvedDistributionStartTime -= resolvedDuration;
        }

        // Approve the rewards coordinator to spend the tokens
        token.approve(address(rewardsCoordinator), amount);

        IRewardsCoordinatorTypes.StrategyAndMultiplier[] memory strategiesAndMultipliers =
            new IRewardsCoordinatorTypes.StrategyAndMultiplier[](1);
        strategiesAndMultipliers[0] =
            IRewardsCoordinatorTypes.StrategyAndMultiplier({strategy: strategy, multiplier: 1});

        IRewardsCoordinatorTypes.OperatorReward[] memory operatorRewards =
            new IRewardsCoordinatorTypes.OperatorReward[](1);
        operatorRewards[0] = IRewardsCoordinatorTypes.OperatorReward({operator: operator, amount: amount});

        IRewardsCoordinatorTypes.OperatorDirectedRewardsSubmission[] memory operatorDirectedRewardsSubmissions =
            new IRewardsCoordinatorTypes.OperatorDirectedRewardsSubmission[](1);
        operatorDirectedRewardsSubmissions[0] = IRewardsCoordinatorTypes.OperatorDirectedRewardsSubmission({
            strategiesAndMultipliers: strategiesAndMultipliers,
            token: EigenIERC20(address(token)),
            operatorRewards: operatorRewards,
            startTimestamp: resolvedDistributionStartTime,
            duration: resolvedDuration,
            description: description
        });

        rewardsCoordinator.createOperatorDirectedAVSRewardsSubmission(address(this), operatorDirectedRewardsSubmissions);
    }

    /// @inheritdoc IEigenServiceManager
    function updateAVSMetadataURI(string calldata metadataURI) external {
        LibDiamond.enforceIsContractOwner();
        IAllocationManager(_eigenAddresses.allocationManager).updateAVSMetadataURI(address(this), metadataURI);
        emit ICoverageProvider.MetadataUpdated(metadataURI);
    }

    /// @inheritdoc IEigenServiceManager
    function slashOperator(address operator, address strategy, address coverageAgent, uint256 amount)
        external
        returns (uint256 tokensReceived)
    {
        require(msg.sender == address(this), "Only internal calls");

        uint32 operatorSetId = coverageAgentToOperatorSetId[coverageAgent];

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = IStrategy(strategy);

        uint256 wadToSlash = _calculateWadToSlash(operator, strategy, coverageAgent, amount);

        uint256[] memory wadsToSlash = new uint256[](1);
        wadsToSlash[0] = wadToSlash;

        (uint256 slashId,) = IAllocationManager(_eigenAddresses.allocationManager)
            .slashOperator(
                address(this),
                IAllocationManagerTypes.SlashingParams({
                    operator: operator,
                    operatorSetId: operatorSetId,
                    strategies: strategies,
                    wadsToSlash: wadsToSlash,
                    description: "Coverage claim slash"
                })
            );

        // Claim slashed tokens from StrategyManager (tokens are sent to this contract as redistribution recipient)
        OperatorSet memory operatorSet = OperatorSet({avs: address(this), id: operatorSetId});
        tokensReceived = IStrategyManager(_eigenAddresses.strategyManager)
            .clearBurnOrRedistributableSharesByStrategy(operatorSet, slashId, IStrategy(strategy));
    }

    /// @inheritdoc IEigenServiceManager
    function ensureAllocations(address operator, address coverageAgent, address strategy) external {
        uint32 operatorSetId = coverageAgentToOperatorSetId[coverageAgent];
        OperatorSet memory operatorSet = OperatorSet({avs: address(this), id: operatorSetId});
        IAllocationManager allocationManager = IAllocationManager(_eigenAddresses.allocationManager);

        // Ensure strategy is added to the operator set
        IStrategy[] memory strategiesInSet = allocationManager.getStrategiesInOperatorSet(operatorSet);
        bool strategyInSet = false;
        for (uint256 i = 0; i < strategiesInSet.length; i++) {
            if (address(strategiesInSet[i]) == strategy) {
                strategyInSet = true;
                break;
            }
        }
        if (!strategyInSet) {
            IStrategy[] memory strategiesToAdd = new IStrategy[](1);
            strategiesToAdd[0] = IStrategy(strategy);
            allocationManager.addStrategiesToOperatorSet(address(this), operatorSetId, strategiesToAdd);
        }

        // Make sure operator has strategy allocations to the coverage agent's operator set
        IAllocationManagerTypes.Allocation memory allocation =
            allocationManager.getAllocation(operator, operatorSet, IStrategy(strategy));

        if (allocation.currentMagnitude == 0) revert NotAllocated(operator, strategy, coverageAgent);
    }

    /// @inheritdoc IEigenServiceManager
    function getAllocationedStrategies(address operator, address coverageAgent)
        external
        view
        returns (address[] memory)
    {
        uint32 operatorSetId = coverageAgentToOperatorSetId[coverageAgent];
        OperatorSet memory operatorSet = OperatorSet({avs: address(this), id: operatorSetId});
        IStrategy[] memory strategies =
            IAllocationManager(_eigenAddresses.allocationManager).getAllocatedStrategies(operator, operatorSet);
        address[] memory strategiesAddresses = new address[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            strategiesAddresses[i] = address(strategies[i]);
        }
        return strategiesAddresses;
    }

    /// ============ Internal functions ============ //

    /// @notice Returns the minimum of two uint256 values
    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @notice Returns the total coverage allocated to a coverage agent for a strategy in the operator's asset
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
    
    /// @notice Calculates the WAD proportion to slash based on the amount
    function _calculateWadToSlash(address operator, address strategy, address coverageAgent, uint256 amount)
        private
        view
        returns (uint256 wadToSlash)
    {
        // Get allocated stake
        address[] memory ops = new address[](1);
        ops[0] = operator;
        IStrategy[] memory strats = new IStrategy[](1);
        strats[0] = IStrategy(strategy);

        uint256 totalAllocatedStake = IAllocationManager(_eigenAddresses.allocationManager)
            .getAllocatedStake(
                OperatorSet({avs: address(this), id: coverageAgentToOperatorSetId[coverageAgent]}), ops, strats
            )[0][0];

        // Convert amount to strategy asset and calculate proportion
        uint256 requiredSlashAmount = IAssetPriceOracleAndSwapper(address(this))
            .swapForOutputQuote(
                amount, address(IStrategy(strategy).underlyingToken()), address(ICoverageAgent(coverageAgent).asset())
            );
        wadToSlash = (requiredSlashAmount * WAD) / totalAllocatedStake;
        // Revert if the required slash amount is greater than the total allocated stake
        if (wadToSlash > WAD) {
            (uint256 totalAllocatedStakeValue,) = IAssetPriceOracleAndSwapper(address(this))
                .getQuote(
                    totalAllocatedStake,
                    address(ICoverageAgent(coverageAgent).asset()),
                    address(IStrategy(strategy).underlyingToken())
                );

            // Capture edge case rounding issues
            if (totalAllocatedStakeValue > amount) {
                revert ICoverageProvider.InsufficientSlashableCoverageAvailable(0);
            }
            revert ICoverageProvider.InsufficientSlashableCoverageAvailable(amount - totalAllocatedStakeValue);
        }
    }
}
