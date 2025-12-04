// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NotHandler, CoverageManagerNotActive} from "./Errors.sol";
import {ICoveragePool, CoverageManagerData, PurchaseCoverageRequest, Coverage} from "./interfaces/ICoveragePool.sol";
import {ICoverageManager} from "./interfaces/ICoverageManager.sol";

/// @notice A pool of delegations for a single operator.
/// @dev Each pool acts as a target contract for the restaking networks to delegate to e.g. for Eigen this will be the strategy.
/// Delegators are whitelisted by the operators to ensure they are trusted.
contract CoveragePool is ICoveragePool {
    address public handler;
    mapping(address => CoverageManagerData) private _coverageManagers;
    address[] private _coverageManagerAddresses;

    /// @notice The asset that the coverage pool will distribute as yield
    constructor(address _handler) {
        if (_handler == address(0)) revert NotHandler();
        handler = _handler;
    }

    /// @inheritdoc ICoveragePool
    function registerCoverageManager(address coverageManager) external onlyHandler {
        _coverageManagers[coverageManager] = CoverageManagerData({active: true});
        _coverageManagerAddresses.push(coverageManager);

        ICoverageManager(coverageManager).onIsRegistered();

        emit CoverageManagerRegistered(coverageManager);
    }

    /// @inheritdoc ICoveragePool
    function onRegisterPosition(uint256 positionId) external {
        if(!_coverageManagers[msg.sender].active){
            revert CoverageManagerNotActive();
        }
        emit PositionRegistered(msg.sender, positionId);
    }


    /// @inheritdoc ICoveragePool
    function purchaseCoverage(PurchaseCoverageRequest[] calldata requests) external returns (uint256 coverageId) {
        //TODO: Implement purchaseCoverage
    }

    /// @inheritdoc ICoveragePool
    function registeredCoverageManagers() external view returns (address[] memory) {
        return _coverageManagerAddresses;
    }

    function coverageManagerData(address coverageManager) external view returns (CoverageManagerData memory data) {
        data = _coverageManagers[coverageManager];
    }

    /// @inheritdoc ICoveragePool
    function coverage(uint256 coverageId) external view returns (Coverage memory) {
        //TODO: Implement coverage
    }


    modifier onlyHandler() {
        _onlyHandler();
        _;
    }

    function _onlyHandler() internal view {
        if (msg.sender != handler) revert NotHandler();
    }
}
