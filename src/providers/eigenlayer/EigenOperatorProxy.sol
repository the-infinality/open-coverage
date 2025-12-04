// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin-v5/contracts/proxy/utils/Initializable.sol";

import {OperatorSet} from "eigenlayer-contracts/libraries/OperatorSetLib.sol";
import {IAllocationManager, IAllocationManagerTypes} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";

import {IEigenServiceManager} from "./interfaces/IEigenServiceManager.sol";
import {IEigenOperatorProxy} from "./interfaces/IEigenOperatorProxy.sol";
import {EigenAddresses} from "./Types.sol";
import {NotOperatorHandler, StrategyNotWhitelisted} from "./Errors.sol";

/// @title EigenOperatorProxy
/// @author p-dealwis, Infinality
/// @notice This contract manages the eigen operator as proxy to disable some functionality for operators
/// @dev Not to be confused with the operator entity that is the beneficiary of the delegation pool.
contract EigenOperatorProxy is IEigenOperatorProxy, Initializable {
    EigenAddresses public eigenAddresses;

    address private _serviceManager;
    address private _handler;
    uint256 private _totpPeriod;

    mapping(bytes32 => bool) private _allowlistedDigests;

    /// @inheritdoc IEigenOperatorProxy
    function initialize(address serviceManager_, address handler_, string calldata metadataURI_) external initializer {
        _serviceManager = serviceManager_;
        _totpPeriod = 28 days; // Arbitrary value
        _handler = handler_;

        // Fetch the eigen addresses
        eigenAddresses = IEigenServiceManager(_serviceManager).eigenAddresses();

        // Register as an operator on delegation manager where anyone can stake to the operator without requiring approval.
        IDelegationManager(eigenAddresses.delegationManager).registerAsOperator(address(0), 0, metadataURI_);
    }

    /// @inheritdoc IEigenOperatorProxy
    function registerCoveragePool(address coveragePool_, uint16 rewardsSplit_) external onlyHandler {
        // Build the register params
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = IEigenServiceManager(_serviceManager).getOperatorSetId(coveragePool_);

        IAllocationManager.RegisterParams memory params =
            IAllocationManagerTypes.RegisterParams({avs: _serviceManager, operatorSetIds: operatorSetIds, data: ""});

        // 1. Register the operator set to the service manager, which in turn calls RegisterOperator on the Eigen Service Manager
        IAllocationManager(eigenAddresses.allocationManager).registerForOperatorSets(address(this), params);

        // 2. Set the operator split to 0, all rewards go to restakers
        IRewardsCoordinator(eigenAddresses.rewardsCoordinator).setOperatorAVSSplit(address(this), msg.sender, rewardsSplit_);
    }

    /// @inheritdoc IEigenOperatorProxy
    function allocate(address coveragePool_, address[] calldata _strategyAddresses) external onlyHandler {
        uint32 operatorSetId = IEigenServiceManager(_serviceManager).getOperatorSetId(coveragePool_);

        // The strategy that the restakers capital is deployed to
        IStrategy[] memory strategies = new IStrategy[](_strategyAddresses.length);
        for (uint256 i = 0; i < _strategyAddresses.length; i++) {
            if (!IEigenServiceManager(_serviceManager).isStrategyWhitelisted(_strategyAddresses[i])) {
                revert StrategyNotWhitelisted();
            }
            strategies[i] = IStrategy(_strategyAddresses[i]);
        }

        // Only 1 allocation so 1e18 just means everything will be allocated to the avs
        uint64[] memory magnitudes = new uint64[](_strategyAddresses.length);
        for (uint256 i = 0; i < _strategyAddresses.length; i++) {
            magnitudes[i] = 1e18;
        }

        // Create the allocation params
        OperatorSet memory operatorSet = OperatorSet({avs: _serviceManager, id: operatorSetId});
        IAllocationManager.AllocateParams[] memory allocations = new IAllocationManager.AllocateParams[](1);
        allocations[0] = IAllocationManagerTypes.AllocateParams({
            operatorSet: operatorSet, strategies: strategies, newMagnitudes: magnitudes
        });

        // Allocates the operator set. Can only be called after ALLOCATION_CONFIGURATION_DELAY (approximately 17.5 days) has passed since registration.
        IAllocationManager(eigenAddresses.allocationManager).modifyAllocations(address(this), allocations);
    }

    /// @inheritdoc IEigenOperatorProxy
    function updateOperatorMetadataURI(string calldata _metadataUri) external {
        if (msg.sender != _handler) revert NotOperator();
        IDelegationManager(eigenAddresses.delegationManager).updateOperatorMetadataURI(address(this), _metadataUri);
    }

    /// @inheritdoc IEigenOperatorProxy
    function eigenServiceManager() external view returns (address) {
        return _serviceManager;
    }

    /// @inheritdoc IEigenOperatorProxy
    function handler() external view returns (address) {
        return _handler;
    }

    function _onlyHandler() internal view {
        if (msg.sender != _handler) revert NotOperatorHandler();
    }

    modifier onlyHandler() {
        _onlyHandler();
        _;
    }
}
