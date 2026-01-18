// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OperatorSet} from "eigenlayer-contracts/libraries/OperatorSetLib.sol";
import {IAllocationManager, IAllocationManagerTypes} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IPermissionController} from "eigenlayer-contracts/interfaces/IPermissionController.sol";

import {IEigenServiceManager} from "./interfaces/IEigenServiceManager.sol";
import {IEigenOperatorProxy} from "./interfaces/IEigenOperatorProxy.sol";
import {EigenAddresses} from "./Types.sol";

import {NotOperatorAuthorized, StrategyNotWhitelisted} from "./Errors.sol";

/// @title EigenOperatorProxy
/// @author p-dealwis, Infinality
/// @notice This contract manages the eigen operator as proxy to disable some functionality for operators
/// @dev Not to be confused with the operator entity that is the beneficiary of the delegation pool.
contract EigenOperatorProxy is IEigenOperatorProxy {
    EigenAddresses private _eigenAddresses;

    address private _handler;

    mapping(bytes32 => bool) private _allowlistedDigests;

    /// @notice Initialize the EigenOperator
    /// @param eigenAddresses_ EigenAddresses struct containing all EigenLayer contract addresses
    /// @param handler_ Eigen operator proxies handler
    /// @param operatorMetadata_ Operator metadata URI
    constructor(EigenAddresses memory eigenAddresses_, address handler_, string memory operatorMetadata_) {
        _eigenAddresses = eigenAddresses_;
        _handler = handler_;

        // Register as an operator on delegation manager where anyone can stake to the operator without requiring approval.
        IDelegationManager(_eigenAddresses.delegationManager).registerAsOperator(address(0), 0, operatorMetadata_);

        // Make handler an admin and ensure this contract is an admin as well
        IPermissionController(_eigenAddresses.permissionController).addPendingAdmin(address(this), handler_);
        IPermissionController(_eigenAddresses.permissionController).addPendingAdmin(address(this), address(this));
        IPermissionController(_eigenAddresses.permissionController).acceptAdmin(address(this));
    }

    /// @inheritdoc IEigenOperatorProxy
    function registerCoverageAgent(address serviceManager_, address coverageAgent_, uint16 rewardsSplit_)
        external
        onlyHandler
    {
        uint32 operatorSetId = IEigenServiceManager(serviceManager_).getOperatorSetId(coverageAgent_);
        OperatorSet memory operatorSet = OperatorSet({avs: serviceManager_, id: operatorSetId});

        // Check if already registered to this coverage agent's operator set
        if (IAllocationManager(_eigenAddresses.allocationManager).isMemberOfOperatorSet(address(this), operatorSet)) {
            revert AlreadyRegistered();
        }

        // Build the register params
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = operatorSetId;

        IAllocationManager.RegisterParams memory params =
            IAllocationManagerTypes.RegisterParams({avs: serviceManager_, operatorSetIds: operatorSetIds, data: ""});

        // Register the operator set to the service manager
        IAllocationManager(_eigenAddresses.allocationManager).registerForOperatorSets(address(this), params);

        _setRewardsSplit(serviceManager_, coverageAgent_, rewardsSplit_);
    }

    /// @inheritdoc IEigenOperatorProxy
    function allocate(
        address serviceManager_,
        address coverageAgent_,
        address[] calldata _strategyAddresses,
        uint64[] calldata _magnitudes
    ) external onlyHandler {
        uint32 operatorSetId = IEigenServiceManager(serviceManager_).getOperatorSetId(coverageAgent_);

        // The strategy that the restakers capital is deployed to
        IStrategy[] memory strategies = new IStrategy[](_strategyAddresses.length);
        for (uint256 i = 0; i < _strategyAddresses.length; i++) {
            if (!IEigenServiceManager(serviceManager_).isStrategyWhitelisted(_strategyAddresses[i])) {
                revert StrategyNotWhitelisted(_strategyAddresses[i]);
            }
            strategies[i] = IStrategy(_strategyAddresses[i]);
        }

        // Create the allocation params
        OperatorSet memory operatorSet = OperatorSet({avs: serviceManager_, id: operatorSetId});
        IAllocationManager.AllocateParams[] memory allocations = new IAllocationManager.AllocateParams[](1);
        allocations[0] = IAllocationManagerTypes.AllocateParams({
            operatorSet: operatorSet, strategies: strategies, newMagnitudes: _magnitudes
        });

        // Allocates the operator set. Can only be called after ALLOCATION_CONFIGURATION_DELAY (approximately 17.5 days) has passed since registration.
        IAllocationManager(_eigenAddresses.allocationManager).modifyAllocations(address(this), allocations);
    }

    /// @inheritdoc IEigenOperatorProxy
    function setRewardsSplit(address serviceManager_, address coverageAgent_, uint16 rewardsSplit_) external onlyHandler {
        _setRewardsSplit(serviceManager_, coverageAgent_, rewardsSplit_);
    }

    function _setRewardsSplit(address serviceManager_, address coverageAgent_, uint16 rewardsSplit_) private {
        if (rewardsSplit_ > 10000) revert InvalidRewardsSplit(rewardsSplit_);
        uint32 operatorSetId = IEigenServiceManager(serviceManager_).getOperatorSetId(coverageAgent_);
        OperatorSet memory operatorSet = OperatorSet({avs: serviceManager_, id: operatorSetId});
        IRewardsCoordinator(_eigenAddresses.rewardsCoordinator).setOperatorSetSplit(address(this), operatorSet, rewardsSplit_);
    }

    /// @inheritdoc IEigenOperatorProxy
    function updateOperatorMetadataURI(string calldata _metadataUri) external {
        if (msg.sender != _handler) revert NotOperator();
        IDelegationManager(_eigenAddresses.delegationManager).updateOperatorMetadataURI(address(this), _metadataUri);
    }

    /// @inheritdoc IEigenOperatorProxy
    function handler() external view returns (address) {
        return _handler;
    }

    /// @inheritdoc IEigenOperatorProxy
    function eigenAddresses() external view returns (EigenAddresses memory) {
        return _eigenAddresses;
    }

    function _onlyHandler() internal view {
        if (msg.sender != _handler) revert NotOperatorAuthorized(address(this), msg.sender);
    }

    modifier onlyHandler() {
        _onlyHandler();
        _;
    }
}
