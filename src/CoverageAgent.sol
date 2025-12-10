// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NotCoverageAgentHandler, CoverageProviderNotActive} from "./Errors.sol";
import {ICoverageAgent, CoverageProviderData, PurchaseCoverageRequest, Coverage} from "./interfaces/ICoverageAgent.sol";
import {ICoverageProvider} from "./interfaces/ICoverageProvider.sol";

/// @notice A pool of delegations for a single operator.
/// @dev Each pool acts as a target contract for the restaking networks to delegate to e.g. for Eigen this will be the strategy.
/// Delegators are whitelisted by the operators to ensure they are trusted.
contract CoverageAgent is ICoverageAgent {
    address private immutable _ENTITY;
    address private immutable _ASSET;
    mapping(address => CoverageProviderData) private _coverageProviders;
    address[] private _coverageProviderAddresses;

    /// @notice The asset that the coverage agent will distribute as yield
    constructor(address _handler, address _coverageAsset) {
        if (_handler == address(0)) revert NotCoverageAgentHandler();
        _ENTITY = _handler;
        _ASSET = _coverageAsset;
    }

    /// @inheritdoc ICoverageAgent
    function registerCoverageProvider(address coverageProvider) external onlyEntity {
        _coverageProviders[coverageProvider] = CoverageProviderData({active: true});
        _coverageProviderAddresses.push(coverageProvider);

        ICoverageProvider(coverageProvider).onIsRegistered();

        emit CoverageProviderRegistered(coverageProvider);
    }

    /// @inheritdoc ICoverageAgent
    function onRegisterPosition(uint256 positionId) external {
        if (!_coverageProviders[msg.sender].active) {
            revert CoverageProviderNotActive();
        }
        emit PositionRegistered(msg.sender, positionId);
    }

    /// @inheritdoc ICoverageAgent
    function purchaseCoverage(PurchaseCoverageRequest[] calldata requests) external returns (uint256 coverageId) {
        //TODO: Implement purchaseCoverage
    }

    /// @inheritdoc ICoverageAgent
    function registeredCoverageProviders() external view returns (address[] memory) {
        return _coverageProviderAddresses;
    }

    function coverageProviderData(address coverageProvider) external view returns (CoverageProviderData memory data) {
        data = _coverageProviders[coverageProvider];
    }

    /// @inheritdoc ICoverageAgent
    function coverage(uint256 coverageId) external view returns (Coverage memory) {
        //TODO: Implement coverage
    }

    /// @inheritdoc ICoverageAgent
    function asset() external view returns (address) {
        return _ASSET;
    }

    /// @inheritdoc ICoverageAgent
    function entity() external view returns (address) {
        return _ENTITY;
    }

    modifier onlyEntity() {
        _onlyEntity();
        _;
    }

    function _onlyEntity() internal view {
        if (msg.sender != _ENTITY) revert NotCoverageAgentHandler();
    }
}
