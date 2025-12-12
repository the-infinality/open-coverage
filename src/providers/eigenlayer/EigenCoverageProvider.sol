// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EnumerableMap} from "@openzeppelin-v5/contracts/utils/structs/EnumerableMap.sol";
import {UUPSUpgradeable} from "@openzeppelin-v5/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin-v5/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IAllocationManager, IAllocationManagerTypes} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";
import {OperatorSet} from "eigenlayer-contracts/libraries/OperatorSetLib.sol";
import {IPermissionController} from "eigenlayer-contracts/interfaces/IPermissionController.sol";

import {EigenAddresses} from "./Types.sol";
import {
    CoverageAgentAlreadyRegistered,
    InvalidAVS,
    NotOperatorAuthorized,
    InvalidAsset,
    NotAllocated
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
    CoverageClaimStatus
} from "../../interfaces/ICoverageProvider.sol";
import {ICoverageAgent} from "../../interfaces/ICoverageAgent.sol";
import {AssetPriceOracleAndSwapper} from "../../mixins/AssetPriceOracleAndSwapper.sol";

/// @title EigenCoverageProvider
/// @author p-dealwis, Infinality
/// @notice A provider for Eigen delegations
/// @dev Manage delegation strategies to whitelist strategies, distribute rewards and slash operators.
contract EigenCoverageProvider is AssetPriceOracleAndSwapper, IEigenServiceManager, ICoverageProvider, UUPSUpgradeable, OwnableUpgradeable {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    EigenAddresses private _eigenAddresses;

    uint32 private _operatorSetCount = 0;

    EigenCoveragePosition[] public positions;
    CoverageClaim[] public claims;

    mapping(address => uint32) public coverageAgentToOperatorSetId;

    mapping(address => bool) public strategyWhitelist;
    mapping(address => address) public assetToStrategy;

    mapping(address => OperatorData) public operators;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// ============ Upgradeability ============ //

    function initialize(
        address _owner,
        EigenAddresses memory eigenAddresses_,
        string memory _metadataURI,
        address universalRouter_,
        address permit2_
    )
        external
        initializer
    {
        __Ownable_init(_owner);
        __AssetPriceOracleAndSwapper_init(universalRouter_, permit2_);
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
        if (data.expiryTimestamp < block.timestamp) revert TimestampInvalid(data.expiryTimestamp);
        if (data.minRate > 10000) revert MinRateInvalid(data.minRate);

        CreatePositionAddtionalData memory createPositionAddtionalData =
            abi.decode(additionalData, (CreatePositionAddtionalData));

        if (!_checkOperatorPermissions(
                createPositionAddtionalData.operator,
                _eigenAddresses.allocationManager,
                IAllocationManager.modifyAllocations.selector
            )) revert NotOperatorAuthorized(createPositionAddtionalData.operator, msg.sender);

        if(!strategyWhitelist[createPositionAddtionalData.strategy]) revert StrategyNotWhitelisted(createPositionAddtionalData.strategy);

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
    /// @dev The caller must have the `modifyAllocations` permission for the operator
    function closePosition(uint256 positionId) external {
        EigenCoveragePosition storage positionData = positions[positionId];

        if (!_checkOperatorPermissions(
                positionData.operator,
                _eigenAddresses.allocationManager,
                IAllocationManager.modifyAllocations.selector
            )) revert NotOperatorAuthorized(positionData.operator, msg.sender);

        positions[positionId].data.expiryTimestamp = block.timestamp;
        emit PositionClosed(positionId);
    }

    /// @inheritdoc ICoverageProvider
    function claimCoverage(
        uint256 positionId,
        uint256 amount,
        uint256 duration,
        uint256 reward
    ) external returns (uint256 claimId) {
        EigenCoveragePosition storage positionData = positions[positionId];
        if(msg.sender != positionData.data.coverageAgent) revert NotCoverageAgent(msg.sender, positionData.data.coverageAgent);

        // Check whether the rewards meets the minimum reward rate
        uint256 minimumReward = (amount * positionData.data.minRate * duration) / (10000 * 365 days);
        if(minimumReward > reward) revert InsufficientReward(minimumReward, reward);

        // Add the total coverage to the operator's strategy by coverage agent for tracking coverage obligations.
        address strategy = assetToStrategy[positionData.data.asset];
        operators[positionData.operator].coverageStrategies[strategy].set(
            positionData.data.coverageAgent, 
            operators[positionData.operator].coverageStrategies[strategy].get(positionData.data.coverageAgent) + amount
        );

        // Check to see whether the operator has enough coverage available to cover the claim.
        if(_totalAllocatedOperatorStrategyToCoverageAgent(positionData.operator, strategy, positionData.data.coverageAgent) < 
            _totalCoverageByOperatorStrategy(positionData.operator, strategy)) {
            revert InsufficientCoverageAvailable(
                _totalCoverageByOperatorStrategy(positionData.operator, strategy), 
                _totalAllocatedOperatorStrategyToCoverageAgent(positionData.operator, strategy, positionData.data.coverageAgent)
            );
        }

        claimId = claims.length;
        claims.push(
            CoverageClaim({
                positionId: positionId, 
                amount: amount, 
                duration: duration, 
                status: CoverageClaimStatus.Issued,
                reward: reward
            })
        );
    }

    /// @inheritdoc ICoverageProvider
    function liquidateClaim(uint256 claimId) external {
        //TODO: Implement liquidateClaim
    }

    /// @inheritdoc ICoverageProvider
    function completeClaims(uint256 claimId) external {
        //TODO: Implement completeClaims
    }

    /// @inheritdoc ICoverageProvider
    function slashClaims(uint256[] calldata claimIds, uint256[] calldata amounts)
        external
        returns (CoverageClaimStatus[] memory slashStatuses)
    {
        //TODO: Implement slashClaims
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
        if(assetToStrategy[address(IStrategy(strategyAddress).underlyingToken())] != address(0)) 
            revert StrategyAssetAlreadyRegistered(address(IStrategy(strategyAddress).underlyingToken()));
        if(whitelisted) {
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

    function eigenAddresses() external view returns (EigenAddresses memory) {
        return _eigenAddresses;
    }

    /// ============ Internal functions ============ //

    /// @notice Updates the metadata URI for the AVS
    /// @param _metadataUri is the metadata URI for the AVS
    function _updateAVSMetadataURI(string memory _metadataUri) private {
        IAllocationManager(_eigenAddresses.allocationManager).updateAVSMetadataURI(address(this), _metadataUri);
    }

    function _totalCoverageByOperatorStrategy(address operator, address strategy) private view returns (uint256 total) {
        for (uint256 i = 0; i < operators[operator].coverageStrategies[strategy].length(); i++) {
            (address key, uint256 value) = operators[operator].coverageStrategies[strategy].at(i);
            total += quote(value, ICoverageAgent(key).asset(), address(IStrategy(strategy).underlyingToken()));
        }
    }

    function _totalAllocatedOperatorStrategyToCoverageAgent(address operator, address strategy, address coverageAgent) private view returns (uint256 total) {
        address[] memory _operators = new address[](1);
        _operators[0] = operator;
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = IStrategy(strategy);
        uint256[][] memory allocatedStake = IAllocationManager(_eigenAddresses.allocationManager)
            .getAllocatedStake(OperatorSet({avs: address(this), id: coverageAgentToOperatorSetId[coverageAgent]}), _operators, strategies);
        return allocatedStake[0][0];
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

    function _checkOperatorPermissions(address operator, address target, bytes4 selector) private returns (bool) {
        return
            IPermissionController(_eigenAddresses.permissionController).canCall(operator, msg.sender, target, selector);
    }
}
