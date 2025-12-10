// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UUPSUpgradeable} from "@openzeppelin-v5/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin-v5/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IAllocationManager, IAllocationManagerTypes} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";
import {OperatorSet} from "eigenlayer-contracts/libraries/OperatorSetLib.sol";
import {IPermissionController} from "eigenlayer-contracts/interfaces/IPermissionController.sol";

import {EigenAddresses, ClaimReward, OperatorRewards} from "./Types.sol";
import {
    CoverageAgentAlreadyRegistered,
    InvalidAVS,
    NotOperatorAuthorized,
    InvalidAsset,
    NotAllocated,
    NoRewardsToClaim,
    ClaimNotFound,
    InvalidClaimStatus,
    ClaimAlreadyLiquidated
} from "./Errors.sol";
import {
    IEigenServiceManager,
    CreatePositionAddtionalData,
    EigenCoveragePosition,
    OperatorData
} from "./interfaces/IEigenServiceManager.sol";
import {
    ICoverageProvider,
    CoveragePosition,
    CoverageClaim,
    CoverageClaimStatus,
    Refundable
} from "../../interfaces/ICoverageProvider.sol";
import {ICoverageAgent} from "../../interfaces/ICoverageAgent.sol";

/// @title EigenCoverageProvider
/// @author p-dealwis, Infinality
/// @notice A provider for Eigen delegations
/// @dev Manage delegation strategies to whitelist strategies, distribute rewards and slash operators.
contract EigenCoverageProvider is IEigenServiceManager, ICoverageProvider, UUPSUpgradeable, OwnableUpgradeable {
    /// @notice Emitted when an operator claims rewards
    event RewardsClaimed(address indexed operator, address indexed coverageAgent, uint256 amount);
    
    EigenAddresses private _eigenAddresses;

    uint32 private _operatorSetCount = 0;

    EigenCoveragePosition[] public positions;
    CoverageClaim[] public claims;

    mapping(address => uint32) public coverageAgentToOperatorSetId;

    mapping(address => bool) public strategyWhitelist;

    mapping(address => OperatorData) public operators;

    // Reward tracking: claimId => ClaimReward
    mapping(uint256 => ClaimReward) public claimRewardData;

    // Operator rewards: operator => coverageAgent => OperatorRewards
    mapping(address => mapping(address => OperatorRewards)) public operatorRewards;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// ============ Upgradeability ============ //

    function initialize(address _owner, EigenAddresses memory eigenAddresses_, string memory _metadataURI)
        external
        initializer
    {
        __Ownable_init(_owner);
        _eigenAddresses = eigenAddresses_;

        _updateAVSMetadataURI(_metadataURI);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        // Only owner can upgrade
    }

    /// ============ ICoverageProvider implementations ============ //

    /// @inheritdoc ICoverageProvider
    function onIsRegistered() external {
        if (coverageAgentToOperatorSetId[msg.sender] != 0) revert CoverageAgentAlreadyRegistered();

        IAllocationManagerTypes.CreateSetParams[] memory params = new IAllocationManager.CreateSetParams[](1);

        uint32 operatorSetId = ++_operatorSetCount;

        // Setup a new operator set with the default predefined strategies
        params[0] =
            IAllocationManagerTypes.CreateSetParams({operatorSetId: operatorSetId, strategies: new IStrategy[](0)});

        address[] memory redistributionRecipients = new address[](1);
        redistributionRecipients[0] = msg.sender;

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
        _validatePositionData(data);

        CreatePositionAddtionalData memory createPositionAddtionalData =
            abi.decode(additionalData, (CreatePositionAddtionalData));

        if (!_checkOperatorPermissions(
                createPositionAddtionalData.operator,
                _eigenAddresses.allocationManager,
                IAllocationManager.modifyAllocations.selector
            )) revert NotOperatorAuthorized(createPositionAddtionalData.operator, msg.sender);

        if (address(IStrategy(createPositionAddtionalData.strategy).underlyingToken()) != data.asset) {
            revert InvalidAsset(createPositionAddtionalData.strategy, data.asset);
        }

        // Make sure operator has strategy allocations to the operator set for the coverage agent
        uint32 operatorSetId = coverageAgentToOperatorSetId[coverageAgent];
        OperatorSet memory operatorSet = OperatorSet({avs: address(this), id: operatorSetId});
        IAllocationManagerTypes.Allocation memory allocation = IAllocationManager(_eigenAddresses.allocationManager)
            .getAllocation(
                createPositionAddtionalData.operator, operatorSet, IStrategy(createPositionAddtionalData.strategy)
            );

        if (allocation.currentMagnitude == 0) revert NotAllocated();

        positionId = _registerPosition(coverageAgent, data, createPositionAddtionalData);
    }

    /// @inheritdoc ICoverageProvider
    function updatePosition(uint256 positionId, CoveragePosition memory data) external {
        _validatePositionData(data);
        positions[positionId].data = data;
        emit PositionUpdated(positionId);
    }

    /// @inheritdoc ICoverageProvider
    function issueCoverage(
        uint256 positionId,
        uint256 amount,
        uint256 duration,
        address paymentAsset,
        uint256 paymentAmount
    ) external returns (uint256 claimId) {
        // Calculate the premium amount based on duration and min rate
        EigenCoveragePosition storage positionData = positions[positionId];
        uint16 minRate = positionData.data.minRate; // in basis points per annum (1e4 = 100%)

        uint256 minimumPremium = (amount * minRate * duration) / (10000 * 365 days);

        uint256 premiumInPositionAsset;

        // Skip conversion if the payment asset is the same as the position asset
        if (positionData.data.asset != paymentAsset) {
            // TODO: get premium
        } else {
            premiumInPositionAsset = paymentAmount;
        }

        // paymentAmount check can be enforced if required
        require(premiumInPositionAsset >= minimumPremium, "Insufficient payment amount for premium");

        // Create the claim
        claims.push(
            CoverageClaim({
                positionId: positionId, 
                amount: amount, 
                duration: duration, 
                status: CoverageClaimStatus.Issued
            })
        );
        claimId = claims.length - 1;
        
        operators[positionData.operator].coverageAgentAmount[positionData.coverageAgent] += premiumInPositionAsset;

        // Track rewards based on refundable status
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + duration;
        
        // Initialize claim reward tracking
        claimRewardData[claimId] = ClaimReward({
            totalReward: premiumInPositionAsset,
            distributedReward: 0,
            startTime: startTime,
            endTime: endTime,
            liquidationTime: 0
        });

        // Handle immediate distribution for Refundable.None
        if (positionData.data.refundable == Refundable.None) {
            // Distribute rewards immediately to operator
            operatorRewards[positionData.operator][positionData.coverageAgent].pendingRewards += premiumInPositionAsset;
            claimRewardData[claimId].distributedReward = premiumInPositionAsset;
        }
        // For Refundable.TimeWeighted and Refundable.Full, rewards are tracked but not distributed yet

        emit ClaimIssued(positionId, claimId, amount, duration);
    }

    /// @inheritdoc ICoverageProvider
    function liquidateClaim(uint256 claimId) external {
        if (claimId >= claims.length) revert ClaimNotFound(claimId);
        
        CoverageClaim storage claimData = claims[claimId];
        
        // Validate claim status
        if (claimData.status == CoverageClaimStatus.Liquidated) {
            revert ClaimAlreadyLiquidated(claimId);
        }
        if (claimData.status != CoverageClaimStatus.Issued) {
            revert InvalidClaimStatus(claimId, claimData.status);
        }

        // Get position and operator info
        EigenCoveragePosition storage position = positions[claimData.positionId];
        ClaimReward storage reward = claimRewardData[claimId];
        
        // Mark liquidation time
        reward.liquidationTime = block.timestamp;
        claimData.status = CoverageClaimStatus.Liquidated;

        // Calculate rewards up to liquidation point based on refundable status
        if (position.data.refundable == Refundable.TimeWeighted) {
            // Calculate time-weighted reward up to liquidation
            uint256 timeElapsed = block.timestamp - reward.startTime;
            uint256 totalDuration = reward.endTime - reward.startTime;
            
            // Calculate proportional reward earned up to liquidation
            uint256 earnedReward = (reward.totalReward * timeElapsed) / totalDuration;
            
            // Distribute earned reward to operator
            uint256 rewardToDistribute = earnedReward - reward.distributedReward;
            if (rewardToDistribute > 0) {
                operatorRewards[position.operator][position.coverageAgent].pendingRewards += rewardToDistribute;
                reward.distributedReward = earnedReward;
            }
        } else if (position.data.refundable == Refundable.None) {
            // For Refundable.None, rewards were already distributed at issuance
            // No additional action needed
        }
        // For Refundable.Full, no rewards are distributed on liquidation

        emit Liquidated(claimId);
    }

    /// @inheritdoc ICoverageProvider
    function completeClaims(uint256 claimId) external {
        if (claimId >= claims.length) revert ClaimNotFound(claimId);
        
        CoverageClaim storage claimData = claims[claimId];
        
        // Validate claim can be completed
        if (claimData.status == CoverageClaimStatus.Completed) {
            revert InvalidClaimStatus(claimId, claimData.status);
        }
        if (claimData.status == CoverageClaimStatus.PendingSlash) {
            revert InvalidClaimStatus(claimId, claimData.status);
        }

        // Get position and operator info
        EigenCoveragePosition storage position = positions[claimData.positionId];
        ClaimReward storage reward = claimRewardData[claimId];

        // Handle reward distribution based on refundable status and claim status
        if (claimData.status == CoverageClaimStatus.Issued) {
            // Claim completed successfully without liquidation
            
            if (position.data.refundable == Refundable.Full) {
                // For Refundable.Full, distribute all rewards on completion
                uint256 rewardToDistribute = reward.totalReward - reward.distributedReward;
                if (rewardToDistribute > 0) {
                    operatorRewards[position.operator][position.coverageAgent].pendingRewards += rewardToDistribute;
                    reward.distributedReward = reward.totalReward;
                }
            } else if (position.data.refundable == Refundable.TimeWeighted) {
                // For time-weighted, distribute remaining rewards
                uint256 rewardToDistribute = reward.totalReward - reward.distributedReward;
                if (rewardToDistribute > 0) {
                    operatorRewards[position.operator][position.coverageAgent].pendingRewards += rewardToDistribute;
                    reward.distributedReward = reward.totalReward;
                }
            }
            // For Refundable.None, rewards were already distributed at issuance
        } else if (claimData.status == CoverageClaimStatus.Liquidated) {
            // Claim was liquidated, rewards were already handled in liquidateClaim
            // No additional reward distribution needed
        }

        // Mark claim as completed
        claimData.status = CoverageClaimStatus.Completed;
        
        emit ClaimCompleted(claimId);
    }

    /// @inheritdoc ICoverageProvider
    function slashClaims(uint256[] calldata claimIds, uint256[] calldata amounts)
        external
        returns (CoverageClaimStatus[] memory slashStatuses)
    {
        //TODO: Implement slashClaims
    }

    /// @notice Claim rewards for an operator from a coverage agent
    /// @dev Only callable by authorized handlers for the operator
    /// @param operator The operator to claim rewards for
    /// @param coverageAgent The coverage agent to claim rewards from
    function claimRewards(address operator, address coverageAgent) external returns (uint256 rewardAmount) {
        // Check operator permissions
        if (!_checkOperatorPermissions(
                operator,
                _eigenAddresses.rewardsCoordinator,
                bytes4(keccak256("processRewardClaim(address,address)"))
            )) revert NotOperatorAuthorized(operator, msg.sender);

        OperatorRewards storage rewards = operatorRewards[operator][coverageAgent];
        rewardAmount = rewards.pendingRewards;
        
        if (rewardAmount == 0) revert NoRewardsToClaim();

        // Update reward tracking
        rewards.pendingRewards = 0;
        rewards.claimedRewards += rewardAmount;

        emit RewardsClaimed(operator, coverageAgent, rewardAmount);

        // Transfer rewards to operator
        // TODO: Implement actual token transfer based on the asset
    }

    /// @notice Get pending rewards for an operator from a coverage agent
    /// @param operator The operator address
    /// @param coverageAgent The coverage agent address
    /// @return pendingRewards Amount of pending rewards
    function getPendingRewards(address operator, address coverageAgent) external view returns (uint256 pendingRewards) {
        return operatorRewards[operator][coverageAgent].pendingRewards;
    }

    /// @notice Get total claimed rewards for an operator from a coverage agent
    /// @param operator The operator address
    /// @param coverageAgent The coverage agent address
    /// @return claimedRewards Amount of claimed rewards
    function getClaimedRewards(address operator, address coverageAgent) external view returns (uint256 claimedRewards) {
        return operatorRewards[operator][coverageAgent].claimedRewards;
    }

    /// @inheritdoc ICoverageProvider
    function totalCoverageByAgent(address coverageAgent) external view returns (uint256 amount) {
        //TODO: Implement totalCoverageByAgent
    }

    /// @inheritdoc ICoverageProvider
    function position(uint256 positionId) external view returns (CoveragePosition memory) {
        return positions[positionId].data;
    }

    /// @inheritdoc ICoverageProvider
    function claim(uint256 claimId) external view returns (CoverageClaim memory data) {
        //TODO: Implement claim
    }

    // ============ IEigenServiceManager implementations ============ //

    /// @inheritdoc IEigenServiceManager
    function registerOperator(address, address _avs, uint32[] calldata, bytes calldata) external view {
        require(msg.sender != _eigenAddresses.delegationManager, "Not delegation manager");
        if (_avs != address(this)) revert InvalidAVS();
    }

    /// @inheritdoc IEigenServiceManager
    function setStrategyWhitelist(address strategyAddress, bool whitelisted) external onlyOwner {
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

    function eigenAddresses() external view returns (EigenAddresses memory) {
        return _eigenAddresses;
    }

    /// ============ Internal functions ============ //

    /// @notice Updates the metadata URI for the AVS
    /// @param _metadataUri is the metadata URI for the AVS
    function _updateAVSMetadataURI(string memory _metadataUri) private {
        IAllocationManager(_eigenAddresses.allocationManager).updateAVSMetadataURI(address(this), _metadataUri);
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
                strategy: createPositionAddtionalData.strategy,
                coverageAgent: coverageAgent
            })
        );
        positionId = positions.length - 1;

        emit PositionCreated(positionId);

        // Notify the coverage agent that the position has been registered
        ICoverageAgent(coverageAgent).onRegisterPosition(positionId);
    }

    function _validatePositionData(CoveragePosition memory data) private view {
        if (data.expiryTimestamp < block.timestamp) revert TimestampInvalid(data.expiryTimestamp);
        if (data.minRate > 10000) revert MinRateInvalid(data.minRate);
    }

    function _checkOperatorPermissions(address operator, address target, bytes4 selector) private returns (bool) {
        return
            IPermissionController(_eigenAddresses.permissionController).canCall(operator, msg.sender, target, selector);
    }
}
