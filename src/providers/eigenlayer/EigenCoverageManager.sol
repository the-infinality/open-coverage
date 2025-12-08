// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UUPSUpgradeable} from "@openzeppelin-v5/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin-v5/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UpgradeableBeacon} from "@openzeppelin-v5/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin-v5/contracts/proxy/beacon/BeaconProxy.sol";

import {IAllocationManager, IAllocationManagerTypes} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";
import {OperatorSet} from "eigenlayer-contracts/libraries/OperatorSetLib.sol";

import {EigenOperatorProxy} from "./EigenOperatorProxy.sol";
import {EigenAddresses} from "./Types.sol";
import {CoveragePoolAlreadyRegistered, InvalidAVS, NotOperatorHandler, InvalidAsset, NotAllocated} from "./Errors.sol";
import {IEigenServiceManager, CreatePositionAddtionalData, EigenCoveragePosition, OperatorData} from "./interfaces/IEigenServiceManager.sol";
import {IEigenOperatorProxy} from "./interfaces/IEigenOperatorProxy.sol";
import {ICoverageManager, CoveragePosition, CoverageClaim, CoverageClaimStatus} from "../../interfaces/ICoverageManager.sol";
import {ICoveragePool} from "../../interfaces/ICoveragePool.sol";


/// @title EigenCoverageManager
/// @author p-dealwis, Infinality
/// @notice A manager for Eigen delegations
/// @dev Manage delegation strategies to whitelist strategies, distribute rewards and slash operators.
contract EigenCoverageManager is IEigenServiceManager, ICoverageManager, UUPSUpgradeable, OwnableUpgradeable {
    EigenAddresses private _eigenAddresses;
    address public eigenOperatorInstance;

    uint32 private _operatorSetCount = 0;

    EigenCoveragePosition[] public positions;
    CoverageClaim[] public claims;

    mapping(address => uint32) public coveragePoolToOperatorSetId;

    mapping(address => bool) public strategyWhitelist;

    mapping(address => OperatorData) public operators;


    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }


    /// ============ Upgradeability ============ //

    function initialize(address _owner, EigenAddresses memory eigenAddresses_, string memory _metadataURI) external initializer {
        __Ownable_init(_owner);
        _eigenAddresses = eigenAddresses_;

        // Deploy a instance for the upgradeable beacon proxies
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(new EigenOperatorProxy()), address(this));
        eigenOperatorInstance = address(beacon);

        _updateAVSMetadataURI(_metadataURI);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        // Only owner can upgrade
    }


    /// ============ ICoverageManager implementations ============ //

    /// @inheritdoc ICoverageManager
    function onIsRegistered() external {
        if (coveragePoolToOperatorSetId[msg.sender] != 0) revert CoveragePoolAlreadyRegistered();

        IAllocationManagerTypes.CreateSetParams[] memory params = new IAllocationManager.CreateSetParams[](1);

        uint32 operatorSetId = ++_operatorSetCount;

        // Setup a new operator set with the default predefined strategies
        params[0] =
            IAllocationManagerTypes.CreateSetParams({operatorSetId: operatorSetId, strategies: new IStrategy[](0)});

        address[] memory redistributionRecipients = new address[](1);
        redistributionRecipients[0] = msg.sender;

        IAllocationManager(_eigenAddresses.allocationManager)
            .createRedistributingOperatorSets(address(this), params, redistributionRecipients);

        coveragePoolToOperatorSetId[msg.sender] = operatorSetId;
    }

    /// @inheritdoc ICoverageManager
    function createPosition(address coveragePool, CoveragePosition memory data, bytes calldata additionalData) external returns (uint256 positionId) {
        _validatePositionData(data);

        CreatePositionAddtionalData memory createPositionAddtionalData = abi.decode(additionalData, (CreatePositionAddtionalData));
        if(IEigenOperatorProxy(createPositionAddtionalData.operatorProxy).handler() != msg.sender) revert NotOperatorHandler(createPositionAddtionalData.operatorProxy, msg.sender);
        if(address(IStrategy(createPositionAddtionalData.strategy).underlyingToken()) != data.asset) revert InvalidAsset(createPositionAddtionalData.strategy, data.asset);

        // Make sure operator has strategy allocations to the operator set for the coverage pool
        uint32 operatorSetId = coveragePoolToOperatorSetId[coveragePool];
        OperatorSet memory operatorSet = OperatorSet({avs: address(this), id: operatorSetId});
        IAllocationManagerTypes.Allocation memory allocation = IAllocationManager(_eigenAddresses.allocationManager).getAllocation(createPositionAddtionalData.operatorProxy, operatorSet, IStrategy(createPositionAddtionalData.strategy));

        if(allocation.currentMagnitude == 0) revert NotAllocated();

        positionId = _registerPosition(coveragePool, data, createPositionAddtionalData);
    }

    /// @inheritdoc ICoverageManager
    function updatePosition(uint256 positionId, CoveragePosition memory data) external {
        _validatePositionData(data);
        positions[positionId].data = data;
        emit PositionUpdated(positionId);
    }

    /// @inheritdoc ICoverageManager
    function issueCoverage(uint256 positionId, uint256 amount, uint256 duration, address paymentAsset, uint256 paymentAmount) external returns (uint256 claimId) {
        // Calculate the premium amount based on duration and min rate
        EigenCoveragePosition storage positionData = positions[positionId];
        uint16 minRate = positionData.data.minRate; // in basis points per annum (1e4 = 100%)

        uint256 minimumPremium = (amount * minRate * duration) / (10000 * 365 days);

        uint256 premiumInPositionAsset;

        // Skip conversion if the payment asset is the same as the position asset
        if(positionData.data.asset != paymentAsset) {
            // TODO: get premium
        } else {
            premiumInPositionAsset = paymentAmount;
        }

        // paymentAmount check can be enforced if required
        require(premiumInPositionAsset < minimumPremium, "Insufficient payment amount for premium");

        // Placeholder for rest of the logic: minting claim, storing claim, transferring payment, etc.
        // TODO: Implement full issueCoverage logic
        claims.push(CoverageClaim({positionId: positionId, amount: amount, duration: duration, status: CoverageClaimStatus.Issued}));
        operators[positionData.operatorProxy].coveragePoolAmount[positionData.coveragePool] += premiumInPositionAsset;
    }

    /// @inheritdoc ICoverageManager
    function liquidateClaim(uint256 claimId) external {
        //TODO: Implement liquidateClaim
    }

    /// @inheritdoc ICoverageManager
    function completeClaims(uint256 claimId) external {
        //TODO: Implement completeClaims
    }

    /// @inheritdoc ICoverageManager
    function slashClaims(uint256[] calldata claimIds, uint256[] calldata amounts) external {
        //TODO: Implement slashClaims
    }

    /// @inheritdoc ICoverageManager
    function totalCoverageByPool(address coveragePool) external view returns (uint256 amount) {
        //TODO: Implement totalCoverageByPool
    }

    /// @inheritdoc ICoverageManager
    function position(uint256 positionId) external view returns (CoveragePosition memory) {
        return positions[positionId].data;
    }

    /// @inheritdoc ICoverageManager
    function claim(uint256 claimId) external view returns (CoverageClaim memory data) {
        //TODO: Implement claim
    }

    // ============ IEigenServiceManager implementations ============ //

    /// @inheritdoc IEigenServiceManager
    function registerOperator(address, address _avs, uint32[] calldata, bytes calldata) external {
        require(msg.sender != _eigenAddresses.delegationManager, "Not delegation manager");
        if (_avs != address(this)) revert InvalidAVS();
    }

    /// @inheritdoc IEigenServiceManager
    function createOperatorProxy(string calldata _operatorMetadata)
        external
        returns (address operator)
    {
        // Best practice initialize on deployment
        bytes memory initdata = abi.encodeWithSelector(
            EigenOperatorProxy.initialize.selector, address(this), msg.sender, _operatorMetadata
        );
        operator = address(new BeaconProxy(eigenOperatorInstance, initdata));
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
    function getOperatorSetId(address coveragePool) external view returns (uint32) {
        return coveragePoolToOperatorSetId[coveragePool];
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

    function _registerPosition(address coveragePool, CoveragePosition memory data, CreatePositionAddtionalData memory createPositionAddtionalData) private returns (uint256 positionId) {
        positions.push(EigenCoveragePosition({data: data, operatorProxy: createPositionAddtionalData.operatorProxy, strategy: createPositionAddtionalData.strategy, coveragePool: coveragePool}));
        positionId = positions.length - 1;

        emit PositionCreated(positionId);

        // Notify the coverage pool that the position has been registered
        ICoveragePool(coveragePool).onRegisterPosition(positionId);
    }

    function _validatePositionData(CoveragePosition memory data) private view {
        if(data.expiryTimestamp < block.timestamp) revert TimestampInvalid(data.expiryTimestamp);
        if(data.minRate > 10000) revert MinRateInvalid(data.minRate);
    }
}
