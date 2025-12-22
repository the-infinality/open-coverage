// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin-v5/contracts/token/ERC20/ERC20.sol";
import {EnumerableMap} from "@openzeppelin-v5/contracts/utils/structs/EnumerableMap.sol";
import {IAllocationManager, IAllocationManagerTypes} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";
import {IStrategyManager} from "eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {OperatorSet} from "eigenlayer-contracts/libraries/OperatorSetLib.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IRewardsCoordinatorTypes} from "eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {Refundable, CoverageClaimStatus} from "src/interfaces/ICoverageProvider.sol";

import {LibDiamond} from "../../../diamond/libraries/LibDiamond.sol";
import {EigenAddresses} from "../Types.sol";
import {InvalidAVS, NotAllocated} from "../Errors.sol";
import {IEigenServiceManager, EigenCoveragePosition} from "../interfaces/IEigenServiceManager.sol";
import {CoverageClaim} from "../../../interfaces/ICoverageProvider.sol";
import {ICoverageAgent} from "../../../interfaces/ICoverageAgent.sol";
import {IAssetPriceOracleAndSwapper} from "../../../interfaces/IAssetPriceOracleAndSwapper.sol";
import {EigenCoverageStorage, ClaimRewardDistribution} from "../EigenCoverageStorage.sol";
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
    function registerOperator(address, address _avs, uint32[] calldata, bytes calldata) external view {
        require(msg.sender != _eigenAddresses.delegationManager, "Not delegation manager");
        if (_avs != address(this)) revert InvalidAVS();
    }

    /// @inheritdoc IEigenServiceManager
    function setStrategyWhitelist(address strategyAddress, bool whitelisted) external {
        LibDiamond.enforceIsContractOwner();

        if (assetToStrategy[address(IStrategy(strategyAddress).underlyingToken())] != address(0)) {
            revert StrategyAssetAlreadyRegistered(address(IStrategy(strategyAddress).underlyingToken()));
        }
        if (whitelisted) {
            assetToStrategy[address(IStrategy(strategyAddress).underlyingToken())] = strategyAddress;
        } else {
            delete assetToStrategy[address(IStrategy(strategyAddress).underlyingToken())];
        }
        strategyWhitelist[strategyAddress] = whitelisted;
    }

    /// @inheritdoc IEigenServiceManager
    function isStrategyWhitelisted(address strategy) external view returns (bool) {
        return strategyWhitelist[strategy];
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
    function captureRewards(uint256 claimId)
        external
        returns (uint256 amount, uint32 duration, uint32 distributionStartTime)
    {
        IRewardsCoordinator rewardsCoordinator = IRewardsCoordinator(_eigenAddresses.rewardsCoordinator);

        CoverageClaim memory _claim = claims[claimId];
        EigenCoveragePosition memory _position = positions[_claim.positionId];
        ClaimRewardDistribution memory _claimRewardDistribution = claimRewardDistributions[claimId];

        uint32 calculationInterval = rewardsCoordinator.CALCULATION_INTERVAL_SECONDS();
        distributionStartTime =
            uint32(_claimRewardDistribution.lastDistributedTimestamp / calculationInterval) * calculationInterval;

        duration = uint32(
            _min(
                _min(block.timestamp - distributionStartTime, rewardsCoordinator.MAX_REWARDS_DURATION()),
                _claim.duration + _claim.createdAt - distributionStartTime
            ) / calculationInterval * calculationInterval
        );

        if (duration == 0) {
            return (0, 0, distributionStartTime);
        }

        if (_position.data.refundable == Refundable.TimeWeighted || _position.data.refundable == Refundable.None) {
            uint256 claimableReward =
                _min(block.timestamp - _claim.createdAt, _claim.duration) * _claim.reward / _claim.duration;
            amount = claimableReward - _claimRewardDistribution.amount;
            claimRewardDistributions[claimId].amount += amount;
            claimRewardDistributions[claimId].lastDistributedTimestamp = uint32(block.timestamp);
        } else if (_position.data.refundable == Refundable.Full && _claim.status == CoverageClaimStatus.Completed) {
            amount = _claim.reward;
        } else {
            return (0, 0, distributionStartTime);
        }

        IERC20 coverageAsset = IERC20(ICoverageAgent(_position.data.coverageAgent).asset());
        coverageAsset.approve(address(rewardsCoordinator), amount);

        IRewardsCoordinatorTypes.StrategyAndMultiplier[] memory strategiesAndMultipliers =
            new IRewardsCoordinatorTypes.StrategyAndMultiplier[](1);
        strategiesAndMultipliers[0] =
            IRewardsCoordinatorTypes.StrategyAndMultiplier({strategy: IStrategy(_position.strategy), multiplier: 1});

        IRewardsCoordinatorTypes.OperatorReward[] memory operatorRewards =
            new IRewardsCoordinatorTypes.OperatorReward[](1);
        operatorRewards[0] = IRewardsCoordinatorTypes.OperatorReward({operator: _position.operator, amount: amount});

        IRewardsCoordinatorTypes.OperatorDirectedRewardsSubmission[] memory operatorDirectedRewardsSubmissions =
            new IRewardsCoordinatorTypes.OperatorDirectedRewardsSubmission[](1);
        operatorDirectedRewardsSubmissions[0] = IRewardsCoordinatorTypes.OperatorDirectedRewardsSubmission({
            strategiesAndMultipliers: strategiesAndMultipliers,
            token: coverageAsset,
            operatorRewards: operatorRewards,
            startTimestamp: distributionStartTime,
            duration: duration,
            description: "Coverage reward"
        });

        rewardsCoordinator.createOperatorDirectedAVSRewardsSubmission(address(this), operatorDirectedRewardsSubmissions);
    }

    /// @inheritdoc IEigenServiceManager
    function updateAVSMetadataURI(string calldata metadataURI) external {
        LibDiamond.enforceIsContractOwner();
        IAllocationManager(_eigenAddresses.allocationManager).updateAVSMetadataURI(address(this), metadataURI);
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
    function ensureAllocations(address coverageAgent, address operator, address strategy) external {
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

        if (allocation.currentMagnitude == 0) revert NotAllocated();
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
        uint256 quotedPrice =
            IAssetPriceOracleAndSwapper(address(this)).getQuote(allocatedStake[0][0], strategyAsset, coverageAsset);

        uint8 strategyDecimals = ERC20(strategyAsset).decimals();
        uint8 coverageDecimals = ERC20(coverageAsset).decimals();

        if (strategyDecimals > coverageDecimals) {
            return quotedPrice / (10 ** (strategyDecimals - coverageDecimals));
        } else {
            return quotedPrice * (10 ** (coverageDecimals - strategyDecimals));
        }
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

        if (totalAllocatedStake == 0) revert NotAllocated();

        // Convert amount to strategy asset and calculate proportion
        uint256 slashAmount = IAssetPriceOracleAndSwapper(address(this))
            .getQuote(
                amount, address(IStrategy(strategy).underlyingToken()), address(ICoverageAgent(coverageAgent).asset())
            );
        wadToSlash = (slashAmount * WAD) / totalAllocatedStake;
        if (wadToSlash > WAD) wadToSlash = WAD;
    }
}

