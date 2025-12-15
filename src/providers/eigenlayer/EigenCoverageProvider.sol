// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin-v5/contracts/token/ERC20/ERC20.sol";
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

        _validateReward(amount, positionData.data.minRate, duration, reward);

        address strategy = assetToStrategy[positionData.data.asset];
        _updateCoverageMap(positionData.operator, strategy, positionData.data.coverageAgent, amount);
        _checkCoverage(positionData.operator, strategy, positionData.data.coverageAgent);

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
    function position(uint256 positionId) external view returns (CoveragePosition memory) {
        return positions[positionId].data;
    }

    /// @inheritdoc ICoverageProvider
    function positionMaxAmount(uint256 positionId) external view returns (uint256 maxAmount) {
        EigenCoveragePosition memory _position = positions[positionId];

        uint256 allocatedCoverage = _totalAllocatedValueToCoverageAgent(_position.operator, _position.strategy, _position.data.coverageAgent);
        uint256 totalCoverageByOperator = _totalCoverageByOperatorStrategy(_position.operator, _position.strategy, _position.data.coverageAgent);
        if(allocatedCoverage > totalCoverageByOperator) {
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

    /// @inheritdoc IEigenServiceManager
    function coverageAllocated(address operator, address strategy, address coverageAgent) external view returns (uint256) {
        return _totalAllocatedValueToCoverageAgent(operator, strategy, coverageAgent);
    }

    /// ============ Internal functions ============ //

    /// @notice Updates the metadata URI for the AVS
    /// @param _metadataUri is the metadata URI for the AVS
    function _updateAVSMetadataURI(string memory _metadataUri) private {
        IAllocationManager(_eigenAddresses.allocationManager).updateAVSMetadataURI(address(this), _metadataUri);
    }

    /// @notice Validates that the reward meets the minimum rate requirement
    function _validateReward(uint256 amount, uint16 minRate, uint256 duration, uint256 reward) private pure {
        uint256 minimumReward = (amount * minRate * duration) / (10000 * 365 days);
        if(minimumReward > reward) revert InsufficientReward(minimumReward, reward);
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
        if(deficit > 0) {
            revert InsufficientCoverageAvailable(
                deficit
            );
        }
    }

    function _coverageDeficitAmount(address operator, address strategy, address coverageAgent) private view returns (uint256 deficit) {
        uint256 totalAllocatedCoverage = _totalAllocatedValueToCoverageAgent(operator, strategy, coverageAgent);
        uint256 totalCoverageByOperator = _totalCoverageByOperatorStrategy(operator, strategy, coverageAgent);

        if(totalAllocatedCoverage < totalCoverageByOperator) {
            deficit = totalCoverageByOperator - totalAllocatedCoverage;
        }
    }

    /// @notice Returns the total coverage by an operator for a strategy in the operators asset
    function _totalCoverageByOperatorStrategy(address operator, address strategy, address coverageAgent) private view returns (uint256) {
        (bool exists, uint256 value) = operators[operator].coverageStrategies[strategy].tryGet(coverageAgent);
        if(exists) {
            return value;
        }
        return 0;
    }

    /// @notice Returns the total coverage allocated to a coverage agent for a strategy in the operators asset
    function _totalAllocatedValueToCoverageAgent(address operator, address strategy, address coverageAgent) private view returns (uint256 total) {
        address[] memory _operators = new address[](1);
        _operators[0] = operator;
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = IStrategy(strategy);
        address strategyAsset = address(IStrategy(strategy).underlyingToken());
        address coverageAsset = address(ICoverageAgent(coverageAgent).asset());
        uint256[][] memory allocatedStake = IAllocationManager(_eigenAddresses.allocationManager)
            .getAllocatedStake(OperatorSet({avs: address(this), id: coverageAgentToOperatorSetId[coverageAgent]}), _operators, strategies);
        uint256 quotedPrice = quote(allocatedStake[0][0], strategyAsset, coverageAsset);

        uint8 strategyDecimals = ERC20(strategyAsset).decimals();
        uint8 coverageDecimals = ERC20(coverageAsset).decimals();

        if(strategyDecimals > coverageDecimals) {
            return quotedPrice / (10 ** (strategyDecimals - coverageDecimals));
        } else {
            return quotedPrice * (10 ** (coverageDecimals - strategyDecimals));
        }
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
