// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20} from "@openzeppelin-v5/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC20} from "@openzeppelin-v5/contracts/token/ERC20/IERC20.sol";
import {EnumerableMap} from "@openzeppelin-v5/contracts/utils/structs/EnumerableMap.sol";
import {ICoverageAgent, ClaimCoverageRequest, Coverage, Claim} from "src/interfaces/ICoverageAgent.sol";
import {ICoverageProvider, CoverageClaim, CoverageClaimStatus} from "src/interfaces/ICoverageProvider.sol";
import {SafeERC20} from "@openzeppelin-v5/contracts/token/ERC20/utils/SafeERC20.sol";
import {IExampleCoverageAgent} from "src/interfaces/IExampleCoverageAgent.sol";
import {ERC165} from "@openzeppelin-v5/contracts/utils/introspection/ERC165.sol";

/// @notice An example implementation of a coverage agent.
/// @dev This is a reference implementation that can be varied for each coordinator.
/// Each pool acts as a target contract for the restaking networks to delegate to e.g. for Eigen this will be the strategy.
/// Delegators are whitelisted by the operators to ensure they are trusted.
contract ExampleCoverageAgent is ICoverageAgent, IExampleCoverageAgent, ERC165 {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    address private immutable _COORDINATOR;
    address private immutable _ASSET;
    EnumerableMap.AddressToUintMap private _coverageProviders;
    Coverage[] private _coverages;

    /// @notice The asset that the coverage agent will distribute as yield
    constructor(address _coordinator, address _coverageAsset, string memory initialMetadataUri) {
        if (_coordinator == address(0)) revert NotCoverageAgentCoordinator();
        _COORDINATOR = _coordinator;
        _ASSET = _coverageAsset;
        emit MetadataUpdated(initialMetadataUri);
    }

    /// @inheritdoc ICoverageAgent
    function registerCoverageProvider(address coverageProvider) external onlyCoordinator {
        _coverageProviders.set(coverageProvider, 1); // 1 represents active (true)

        ICoverageProvider(coverageProvider).onIsRegistered();

        emit CoverageProviderRegistered(coverageProvider);
    }

    /// @inheritdoc ICoverageAgent
    function onRegisterPosition(uint256) external view {
        if (!_coverageProviders.contains(msg.sender)) {
            revert ICoverageAgent.CoverageProviderNotRegistered();
        }
    }

    /// @inheritdoc ICoverageAgent
    function onSlashCompleted(uint256, uint256 slashAmount) external {
        if (!_coverageProviders.contains(msg.sender)) {
            revert ICoverageAgent.CoverageProviderNotRegistered();
        }
        SafeERC20.safeTransfer(IERC20(_ASSET), _COORDINATOR, slashAmount);
    }

    /// @inheritdoc ICoverageAgent
    function onClaimRefunded(uint256, uint256 refundAmount) external {
        if (!_coverageProviders.contains(msg.sender)) {
            revert ICoverageAgent.CoverageProviderNotRegistered();
        }
        SafeERC20.safeTransfer(IERC20(_ASSET), _COORDINATOR, refundAmount);
    }

    /// @notice Purchase coverage from coverage providers.
    /// @dev Can only be called by the coverage agent coordinator. Should track the amount of coverage purchased for future slashing purposes.
    /// @param requests The requests to purchase coverage.
    /// @return coverageId The id of the coverage purchased.
    function purchaseCoverage(ClaimCoverageRequest[] calldata requests)
        external
        onlyCoordinator
        returns (uint256 coverageId)
    {
        coverageId = _coverages.length;

        // Initialize coverage storage
        Coverage storage coverageData = _coverages.push();
        Claim[] storage claims = coverageData.claims;
        coverageData.reservation = false;

        uint256 totalReward = 0;
        for (uint256 i = 0; i < requests.length; i++) {
            totalReward += requests[i].reward;
        }

        // Transfer rewards from coordinator to the coverage agent for all claims
        SafeERC20.safeTransferFrom(IERC20(_ASSET), msg.sender, address(this), totalReward);

        for (uint256 i = 0; i < requests.length; i++) {
            ClaimCoverageRequest memory request = requests[i];

            // Verify coverage provider is registered
            if (!_coverageProviders.contains(request.coverageProvider)) {
                revert ICoverageAgent.CoverageProviderNotRegistered();
            }

            // Approve tokens for the reward
            SafeERC20.forceApprove(IERC20(_ASSET), request.coverageProvider, request.reward);

            // Call issueClaim on the coverage provider
            uint256 claimId = ICoverageProvider(request.coverageProvider)
                .issueClaim(request.positionId, request.amount, request.duration, request.reward);

            // Store the claim
            claims.push(Claim({coverageProvider: request.coverageProvider, claimId: claimId}));
        }

        emit CoverageClaimed(coverageId);
    }

    /// @notice Reserve coverage from coverage providers.
    /// @dev Can only be called by the coverage agent coordinator. Creates reservations without immediate reward payment.
    /// @param requests The requests to reserve coverage.
    /// @return coverageId The id of the reserved coverage.
    function reserveCoverage(ClaimCoverageRequest[] calldata requests)
        external
        onlyCoordinator
        returns (uint256 coverageId)
    {
        coverageId = _coverages.length;

        // Initialize coverage storage
        Coverage storage coverageData = _coverages.push();
        Claim[] storage claims = coverageData.claims;
        coverageData.reservation = true;

        for (uint256 i = 0; i < requests.length; i++) {
            ClaimCoverageRequest memory request = requests[i];

            // Verify coverage provider is registered
            if (!_coverageProviders.contains(request.coverageProvider)) {
                revert ICoverageAgent.CoverageProviderNotRegistered();
            }

            // Call reserveClaim on the coverage provider (no reward transfer yet)
            uint256 claimId = ICoverageProvider(request.coverageProvider)
                .reserveClaim(request.positionId, request.amount, request.duration, request.reward);

            // Store the claim
            claims.push(Claim({coverageProvider: request.coverageProvider, claimId: claimId}));
        }

        emit CoverageReserved(coverageId);
    }

    /// @notice Convert reserved coverage to issued coverage.
    /// @dev Can only be called by the coverage agent coordinator.
    /// @param coverageId The id of the reserved coverage to convert.
    /// @param requests The requests to convert. Only duration, amount, and reward need to be filled.
    ///        coverageProvider and positionId are taken from the original reservation.
    function convertReservedCoverage(uint256 coverageId, ClaimCoverageRequest[] calldata requests)
        external
        onlyCoordinator
    {
        require(coverageId < _coverages.length, InvalidCoverage(coverageId));
        Coverage storage coverageData = _coverages[coverageId];

        // Verify this is a reservation
        if (!coverageData.reservation) {
            revert ICoverageAgent.CoverageNotReservation(coverageId);
        }

        // Verify request length matches claims
        require(requests.length == coverageData.claims.length, InvalidCoverage(coverageId));

        // Calculate total reward needed
        uint256 totalReward = 0;
        for (uint256 i = 0; i < requests.length; i++) {
            totalReward += requests[i].reward;
        }

        // Transfer rewards from coordinator to the coverage agent for all claims
        SafeERC20.safeTransferFrom(IERC20(_ASSET), msg.sender, address(this), totalReward);

        for (uint256 i = 0; i < requests.length; i++) {
            ClaimCoverageRequest memory request = requests[i];
            Claim storage claimData = coverageData.claims[i];

            // Approve tokens for the reward
            SafeERC20.forceApprove(IERC20(_ASSET), claimData.coverageProvider, request.reward);

            // Call convertReservedClaim on the coverage provider
            ICoverageProvider(claimData.coverageProvider)
                .convertReservedClaim(claimData.claimId, request.amount, request.duration, request.reward);
        }

        // Mark as no longer a reservation
        coverageData.reservation = false;

        emit CoverageClaimed(coverageId);
    }

    /// @notice Slash a coverage purchase.
    /// @dev Can only be called by the coverage agent coordinator.
    /// @dev Should slash the coverage purchase and track the amount of coverage slashed for future slashing purposes.
    /// @param coverageId The id of the coverage purchase to slash.
    function slashCoverage(uint256 coverageId)
        external
        onlyCoordinator
        returns (CoverageClaimStatus[] memory slashStatuses)
    {
        require(coverageId < _coverages.length, InvalidCoverage(coverageId));
        Coverage storage coverageData = _coverages[coverageId];
        slashStatuses = new CoverageClaimStatus[](coverageData.claims.length);
        for (uint256 i = 0; i < coverageData.claims.length; i++) {
            CoverageClaim memory claim =
                ICoverageProvider(coverageData.claims[i].coverageProvider).claim(coverageData.claims[i].claimId);
            uint256[] memory claimIds = new uint256[](1);
            uint256[] memory amounts = new uint256[](1);
            claimIds[0] = coverageData.claims[i].claimId;
            amounts[0] = claim.amount;

            CoverageClaimStatus[] memory statuses =
                ICoverageProvider(coverageData.claims[i].coverageProvider).slashClaims(claimIds, amounts);
            slashStatuses[i] = statuses[0];
        }
        return slashStatuses;
    }

    /// @inheritdoc IExampleCoverageAgent
    function updateMetadata(string calldata metadataURI) external onlyCoordinator {
        emit MetadataUpdated(metadataURI);
    }

    /// @inheritdoc ICoverageAgent
    function registeredCoverageProviders() external view returns (address[] memory) {
        return _coverageProviders.keys();
    }

    /// @inheritdoc ICoverageAgent
    function isCoverageProviderRegistered(address coverageProvider) external view returns (bool) {
        return _coverageProviders.contains(coverageProvider);
    }

    /// @inheritdoc ICoverageAgent
    function coverage(uint256 coverageId) external view returns (Coverage memory) {
        require(coverageId < _coverages.length, InvalidCoverage(coverageId));
        return _coverages[coverageId];
    }

    /// @inheritdoc ICoverageAgent
    function asset() external view returns (address) {
        return _ASSET;
    }

    /// @inheritdoc ICoverageAgent
    function coordinator() external view returns (address) {
        return _COORDINATOR;
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IExampleCoverageAgent).interfaceId || interfaceId == type(ICoverageAgent).interfaceId
            || super.supportsInterface(interfaceId);
    }

    modifier onlyCoordinator() {
        _onlyCoordinator();
        _;
    }

    function _onlyCoordinator() internal view {
        if (msg.sender != _COORDINATOR) revert NotCoverageAgentCoordinator();
    }
}
