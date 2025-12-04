// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UUPSUpgradeable} from "@openzeppelin-v5/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin-v5/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UpgradeableBeacon} from "@openzeppelin-v5/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin-v5/contracts/proxy/beacon/BeaconProxy.sol";

import {IAllocationManager, IAllocationManagerTypes} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";

import {EigenOperatorProxy} from "./EigenOperatorProxy.sol";
import {EigenAddresses} from "./Types.sol";
import {CoveragePoolAlreadyRegistered, InvalidAVS} from "./Errors.sol";
import {IEigenServiceManager} from "./interfaces/IEigenServiceManager.sol";
import {ICoverageManager, CoveragePosition, CoverageClaim} from "../../interfaces/ICoverageManager.sol";

import {OperatorData} from "./Types.sol";

/// @title EigenCoverageManager
/// @author p-dealwis, Infinality
/// @notice A manager for Eigen delegations
/// @dev Manage delegation strategies to whitelist strategies, distribute rewards and slash operators.
contract EigenCoverageManager is IEigenServiceManager, ICoverageManager, UUPSUpgradeable, OwnableUpgradeable {
    EigenAddresses private _eigenAddresses;
    address public eigenOperatorInstance;

    uint32 private _operatorSetCount = 0;

    mapping(address => uint32) public coveragePoolToOperatorSetId;
    mapping(address => OperatorData) public operators;

    mapping(address => bool) public strategyWhitelist;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner, EigenAddresses memory eigenAddresses_, string memory _metadataURI) external initializer {
        __Ownable_init(_owner);
        _eigenAddresses = eigenAddresses_;

        // Deploy a instance for the upgradeable beacon proxies
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(new EigenOperatorProxy()), address(this));
        eigenOperatorInstance = address(beacon);

        _updateAVSMetadataURI(_metadataURI);
    }

    function eigenAddresses() external view returns (EigenAddresses memory) {
        return _eigenAddresses;
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
    function createPosition(address coveragePool, CoveragePosition memory data) external returns (uint256 positionId) {
        //TODO: Implement createPosition
    }

    /// @inheritdoc ICoverageManager
    function updatePosition(uint256 positionId, CoveragePosition memory data) external {
        //TODO: Implement updatePosition
    }

    /// @inheritdoc ICoverageManager
    function issueCoverage(uint256 positionId, uint256 amount, uint256 duration) external returns (uint256 claimId) {
        //TODO: Implement issueCoverage
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
    function totalCoverage() external view returns (uint256 amount) {
        //TODO: Implement totalCoverage
    }

    /// @inheritdoc ICoverageManager
    function position(uint256 positionId) external view returns (CoveragePosition memory data) {
        //TODO: Implement position
    }

    /// @inheritdoc ICoverageManager
    function claim(uint256 claimId) external view returns (CoverageClaim memory data) {
        //TODO: Implement claim
    }

    

    // ************ IEigenServiceManager implementations ************ //

    /// @inheritdoc IEigenServiceManager
    function registerOperator(address, address _avs, uint32[] calldata, bytes calldata) external {
        if (_avs != address(this)) revert InvalidAVS();
        //TODO: Implement registerOperator
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
    function createdAtEpoch(address operator) external view returns (uint32) {
        return operators[operator].createdAtEpoch;
    }

    /// @inheritdoc IEigenServiceManager
    function calculationIntervalSeconds() external view returns (uint256) {
        return IRewardsCoordinator(_eigenAddresses.rewardsCoordinator).CALCULATION_INTERVAL_SECONDS();
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

    /// @notice Updates the metadata URI for the AVS
    /// @param _metadataUri is the metadata URI for the AVS
    function _updateAVSMetadataURI(string memory _metadataUri) private {
        IAllocationManager(_eigenAddresses.allocationManager).updateAVSMetadataURI(address(this), _metadataUri);
    }
}
