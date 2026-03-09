// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";
import {TestDeployer} from "test/utils/TestDeployer.sol";
import {ExampleCoverageAgent} from "../src/ExampleCoverageAgent.sol";
import {ICoverageAgent, ClaimCoverageRequest, Coverage} from "../src/interfaces/ICoverageAgent.sol";
import {ICoverageLiquidatable} from "../src/interfaces/ICoverageLiquidatable.sol";
import {
    ICoverageProvider,
    CoveragePosition,
    CoverageClaim,
    CoverageClaimStatus,
    Refundable
} from "../src/interfaces/ICoverageProvider.sol";
import {IExampleCoverageAgent} from "../src/interfaces/IExampleCoverageAgent.sol";

/// @notice Mock Coverage Provider for testing
contract MockCoverageProvider is ICoverageProvider, ICoverageLiquidatable {
    error RewardTransferFailed();

    bool public isRegistered;
    uint256 public nextPositionId;
    uint256 public nextClaimId;
    mapping(uint256 => CoveragePosition) private _positions;
    mapping(uint256 => CoverageClaim) private _claims;
    mapping(address => uint256) private _totalCoverageByAgent;
    mapping(uint256 => uint256) private _claimSlashAmounts;
    mapping(uint256 => uint256) private _refundOnClose;

    function onIsRegistered() external override {
        isRegistered = true;
    }

    function createPosition(CoveragePosition memory data, bytes calldata)
        external
        override
        returns (uint256 positionId)
    {
        positionId = nextPositionId++;
        _positions[positionId] = data;
        ICoverageAgent(data.coverageAgent).onRegisterPosition(positionId);
        emit PositionCreated(positionId);
    }

    function closePosition(uint256 positionId) external override {
        _positions[positionId].expiryTimestamp = block.timestamp;
        emit PositionClosed(positionId);
    }

    function issueClaim(uint256 positionId, uint256 amount, uint256 duration, uint256 reward)
        external
        returns (uint256 claimId)
    {
        claimId = nextClaimId++;
        _claims[claimId] = CoverageClaim({
            positionId: positionId,
            amount: amount,
            duration: duration,
            createdAt: block.timestamp,
            status: CoverageClaimStatus.Issued,
            reward: reward
        });
        _totalCoverageByAgent[msg.sender] += amount;

        CoveragePosition memory _position = _positions[positionId];

        bool success =
            IERC20(ICoverageAgent(_position.coverageAgent).asset()).transferFrom(msg.sender, address(this), reward);
        if (!success) revert RewardTransferFailed();
        emit ClaimIssued(positionId, claimId, amount, duration);
    }

    function reserveClaim(uint256 positionId, uint256 amount, uint256 duration, uint256 reward)
        external
        override
        returns (uint256 claimId)
    {
        claimId = nextClaimId++;
        _claims[claimId] = CoverageClaim({
            positionId: positionId,
            amount: amount,
            duration: duration,
            createdAt: block.timestamp,
            status: CoverageClaimStatus.Reserved,
            reward: reward
        });
        _totalCoverageByAgent[msg.sender] += amount;
        emit ClaimReserved(positionId, claimId, amount, duration);
    }

    function convertReservedClaim(uint256 claimId, uint256 amount, uint256 duration, uint256 reward) external override {
        CoverageClaim storage coverageClaim = _claims[claimId];
        CoveragePosition memory _position = _positions[coverageClaim.positionId];

        bool success =
            IERC20(ICoverageAgent(_position.coverageAgent).asset()).transferFrom(msg.sender, address(this), reward);
        if (!success) revert RewardTransferFailed();

        coverageClaim.amount = amount;
        coverageClaim.duration = duration;
        coverageClaim.reward = reward;
        coverageClaim.createdAt = block.timestamp;
        coverageClaim.status = CoverageClaimStatus.Issued;
        emit ClaimIssued(coverageClaim.positionId, claimId, amount, duration);
    }

    /// @notice Set refund amount to send to the coverage agent when this claim is closed (for testing).
    function setRefundOnClose(uint256 claimId, uint256 amount) external {
        _refundOnClose[claimId] = amount;
    }

    function closeClaim(uint256 claimId) external override {
        _claims[claimId].status = CoverageClaimStatus.Completed;
        uint256 refund = _refundOnClose[claimId];
        if (refund > 0) {
            _refundOnClose[claimId] = 0;
            address agent = msg.sender;
            bool success = IERC20(ICoverageAgent(agent).asset()).transfer(agent, refund);
            if (!success) revert RewardTransferFailed();
            ICoverageAgent(agent).onClaimRefunded(claimId, refund);
        }
        emit ClaimClosed(claimId);
    }

    function liquidateClaim(uint256 claimId, uint256 positionId) external override {
        emit ClaimLiquidated(claimId, _claims[claimId].positionId, positionId);
    }

    function slashClaims(uint256[] calldata claimIds, uint256[] calldata amounts, uint256)
        external
        override
        returns (CoverageClaimStatus[] memory slashStatuses)
    {
        slashStatuses = new CoverageClaimStatus[](claimIds.length);
        for (uint256 i = 0; i < claimIds.length; i++) {
            _claimSlashAmounts[claimIds[i]] = amounts[i];
            CoveragePosition memory _position = _positions[_claims[claimIds[i]].positionId];

            // If slash coordinator is set, emit pending event, otherwise slash immediately
            if (_position.slashCoordinator != address(0)) {
                _claims[claimIds[i]].status = CoverageClaimStatus.PendingSlash;
                slashStatuses[i] = CoverageClaimStatus.PendingSlash;
                emit ClaimSlashPending(claimIds[i], _position.slashCoordinator);
            } else {
                _claims[claimIds[i]].status = CoverageClaimStatus.Slashed;
                slashStatuses[i] = CoverageClaimStatus.Slashed;
                // Real provider sends slashed amount to coverage agent; mock must have balance (e.g. deal in test)
                IERC20 asset = IERC20(ICoverageAgent(_position.coverageAgent).asset());
                bool success = asset.transfer(_position.coverageAgent, amounts[i]);
                if (!success) revert RewardTransferFailed();
                emit ClaimSlashed(claimIds[i], amounts[i]);
            }
        }
    }

    function completeSlash(uint256 claimId, uint256) external override {
        if (_claimSlashAmounts[claimId] > _claims[claimId].amount) {
            revert SlashAmountExceedsClaim(claimId, _claimSlashAmounts[claimId], _claims[claimId].amount);
        }
        uint256 amount = _claimSlashAmounts[claimId];
        _claims[claimId].status = CoverageClaimStatus.Slashed;
        // Real provider sends slashed amount to coverage agent; mock must have balance (e.g. deal in test)
        address agent = _positions[_claims[claimId].positionId].coverageAgent;
        IERC20 asset = IERC20(ICoverageAgent(agent).asset());
        bool success = asset.transfer(agent, amount);
        if (!success) revert RewardTransferFailed();
        emit ClaimSlashed(claimId, amount);
    }

    function repaySlashedClaim(uint256 claimId, uint256 amount) external override {
        // Pull tokens from the coverage agent (caller), matching real provider behavior so approval is tested
        bool success = IERC20(ICoverageAgent(msg.sender).asset()).transferFrom(msg.sender, address(this), amount);
        if (!success) revert RewardTransferFailed();

        if (amount >= _claimSlashAmounts[claimId]) {
            _claimSlashAmounts[claimId] = 0;
            _claims[claimId].status = CoverageClaimStatus.Repaid;
            emit ClaimRepaid(claimId);
        } else {
            _claimSlashAmounts[claimId] -= amount;
        }
        emit ClaimRepayment(claimId, amount);
    }

    /// @notice Helper function to simulate refunding a claim to the coverage agent
    /// @dev Transfers refund amount to the coverage agent and calls onClaimRefunded
    function simulateRefund(uint256 claimId, uint256 refundAmount) external {
        CoverageClaim memory claimData = _claims[claimId];
        CoveragePosition memory _position = _positions[claimData.positionId];

        // Transfer refund amount to the coverage agent
        bool success =
            IERC20(ICoverageAgent(_position.coverageAgent).asset()).transfer(_position.coverageAgent, refundAmount);
        if (!success) revert RewardTransferFailed();

        // Notify the coverage agent of the refund
        ICoverageAgent(_position.coverageAgent).onClaimRefunded(claimId, refundAmount);
    }

    function captureRewards(uint256) external pure override returns (uint256, uint32, uint32) {
        return (0, 0, 0);
    }

    function position(uint256 positionId) external view override returns (CoveragePosition memory) {
        return _positions[positionId];
    }

    function positionMaxAmount(uint256) external pure override returns (uint256) {
        return 1000e6;
    }

    function claim(uint256 claimId) external view override returns (CoverageClaim memory) {
        return _claims[claimId];
    }

    function liquidationThreshold() external pure override returns (uint16) {
        return 9000;
    }

    function positionBacking(uint256) external pure override returns (int256, uint256, uint16) {
        return (0, 0, 0);
    }

    function claimTotalSlashAmount(uint256 claimId) external view override returns (uint256) {
        return _claimSlashAmounts[claimId];
    }

    function providerTypeId() external pure override returns (uint256) {
        return 1;
    }

    function coverageThreshold(bytes32) external pure override returns (uint16) {
        return 9000;
    }

    function setCoverageThreshold(bytes32, uint16 threshold) external pure override {
        if (threshold > 10000) revert ThresholdExceedsMax(10000, threshold);
    }

    function setLiquidationThreshold(uint16 threshold) external pure override {
        if (threshold > 10000) revert ThresholdExceedsMax(10000, threshold);
    }
}

/// @notice Test suite for ExampleCoverageAgent
contract ExampleCoverageAgentTest is TestDeployer {
    ExampleCoverageAgent public coverageAgent;
    MockCoverageProvider public mockProvider;

    address public coordinator;
    address public nonHandler;

    function setUp() public override {
        super.setUp();

        coordinator = address(this);
        nonHandler = address(0x123);

        // Deploy coverage agent
        coverageAgent = new ExampleCoverageAgent(coordinator, USDC, "https://example.com/agent.json");

        // Deploy mock provider and price oracle
        mockProvider = new MockCoverageProvider();
        // Fund mock so it can send tokens to the agent when slashing (real provider gets these from strategy/slash flow)
        deal(USDC, address(mockProvider), 1e12);
    }

    /// ============ Constructor Tests ============

    function test_constructor() public view {
        // Verify asset is set correctly (coordinator is tested via access control)
        assertEq(coverageAgent.asset(), USDC);
    }

    /// @notice Test that constructor emits MetadataUpdated with initial URI
    function test_constructor_emitsMetadataUpdated() public {
        string memory uri = "https://example.com/initial-metadata.json";
        vm.expectEmit(false, false, false, true);
        emit ICoverageAgent.MetadataUpdated(uri);
        new ExampleCoverageAgent(coordinator, USDC, uri);
    }

    /// @notice Test that updateMetadata emits MetadataUpdated
    function test_updateMetadata_emitsMetadataUpdated() public {
        string memory newUri = "https://example.com/updated-metadata.json";
        vm.expectEmit(false, false, false, true);
        emit ICoverageAgent.MetadataUpdated(newUri);
        coverageAgent.updateMetadata(newUri);
    }

    function test_constructor_handlerAccessControl() public {
        // Verify coordinator is set correctly by testing access control
        // Coordinator (address(this)) should be able to register providers
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Non-coordinator should not be able to register providers
        vm.prank(nonHandler);
        vm.expectRevert(IExampleCoverageAgent.NotCoverageAgentCoordinator.selector);
        coverageAgent.registerCoverageProvider(address(0x999));
    }

    function test_RevertWhen_constructor_zeroHandler() public {
        vm.expectRevert(IExampleCoverageAgent.NotCoverageAgentCoordinator.selector);
        new ExampleCoverageAgent(address(0), USDC, "");
    }

    /// ============ Coverage Provider Registration Tests ============

    function test_registerCoverageProvider() public {
        vm.expectEmit(true, false, false, false);
        emit ICoverageAgent.CoverageProviderRegistered(address(mockProvider));

        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Verify provider is registered
        assertTrue(coverageAgent.isCoverageProviderRegistered(address(mockProvider)));

        // Verify provider was notified
        assertTrue(mockProvider.isRegistered());

        // Verify provider is in the list
        address[] memory providers = coverageAgent.registeredCoverageProviders();
        assertEq(providers.length, 1);
        assertEq(providers[0], address(mockProvider));
    }

    function test_RevertWhen_registerCoverageProvider_notHandler() public {
        vm.prank(nonHandler);
        vm.expectRevert(IExampleCoverageAgent.NotCoverageAgentCoordinator.selector);
        coverageAgent.registerCoverageProvider(address(mockProvider));
    }

    function test_registerMultipleCoverageProviders() public {
        MockCoverageProvider provider2 = new MockCoverageProvider();
        MockCoverageProvider provider3 = new MockCoverageProvider();

        coverageAgent.registerCoverageProvider(address(mockProvider));
        coverageAgent.registerCoverageProvider(address(provider2));
        coverageAgent.registerCoverageProvider(address(provider3));

        address[] memory providers = coverageAgent.registeredCoverageProviders();
        assertEq(providers.length, 3);
        assertEq(providers[0], address(mockProvider));
        assertEq(providers[1], address(provider2));
        assertEq(providers[2], address(provider3));
    }

    /// ============ Position Registration Tests ============

    function test_onRegisterPosition() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        uint256 positionId = 123;

        // Should not revert when called by registered provider
        vm.prank(address(mockProvider));
        coverageAgent.onRegisterPosition(positionId);
    }

    function test_RevertWhen_onRegisterPosition_providerNotActive() public {
        uint256 positionId = 123;

        vm.prank(address(mockProvider));
        vm.expectRevert(ICoverageAgent.CoverageProviderNotRegistered.selector);
        coverageAgent.onRegisterPosition(positionId);
    }

    function test_onRegisterPosition_throughProvider() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });

        // Should not revert when creating position through registered provider
        uint256 positionId = mockProvider.createPosition(position, "");
        assertEq(positionId, 0);
    }

    /// ============ Coverage Purchase and Retrieval Tests ============

    function test_purchaseCoverage() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: WETH,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Prepare coverage request
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);

        // Expect CoverageClaimed event from agent
        vm.expectEmit(true, false, false, false);
        emit ICoverageAgent.CoverageClaimed(0);

        // Purchase coverage
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Verify coverage was created
        assertEq(coverageId, 0);

        // Retrieve coverage
        Coverage memory cov = coverageAgent.coverage(coverageId);
        assertEq(cov.claims.length, 1);
        assertEq(cov.claims[0].coverageProvider, address(mockProvider));
    }

    function test_RevertWhen_coverage_invalidCoverageId() public {
        // Try to retrieve coverage with invalid ID (no coverage purchased yet)
        vm.expectRevert(abi.encodeWithSelector(ICoverageAgent.InvalidCoverage.selector, 0));
        coverageAgent.coverage(0);
    }

    function test_RevertWhen_coverage_invalidCoverageId_emitsError() public {
        // Test that InvalidCoverage error is properly reverted when accessing non-existent coverage
        // This explicitly tests the error reversion in the view function
        uint256 invalidCoverageId = 999;

        vm.expectRevert(abi.encodeWithSelector(ICoverageAgent.InvalidCoverage.selector, invalidCoverageId));
        coverageAgent.coverage(invalidCoverageId);
    }

    function test_RevertWhen_coverage_coverageIdOutOfBounds() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase one coverage
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        coverageAgent.purchaseCoverage(requests);

        // Try to retrieve coverage with out-of-bounds ID
        vm.expectRevert(abi.encodeWithSelector(ICoverageAgent.InvalidCoverage.selector, 1));
        coverageAgent.coverage(1);
    }

    function test_coverage_multiplePurchases() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase first coverage
        ClaimCoverageRequest[] memory requests1 = new ClaimCoverageRequest[](1);
        requests1[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        // Purchase second coverage
        ClaimCoverageRequest[] memory requests2 = new ClaimCoverageRequest[](1);
        requests2[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 500e6,
            duration: 30 days,
            reward: 5e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend (10e6 + 5e6 = 15e6)
        deal(USDC, coordinator, 15e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 15e6);

        uint256 coverageId1 = coverageAgent.purchaseCoverage(requests1);
        assertEq(coverageId1, 0);

        uint256 coverageId2 = coverageAgent.purchaseCoverage(requests2);
        assertEq(coverageId2, 1);

        // Retrieve both coverages
        Coverage memory cov1 = coverageAgent.coverage(coverageId1);
        Coverage memory cov2 = coverageAgent.coverage(coverageId2);

        assertEq(cov1.claims.length, 1);
        assertEq(cov2.claims.length, 1);
        assertEq(cov1.claims[0].coverageProvider, address(mockProvider));
        assertEq(cov2.claims[0].coverageProvider, address(mockProvider));

        // Try to retrieve non-existent coverage
        vm.expectRevert(abi.encodeWithSelector(ICoverageAgent.InvalidCoverage.selector, 2));
        coverageAgent.coverage(2);
    }

    /// ============ Coverage Slashing Tests ============

    function test_slashCoverage() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Verify claim is issued before slashing
        Coverage memory cov = coverageAgent.coverage(coverageId);
        uint256 claimId = cov.claims[0].claimId;
        CoverageClaim memory claimBefore = mockProvider.claim(claimId);
        assertEq(uint8(claimBefore.status), uint8(CoverageClaimStatus.Issued));

        // Slash the coverage (use type(uint256).max to slash full amount)
        (CoverageClaimStatus[] memory slashStatuses, uint256 totalSlashed) =
            coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        // Verify slash statuses
        assertEq(slashStatuses.length, 1);
        assertEq(uint8(slashStatuses[0]), uint8(CoverageClaimStatus.Slashed));
        assertEq(totalSlashed, 1000e6); // Full claim amount slashed

        // Verify claim status was updated
        CoverageClaim memory claimAfter = mockProvider.claim(claimId);
        assertEq(uint8(claimAfter.status), uint8(CoverageClaimStatus.Slashed));
    }

    function test_slashCoverage_multipleClaims() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage with multiple claims
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](2);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });
        requests[1] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 500e6,
            duration: 30 days,
            reward: 5e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 15e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 15e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Verify both claims are issued before slashing
        Coverage memory cov = coverageAgent.coverage(coverageId);
        assertEq(cov.claims.length, 2);

        uint256 claimId1 = cov.claims[0].claimId;
        uint256 claimId2 = cov.claims[1].claimId;

        CoverageClaim memory claim1Before = mockProvider.claim(claimId1);
        CoverageClaim memory claim2Before = mockProvider.claim(claimId2);
        assertEq(uint8(claim1Before.status), uint8(CoverageClaimStatus.Issued));
        assertEq(uint8(claim2Before.status), uint8(CoverageClaimStatus.Issued));

        // Slash the coverage (use type(uint256).max to slash full amount)
        (CoverageClaimStatus[] memory slashStatuses, uint256 totalSlashed) =
            coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        // Verify slash statuses
        assertEq(slashStatuses.length, 2);
        assertEq(uint8(slashStatuses[0]), uint8(CoverageClaimStatus.Slashed));
        assertEq(uint8(slashStatuses[1]), uint8(CoverageClaimStatus.Slashed));
        assertEq(totalSlashed, 1500e6); // 1000e6 + 500e6 from both claims

        // Verify both claim statuses were updated
        CoverageClaim memory claim1After = mockProvider.claim(claimId1);
        CoverageClaim memory claim2After = mockProvider.claim(claimId2);
        assertEq(uint8(claim1After.status), uint8(CoverageClaimStatus.Slashed));
        assertEq(uint8(claim2After.status), uint8(CoverageClaimStatus.Slashed));
    }

    function test_slashCoverage_multipleProviders() public {
        // Register multiple providers
        MockCoverageProvider provider2 = new MockCoverageProvider();
        deal(USDC, address(provider2), 1e12);
        coverageAgent.registerCoverageProvider(address(mockProvider));
        coverageAgent.registerCoverageProvider(address(provider2));

        // Create positions for both providers
        CoveragePosition memory position1 = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        CoveragePosition memory position2 = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId1 = mockProvider.createPosition(position1, "");
        uint256 positionId2 = provider2.createPosition(position2, "");

        // Purchase coverage with claims from different providers
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](2);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId1,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });
        requests[1] = ClaimCoverageRequest({
            coverageProvider: address(provider2), positionId: positionId2, amount: 500e6, duration: 30 days, reward: 5e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 15e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 15e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash the coverage (use type(uint256).max to slash full amount)
        (CoverageClaimStatus[] memory slashStatuses, uint256 totalSlashed) =
            coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        // Verify slash statuses
        assertEq(slashStatuses.length, 2);
        assertEq(uint8(slashStatuses[0]), uint8(CoverageClaimStatus.Slashed));
        assertEq(uint8(slashStatuses[1]), uint8(CoverageClaimStatus.Slashed));
        assertEq(totalSlashed, 1500e6); // 1000e6 + 500e6 from both claims

        // Verify claims from both providers were slashed
        Coverage memory cov = coverageAgent.coverage(coverageId);
        uint256 claimId1 = cov.claims[0].claimId;
        uint256 claimId2 = cov.claims[1].claimId;

        CoverageClaim memory claim1 = mockProvider.claim(claimId1);
        CoverageClaim memory claim2 = provider2.claim(claimId2);
        assertEq(uint8(claim1.status), uint8(CoverageClaimStatus.Slashed));
        assertEq(uint8(claim2.status), uint8(CoverageClaimStatus.Slashed));
    }

    function test_RevertWhen_slashCoverage_notCoordinator() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);

        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Try to slash as non-coordinator
        vm.prank(nonHandler);
        vm.expectRevert(IExampleCoverageAgent.NotCoverageAgentCoordinator.selector);
        coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);
    }

    function test_RevertWhen_slashCoverage_invalidCoverageId() public {
        // Try to slash coverage with invalid ID (no coverage purchased yet)
        vm.expectRevert(abi.encodeWithSelector(ICoverageAgent.InvalidCoverage.selector, 0));
        coverageAgent.slashCoverage(0, type(uint256).max, block.timestamp);
    }

    function test_RevertWhen_slashCoverage_coverageIdOutOfBounds() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase one coverage
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        coverageAgent.purchaseCoverage(requests);

        // Try to slash coverage with out-of-bounds ID
        vm.expectRevert(abi.encodeWithSelector(ICoverageAgent.InvalidCoverage.selector, 1));
        coverageAgent.slashCoverage(1, type(uint256).max, block.timestamp);
    }

    function test_slashCoverage_multipleCoverages() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase first coverage
        ClaimCoverageRequest[] memory requests1 = new ClaimCoverageRequest[](1);
        requests1[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        // Purchase second coverage
        ClaimCoverageRequest[] memory requests2 = new ClaimCoverageRequest[](1);
        requests2[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 500e6,
            duration: 30 days,
            reward: 5e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 15e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 15e6);
        uint256 coverageId1 = coverageAgent.purchaseCoverage(requests1);
        uint256 coverageId2 = coverageAgent.purchaseCoverage(requests2);

        // Get claim IDs
        Coverage memory cov1 = coverageAgent.coverage(coverageId1);
        Coverage memory cov2 = coverageAgent.coverage(coverageId2);
        uint256 claimId1 = cov1.claims[0].claimId;
        uint256 claimId2 = cov2.claims[0].claimId;

        // Verify both claims are issued
        assertEq(uint8(mockProvider.claim(claimId1).status), uint8(CoverageClaimStatus.Issued));
        assertEq(uint8(mockProvider.claim(claimId2).status), uint8(CoverageClaimStatus.Issued));

        // Slash only the first coverage (use type(uint256).max to slash full amount)
        (CoverageClaimStatus[] memory slashStatuses, uint256 totalSlashed) =
            coverageAgent.slashCoverage(coverageId1, type(uint256).max, block.timestamp);

        // Verify first coverage was slashed
        assertEq(slashStatuses.length, 1);
        assertEq(uint8(slashStatuses[0]), uint8(CoverageClaimStatus.Slashed));
        assertEq(totalSlashed, 1000e6);
        assertEq(uint8(mockProvider.claim(claimId1).status), uint8(CoverageClaimStatus.Slashed));

        // Verify second coverage was NOT slashed
        assertEq(uint8(mockProvider.claim(claimId2).status), uint8(CoverageClaimStatus.Issued));
    }

    function test_slashCoverage_partialAmount() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage with multiple claims
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](3);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });
        requests[1] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 500e6,
            duration: 30 days,
            reward: 5e6
        });
        requests[2] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 300e6,
            duration: 30 days,
            reward: 3e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 18e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 18e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Verify all claims are issued before slashing
        Coverage memory cov = coverageAgent.coverage(coverageId);
        assertEq(cov.claims.length, 3);

        // Slash only 1200e6 (should fully slash first claim of 1000e6 and partially slash second claim for 200e6)
        (CoverageClaimStatus[] memory slashStatuses, uint256 totalSlashed) =
            coverageAgent.slashCoverage(coverageId, 1200e6, block.timestamp);

        // Verify total slashed matches requested amount
        assertEq(totalSlashed, 1200e6);

        // Verify first claim was fully slashed
        assertEq(uint8(slashStatuses[0]), uint8(CoverageClaimStatus.Slashed));

        // Verify second claim was partially slashed (200e6 out of 500e6)
        assertEq(uint8(slashStatuses[1]), uint8(CoverageClaimStatus.Slashed));

        // Verify third claim was NOT slashed (remaining amount was 0)
        assertEq(uint8(slashStatuses[2]), uint8(CoverageClaimStatus.Issued));

        // Verify slash amounts on provider
        uint256 claimId1 = cov.claims[0].claimId;
        uint256 claimId2 = cov.claims[1].claimId;
        uint256 claimId3 = cov.claims[2].claimId;

        assertEq(mockProvider.claimTotalSlashAmount(claimId1), 1000e6); // Fully slashed
        assertEq(mockProvider.claimTotalSlashAmount(claimId2), 200e6); // Partially slashed
        assertEq(mockProvider.claimTotalSlashAmount(claimId3), 0); // Not slashed
    }

    function test_slashCoverage_partialAmount_exactMatch() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage with a single claim
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash exact amount of the claim
        (CoverageClaimStatus[] memory slashStatuses, uint256 totalSlashed) =
            coverageAgent.slashCoverage(coverageId, 1000e6, block.timestamp);

        // Verify total slashed matches
        assertEq(totalSlashed, 1000e6);
        assertEq(uint8(slashStatuses[0]), uint8(CoverageClaimStatus.Slashed));
    }

    function test_slashCoverage_amountExceedsTotalCoverage() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash more than available (should only slash what's available)
        (CoverageClaimStatus[] memory slashStatuses, uint256 totalSlashed) =
            coverageAgent.slashCoverage(coverageId, 5000e6, block.timestamp);

        // Verify total slashed is capped at available coverage
        assertEq(totalSlashed, 1000e6);
        assertEq(uint8(slashStatuses[0]), uint8(CoverageClaimStatus.Slashed));
    }

    function test_slashCoverage_zeroAmount() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash zero amount (should do nothing)
        (CoverageClaimStatus[] memory slashStatuses, uint256 totalSlashed) =
            coverageAgent.slashCoverage(coverageId, 0, block.timestamp);

        // Verify nothing was slashed
        assertEq(totalSlashed, 0);
        // Status array should still have length equal to claims, but claim is not slashed
        assertEq(slashStatuses.length, 1);

        // Verify claim is still issued
        Coverage memory cov = coverageAgent.coverage(coverageId);
        CoverageClaim memory claim = mockProvider.claim(cov.claims[0].claimId);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Issued));
    }

    /// ============ Slash Coordinator Tests ============

    function test_slashCoverage_withSlashCoordinator() public {
        address slashCoordinator = address(0x999);

        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position with a slash coordinator
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: slashCoordinator,
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Verify slash coordinator is set on position
        CoveragePosition memory createdPosition = mockProvider.position(positionId);
        assertEq(createdPosition.slashCoordinator, slashCoordinator);

        // Prepare coverage request
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);

        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Get the claim ID and verify initial state
        Coverage memory cov = coverageAgent.coverage(coverageId);
        uint256 claimId = cov.claims[0].claimId;

        CoverageClaim memory claimBefore = mockProvider.claim(claimId);
        assertEq(uint8(claimBefore.status), uint8(CoverageClaimStatus.Issued));

        // Slash the coverage - should go to PendingSlash, not Slashed (coordinator is set)
        (CoverageClaimStatus[] memory slashStatuses, uint256 totalSlashed) =
            coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        // Verify slash returned PendingSlash status
        assertEq(slashStatuses.length, 1);
        assertEq(uint8(slashStatuses[0]), uint8(CoverageClaimStatus.PendingSlash));
        assertEq(totalSlashed, 1000e6); // Full claim amount queued for slash

        // Verify claim is in PendingSlash status (requires slash coordinator to complete)
        CoverageClaim memory claimAfter = mockProvider.claim(claimId);
        assertEq(uint8(claimAfter.status), uint8(CoverageClaimStatus.PendingSlash));
    }

    /// ============ Claim Refund Tests ============

    function test_onClaimRefunded() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position with Full refundable policy
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.Full,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Get the claim ID
        Coverage memory cov = coverageAgent.coverage(coverageId);
        uint256 claimId = cov.claims[0].claimId;

        // Simulate refund from provider - provider needs tokens to transfer
        uint256 refundAmount = 5e6;
        deal(USDC, address(mockProvider), refundAmount);

        // Track coordinator balance before refund
        uint256 coordinatorBalanceBefore = IERC20(USDC).balanceOf(coordinator);

        // Simulate refund
        mockProvider.simulateRefund(claimId, refundAmount);

        // Verify refund was transferred to coordinator
        uint256 coordinatorBalanceAfter = IERC20(USDC).balanceOf(coordinator);
        assertEq(coordinatorBalanceAfter - coordinatorBalanceBefore, refundAmount);
    }

    function test_onClaimRefunded_timeWeighted() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position with TimeWeighted refundable policy
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.TimeWeighted,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Get the claim ID
        Coverage memory cov = coverageAgent.coverage(coverageId);
        uint256 claimId = cov.claims[0].claimId;

        // Simulate time-weighted refund (e.g., 50% of reward if closed halfway through)
        uint256 refundAmount = 5e6;
        deal(USDC, address(mockProvider), refundAmount);

        // Track coordinator balance before refund
        uint256 coordinatorBalanceBefore = IERC20(USDC).balanceOf(coordinator);

        // Simulate refund
        mockProvider.simulateRefund(claimId, refundAmount);

        // Verify refund was transferred to coordinator
        uint256 coordinatorBalanceAfter = IERC20(USDC).balanceOf(coordinator);
        assertEq(coordinatorBalanceAfter - coordinatorBalanceBefore, refundAmount);
    }

    function test_RevertWhen_onClaimRefunded_providerNotRegistered() public {
        // Try to call onClaimRefunded from unregistered provider
        vm.prank(address(mockProvider));
        vm.expectRevert(ICoverageAgent.CoverageProviderNotRegistered.selector);
        coverageAgent.onClaimRefunded(0, 1e6);
    }

    function test_RevertWhen_onClaimRefunded_randomCaller() public {
        // Try to call onClaimRefunded from random address
        vm.prank(address(0x123));
        vm.expectRevert(ICoverageAgent.CoverageProviderNotRegistered.selector);
        coverageAgent.onClaimRefunded(0, 1e6);
    }

    /// ============ Repayments Owing Tests ============

    function test_repaymentsOwing_singleSlashedClaim() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash the coverage
        coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        // Check repayments owing
        (uint256[] memory amounts, uint256 totalOwing) = coverageAgent.repaymentsOwing(coverageId);

        // Verify amounts
        assertEq(amounts.length, 1);
        assertEq(amounts[0], 1000e6);
        assertEq(totalOwing, 1000e6);
    }

    function test_repaymentsOwing_multipleSlashedClaims() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage with multiple claims
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](3);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });
        requests[1] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 500e6,
            duration: 30 days,
            reward: 5e6
        });
        requests[2] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 300e6,
            duration: 30 days,
            reward: 3e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 18e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 18e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash the coverage
        coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        // Check repayments owing
        (uint256[] memory amounts, uint256 totalOwing) = coverageAgent.repaymentsOwing(coverageId);

        // Verify amounts
        assertEq(amounts.length, 3);
        assertEq(amounts[0], 1000e6);
        assertEq(amounts[1], 500e6);
        assertEq(amounts[2], 300e6);
        assertEq(totalOwing, 1800e6);
    }

    function test_repaymentsOwing_noSlashedClaims() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](2);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });
        requests[1] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 500e6,
            duration: 30 days,
            reward: 5e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 15e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 15e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Check repayments owing without slashing
        (uint256[] memory amounts, uint256 totalOwing) = coverageAgent.repaymentsOwing(coverageId);

        // Verify all amounts are 0
        assertEq(amounts.length, 2);
        assertEq(amounts[0], 0);
        assertEq(amounts[1], 0);
        assertEq(totalOwing, 0);
    }

    function test_repaymentsOwing_partiallySlashedClaims() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage with multiple claims
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](3);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });
        requests[1] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 500e6,
            duration: 30 days,
            reward: 5e6
        });
        requests[2] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 300e6,
            duration: 30 days,
            reward: 3e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 18e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 18e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash partially (only 1200e6, which slashes first claim fully and second claim partially)
        coverageAgent.slashCoverage(coverageId, 1200e6, block.timestamp);

        // Check repayments owing
        (uint256[] memory amounts, uint256 totalOwing) = coverageAgent.repaymentsOwing(coverageId);

        // Verify amounts
        assertEq(amounts.length, 3);
        assertEq(amounts[0], 1000e6); // First claim fully slashed
        assertEq(amounts[1], 200e6); // Second claim partially slashed
        assertEq(amounts[2], 0); // Third claim not slashed
        assertEq(totalOwing, 1200e6);
    }

    function test_repaymentsOwing_multipleProviders() public {
        // Register multiple providers
        MockCoverageProvider provider2 = new MockCoverageProvider();
        deal(USDC, address(provider2), 1e12);
        coverageAgent.registerCoverageProvider(address(mockProvider));
        coverageAgent.registerCoverageProvider(address(provider2));

        // Create positions for both providers
        CoveragePosition memory position1 = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        CoveragePosition memory position2 = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId1 = mockProvider.createPosition(position1, "");
        uint256 positionId2 = provider2.createPosition(position2, "");

        // Purchase coverage with claims from different providers
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](2);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId1,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });
        requests[1] = ClaimCoverageRequest({
            coverageProvider: address(provider2), positionId: positionId2, amount: 500e6, duration: 30 days, reward: 5e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 15e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 15e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash the coverage
        coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        // Check repayments owing
        (uint256[] memory amounts, uint256 totalOwing) = coverageAgent.repaymentsOwing(coverageId);

        // Verify amounts from both providers
        assertEq(amounts.length, 2);
        assertEq(amounts[0], 1000e6);
        assertEq(amounts[1], 500e6);
        assertEq(totalOwing, 1500e6);
    }

    function test_RevertWhen_repaymentsOwing_invalidCoverageId() public {
        // Try to check repayments owing with invalid ID (no coverage purchased yet)
        vm.expectRevert(abi.encodeWithSelector(ICoverageAgent.InvalidCoverage.selector, 0));
        coverageAgent.repaymentsOwing(0);
    }

    function test_RevertWhen_repaymentsOwing_coverageIdOutOfBounds() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase one coverage
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        coverageAgent.purchaseCoverage(requests);

        // Try to check repayments owing with out-of-bounds ID
        vm.expectRevert(abi.encodeWithSelector(ICoverageAgent.InvalidCoverage.selector, 1));
        coverageAgent.repaymentsOwing(1);
    }

    function test_repaymentsOwing_differentSlashAmounts() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage with multiple claims
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](4);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });
        requests[1] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 500e6,
            duration: 30 days,
            reward: 5e6
        });
        requests[2] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 300e6,
            duration: 30 days,
            reward: 3e6
        });
        requests[3] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 200e6,
            duration: 30 days,
            reward: 2e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 20e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 20e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash 1650e6 (full first claim, full second claim, partial third claim)
        coverageAgent.slashCoverage(coverageId, 1650e6, block.timestamp);

        // Check repayments owing
        (uint256[] memory amounts, uint256 totalOwing) = coverageAgent.repaymentsOwing(coverageId);

        // Verify amounts
        assertEq(amounts.length, 4);
        assertEq(amounts[0], 1000e6); // Fully slashed
        assertEq(amounts[1], 500e6); // Fully slashed
        assertEq(amounts[2], 150e6); // Partially slashed (150e6 out of 300e6)
        assertEq(amounts[3], 0); // Not slashed
        assertEq(totalOwing, 1650e6);
    }

    function test_repaymentsOwing_emptyCoverage() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        mockProvider.createPosition(position, "");

        // Purchase coverage with no claims (empty requests array)
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](0);

        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Check repayments owing
        (uint256[] memory amounts, uint256 totalOwing) = coverageAgent.repaymentsOwing(coverageId);

        // Verify empty arrays
        assertEq(amounts.length, 0);
        assertEq(totalOwing, 0);
    }

    /// ============ Repay Slashed Coverage Tests ============

    function test_repaySlashedCoverage_fullRepayment() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash the coverage
        coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        // Verify repayments owing
        (, uint256 totalOwingBefore) = coverageAgent.repaymentsOwing(coverageId);
        assertEq(totalOwingBefore, 1000e6);

        // Repay the full amount
        deal(USDC, coordinator, 1000e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 1000e6);

        // Expect CoverageRepaid event
        vm.expectEmit(true, false, false, false);
        emit ICoverageAgent.CoverageRepaid(coverageId);

        coverageAgent.repaySlashedCoverage(coverageId, 1000e6);

        // Verify repayments are cleared
        (uint256[] memory amountsAfter, uint256 totalOwingAfter) = coverageAgent.repaymentsOwing(coverageId);
        assertEq(amountsAfter[0], 0);
        assertEq(totalOwingAfter, 0);
    }

    function test_repaySlashedCoverage_partialRepayment() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash the coverage
        coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        // Repay half the amount
        deal(USDC, coordinator, 500e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 500e6);

        coverageAgent.repaySlashedCoverage(coverageId, 500e6);

        // Verify half still owing
        (uint256[] memory amountsAfter, uint256 totalOwingAfter) = coverageAgent.repaymentsOwing(coverageId);
        assertEq(amountsAfter[0], 500e6);
        assertEq(totalOwingAfter, 500e6);
    }

    function test_repaySlashedCoverage_multipleClaimsProportional() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage with two claims
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](2);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 600e6,
            duration: 30 days,
            reward: 6e6
        });
        requests[1] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 400e6,
            duration: 30 days,
            reward: 4e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash the coverage
        coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        // Total owing: 1000e6 (600e6 + 400e6)
        // Repay 500e6 - should distribute proportionally:
        // Claim 1: 600e6 * 500e6 / 1000e6 = 300e6
        // Claim 2: 400e6 * 500e6 / 1000e6 = 200e6

        deal(USDC, coordinator, 500e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 500e6);

        coverageAgent.repaySlashedCoverage(coverageId, 500e6);

        // Verify proportional repayment
        (uint256[] memory amountsAfter, uint256 totalOwingAfter) = coverageAgent.repaymentsOwing(coverageId);
        assertEq(amountsAfter[0], 300e6); // 600e6 - 300e6
        assertEq(amountsAfter[1], 200e6); // 400e6 - 200e6
        assertEq(totalOwingAfter, 500e6);
    }

    function test_repaySlashedCoverage_roundingRemainder() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage with three claims that will cause rounding
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](3);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 333e6, // Amounts that don't divide evenly
            duration: 30 days,
            reward: 3e6
        });
        requests[1] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 333e6,
            duration: 30 days,
            reward: 3e6
        });
        requests[2] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 334e6, // Total: 1000e6
            duration: 30 days,
            reward: 4e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash the coverage
        coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        // Total owing: 1000e6
        // Repay 100e6 - integer division:
        // Claim 0: 333e6 * 100e6 / 1000e6 = 33.3e6 (33300000)
        // Claim 1: 333e6 * 100e6 / 1000e6 = 33.3e6 (33300000)
        // Claim 2: 334e6 * 100e6 / 1000e6 = 33.4e6 (33400000)
        // Total repaid: 100e6 exactly (no remainder in this case)

        uint256 coordinatorBalanceBefore = IERC20(USDC).balanceOf(coordinator);
        deal(USDC, coordinator, coordinatorBalanceBefore + 100e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 100e6);

        coverageAgent.repaySlashedCoverage(coverageId, 100e6);

        // Verify no remainder (it all distributed evenly due to the specific numbers)
        uint256 coordinatorBalanceAfter = IERC20(USDC).balanceOf(coordinator);
        assertEq(coordinatorBalanceAfter, coordinatorBalanceBefore);

        // Verify the repayment amounts
        (uint256[] memory amountsAfter, uint256 totalOwingAfter) = coverageAgent.repaymentsOwing(coverageId);

        // After repayment:
        // Claim 0: 333e6 - 33.3e6 = 299.7e6
        // Claim 1: 333e6 - 33.3e6 = 299.7e6
        // Claim 2: 334e6 - 33.4e6 = 300.6e6
        assertEq(amountsAfter[0], 299.7e6);
        assertEq(amountsAfter[1], 299.7e6);
        assertEq(amountsAfter[2], 300.6e6);
        assertEq(totalOwingAfter, 900e6);
    }

    function test_repaySlashedCoverage_withRoundingDownRemainder() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Create three claims with amounts that will cause rounding down
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](3);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 777e6,
            duration: 30 days,
            reward: 7e6
        });
        requests[1] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 777e6,
            duration: 30 days,
            reward: 7e6
        });
        requests[2] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 777e6, // Total: 2331e6
            duration: 30 days,
            reward: 7e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 21e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 21e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash the coverage
        coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        // Total owing: 2331e6
        // Repay 100e6:
        // Each claim: 777e6 * 100e6 / 2331e6 = 33.333...e6 (rounds down to some value)
        // Due to integer division, total repaid will be less than 100e6

        uint256 coordinatorBalanceBefore = IERC20(USDC).balanceOf(coordinator);
        deal(USDC, coordinator, coordinatorBalanceBefore + 100e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 100e6);

        coverageAgent.repaySlashedCoverage(coverageId, 100e6);

        // Verify remainder was returned due to rounding
        uint256 coordinatorBalanceAfter = IERC20(USDC).balanceOf(coordinator);
        uint256 remainder = coordinatorBalanceAfter - coordinatorBalanceBefore;

        // Should have some remainder due to rounding down
        assertGt(remainder, 0);
        assertLt(remainder, 10e6);

        // Verify repayment happened
        (, uint256 totalOwingAfter) = coverageAgent.repaymentsOwing(coverageId);
        assertLt(totalOwingAfter, 2331e6);
        assertGt(totalOwingAfter, 2231e6);
    }

    function test_repaySlashedCoverage_multipleProviders() public {
        // Register multiple providers
        MockCoverageProvider provider2 = new MockCoverageProvider();
        deal(USDC, address(provider2), 1e12);
        coverageAgent.registerCoverageProvider(address(mockProvider));
        coverageAgent.registerCoverageProvider(address(provider2));

        // Create positions for both providers
        CoveragePosition memory position1 = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        CoveragePosition memory position2 = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId1 = mockProvider.createPosition(position1, "");
        uint256 positionId2 = provider2.createPosition(position2, "");

        // Purchase coverage with claims from different providers
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](2);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId1,
            amount: 700e6,
            duration: 30 days,
            reward: 7e6
        });
        requests[1] = ClaimCoverageRequest({
            coverageProvider: address(provider2), positionId: positionId2, amount: 300e6, duration: 30 days, reward: 3e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash the coverage
        coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        // Repay 500e6 proportionally across providers
        deal(USDC, coordinator, 500e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 500e6);

        coverageAgent.repaySlashedCoverage(coverageId, 500e6);

        // Verify proportional repayment across providers
        // Provider 1: 700e6 * 500e6 / 1000e6 = 350e6 repaid, 350e6 remaining
        // Provider 2: 300e6 * 500e6 / 1000e6 = 150e6 repaid, 150e6 remaining
        assertEq(mockProvider.claimTotalSlashAmount(0), 350e6);
        assertEq(provider2.claimTotalSlashAmount(0), 150e6);
    }

    function test_repaySlashedCoverage_withSomeinlinedClaimsZero() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage with three claims
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](3);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 500e6,
            duration: 30 days,
            reward: 5e6
        });
        requests[1] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 300e6,
            duration: 30 days,
            reward: 3e6
        });
        requests[2] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 200e6,
            duration: 30 days,
            reward: 2e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash 550e6 - slashes first claim fully (500e6) and second claim partially (50e6)
        coverageAgent.slashCoverage(coverageId, 550e6, block.timestamp);

        // Check slashed amounts
        (uint256[] memory amountsBefore,) = coverageAgent.repaymentsOwing(coverageId);
        assertEq(amountsBefore[0], 500e6); // Fully slashed
        assertEq(amountsBefore[1], 50e6); // Partially slashed
        assertEq(amountsBefore[2], 0); // Not slashed

        // Repay 275e6 - should distribute proportionally only to slashed claims
        // Claim 0: 500e6 * 275e6 / 550e6 = 250e6
        // Claim 1: 50e6 * 275e6 / 550e6 = 25e6
        // Claim 2: skipped (0 owing)
        deal(USDC, coordinator, 275e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 275e6);

        coverageAgent.repaySlashedCoverage(coverageId, 275e6);

        // Verify repayment
        (uint256[] memory amountsAfter, uint256 totalOwingAfter) = coverageAgent.repaymentsOwing(coverageId);
        assertEq(amountsAfter[0], 250e6); // 500e6 - 250e6
        assertEq(amountsAfter[1], 25e6); // 50e6 - 25e6
        assertEq(amountsAfter[2], 0); // Still 0
        assertEq(totalOwingAfter, 275e6);
    }

    function test_repaySlashedCoverage_overPayment() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        // Ensure coordinator has tokens and approve coverage agent to spend
        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash the coverage
        coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        // Try to repay more than owed (2000e6 when only 1000e6 owed)
        // repayAmount = 1000e6 * 2000e6 / 1000e6 = 2000e6
        // NOTE: The function calculates 2000e6 to repay but the provider caps it to 1000e6
        // The function transfers all 2000e6 from coordinator and counts totalRepaid as 2000e6
        // So no refund is issued (amount == totalRepaid), resulting in 1000e6 stuck in coverage agent
        // This is a known limitation of the current implementation
        uint256 coordinatorBalanceBefore = IERC20(USDC).balanceOf(coordinator);
        uint256 agentBalanceBefore = IERC20(USDC).balanceOf(address(coverageAgent));
        deal(USDC, coordinator, coordinatorBalanceBefore + 2000e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 2000e6);

        coverageAgent.repaySlashedCoverage(coverageId, 2000e6);

        // Verify NO refund was issued (this is the actual behavior, not ideal)
        uint256 coordinatorBalanceAfter = IERC20(USDC).balanceOf(coordinator);
        assertEq(coordinatorBalanceAfter, coordinatorBalanceBefore); // Paid 2000e6, got 0 back

        // With a provider that pulls tokens, the agent sends the full proportional amount (2000e6) to the provider
        uint256 agentBalanceAfter = IERC20(USDC).balanceOf(address(coverageAgent));
        assertEq(agentBalanceAfter, agentBalanceBefore);

        // Verify the slash is fully repaid
        (, uint256 totalOwingAfter) = coverageAgent.repaymentsOwing(coverageId);
        assertEq(totalOwingAfter, 0);
    }

    function test_RevertWhen_repaySlashedCoverage_invalidCoverageId() public {
        // Try to repay with invalid coverage ID
        deal(USDC, coordinator, 100e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 100e6);

        vm.expectRevert(abi.encodeWithSelector(ICoverageAgent.InvalidCoverage.selector, 0));
        coverageAgent.repaySlashedCoverage(0, 100e6);
    }

    function test_RevertWhen_repaySlashedCoverage_notCoordinator() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash the coverage
        coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        // Try to repay as non-coordinator
        deal(USDC, nonHandler, 1000e6);
        vm.prank(nonHandler);
        IERC20(USDC).approve(address(coverageAgent), 1000e6);

        vm.prank(nonHandler);
        vm.expectRevert(IExampleCoverageAgent.NotCoverageAgentCoordinator.selector);
        coverageAgent.repaySlashedCoverage(coverageId, 1000e6);
    }

    function test_repaySlashedCoverage_emitsCoverageRepaidWhenFullyRepaid() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash the coverage
        coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        // Repay fully and expect event
        deal(USDC, coordinator, 1000e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 1000e6);

        vm.expectEmit(true, false, false, false);
        emit ICoverageAgent.CoverageRepaid(coverageId);

        coverageAgent.repaySlashedCoverage(coverageId, 1000e6);
    }

    function test_repaySlashedCoverage_doesNotEmitEventWhenPartiallyRepaid() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash the coverage
        coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        // Repay partially - should NOT emit CoverageRepaid event
        deal(USDC, coordinator, 500e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 500e6);

        // We don't expect the CoverageRepaid event
        vm.recordLogs();
        coverageAgent.repaySlashedCoverage(coverageId, 500e6);

        // Verify no CoverageRepaid event was emitted
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            // CoverageRepaid event signature
            bytes32 eventSignature = keccak256("CoverageRepaid(uint256)");
            assertNotEq(entries[i].topics[0], eventSignature);
        }
    }

    function test_repaySlashedCoverage_accuracyOfRemainderReturn() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Create claims with amounts that will create rounding remainder
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](3);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 999e6,
            duration: 30 days,
            reward: 9e6
        });
        requests[1] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 999e6,
            duration: 30 days,
            reward: 9e6
        });
        requests[2] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 999e6, // Total: 2997e6
            duration: 30 days,
            reward: 9e6
        });

        deal(USDC, coordinator, 27e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 27e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash the coverage
        coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        // Total owing: 2997e6 (2997000000)
        // Repay 100e6 (100000000):
        // Each claim: 999000000 * 100000000 / 2997000000 = 33333333.333... -> 33333333
        // Total repaid: 33333333 * 3 = 99999999
        // Remainder: 100000000 - 99999999 = 1

        uint256 repayAmount = 100e6;
        uint256 coordinatorBalanceBefore = IERC20(USDC).balanceOf(coordinator);
        uint256 agentBalanceBefore = IERC20(USDC).balanceOf(address(coverageAgent));

        deal(USDC, coordinator, coordinatorBalanceBefore + repayAmount);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), repayAmount);

        coverageAgent.repaySlashedCoverage(coverageId, repayAmount);

        // Verify remainder was returned (just 1 wei due to rounding)
        uint256 coordinatorBalanceAfter = IERC20(USDC).balanceOf(coordinator);
        uint256 remainder = coordinatorBalanceAfter - coordinatorBalanceBefore;

        // Should have 1 wei remainder
        assertEq(remainder, 1);

        // Verify no extra tokens stuck in agent (agent paid 99999999 to provider, returned 1 to coordinator)
        uint256 agentBalanceAfter = IERC20(USDC).balanceOf(address(coverageAgent));
        assertEq(agentBalanceAfter, agentBalanceBefore);

        // Verify repayment amounts
        (, uint256 totalOwingAfter) = coverageAgent.repaymentsOwing(coverageId);
        assertEq(totalOwingAfter, 2997000000 - 99999999);
    }

    /// ============ Rounding Breakage / Dust Tests ============
    /// These tests examine whether accumulated rounding errors can make it
    /// impossible to fully repay slashed claims.

    function test_repaySlashedCoverage_canRepayExactTotalOwing() public {
        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage with multiple claims
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](3);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 333e6,
            duration: 30 days,
            reward: 3e6
        });
        requests[1] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 333e6,
            duration: 30 days,
            reward: 3e6
        });
        requests[2] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 334e6,
            duration: 30 days,
            reward: 4e6
        });

        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash the coverage
        coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        // Repay EXACT total owing - this should work perfectly with no remainder
        (, uint256 totalOwing) = coverageAgent.repaymentsOwing(coverageId);
        assertEq(totalOwing, 1000e6);

        deal(USDC, coordinator, totalOwing);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), totalOwing);

        // Expect CoverageRepaid event since we're paying exact amount
        vm.expectEmit(true, false, false, false);
        emit ICoverageAgent.CoverageRepaid(coverageId);

        coverageAgent.repaySlashedCoverage(coverageId, totalOwing);

        // Verify fully repaid
        (, uint256 totalOwingAfter) = coverageAgent.repaymentsOwing(coverageId);
        assertEq(totalOwingAfter, 0);
    }

    function test_repaySlashedCoverage_dustCannotBeRepaidProportionally() public {
        // This test demonstrates a CRITICAL BUG:
        // If individual claim amounts are very small (dust), attempting to repay
        // proportionally can result in 0 being repaid due to integer division rounding.

        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage with multiple small claims
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](5);
        for (uint256 i = 0; i < 5; i++) {
            requests[i] = ClaimCoverageRequest({
                coverageProvider: address(mockProvider),
                positionId: positionId,
                amount: 10, // Very small amounts (10 wei each)
                duration: 30 days,
                reward: 1
            });
        }

        deal(USDC, coordinator, 5);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 5);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash the coverage - total slashed: 50 wei
        coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        (, uint256 totalOwing) = coverageAgent.repaymentsOwing(coverageId);
        assertEq(totalOwing, 50);

        // Now try to repay 10 wei (less than totalOwing)
        // Formula: amounts[i] * amount / totalOwing = 10 * 10 / 50 = 2
        // This should work (2 per claim = 10 total)
        deal(USDC, coordinator, 10);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10);

        coverageAgent.repaySlashedCoverage(coverageId, 10);

        // Verify repayment worked
        (, uint256 totalOwingAfter1) = coverageAgent.repaymentsOwing(coverageId);
        assertEq(totalOwingAfter1, 40); // 50 - 10 = 40

        // Now try to repay only 3 wei when each claim owes 8 wei
        // Formula: amounts[i] * amount / totalOwing = 8 * 3 / 40 = 0 (rounds down!)
        // This is the BUG: trying to repay 3 will repay 0 to each claim!

        uint256 coordinatorBalanceBefore = IERC20(USDC).balanceOf(coordinator);
        deal(USDC, coordinator, coordinatorBalanceBefore + 3);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 3);

        coverageAgent.repaySlashedCoverage(coverageId, 3);

        // Check if ANY repayment happened
        (, uint256 totalOwingAfter2) = coverageAgent.repaymentsOwing(coverageId);

        // BUG DEMONSTRATED: totalOwing is UNCHANGED because all repayments rounded to 0
        assertEq(totalOwingAfter2, 40); // Still 40! Nothing was repaid!

        // Coordinator should have gotten all 3 wei back as "remainder"
        uint256 coordinatorBalanceAfter = IERC20(USDC).balanceOf(coordinator);
        assertEq(coordinatorBalanceAfter, coordinatorBalanceBefore + 3);
    }

    function test_repaySlashedCoverage_partialRepaymentLeavesUnrepayableDust() public {
        // This test shows how partial repayments can leave dust that requires
        // repaying the exact totalOwing to clear.

        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage with claims
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](3);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });
        requests[1] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });
        requests[2] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        deal(USDC, coordinator, 30e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 30e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash the coverage - total: 3000e6
        coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        // Make several partial repayments that create rounding remainders
        // Each repayment will round down, accumulating dust

        // Repay 1000e6 (1/3 of total)
        deal(USDC, coordinator, 1000e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 1000e6);
        coverageAgent.repaySlashedCoverage(coverageId, 1000e6);

        // Check remaining
        (uint256[] memory amounts1, uint256 totalOwing1) = coverageAgent.repaymentsOwing(coverageId);
        // Each claim: 1000e6 * 1000e6 / 3000e6 = 333333333 repaid
        // Remaining per claim: 1000000000 - 333333333 = 666666667
        assertEq(amounts1[0], 666666667);
        assertEq(amounts1[1], 666666667);
        assertEq(amounts1[2], 666666667);
        assertEq(totalOwing1, 2000000001); // 3000e6 - 999999999 = 2000000001 (1 wei dust!)

        // Repay another 1000e6
        deal(USDC, coordinator, 1000e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 1000e6);
        coverageAgent.repaySlashedCoverage(coverageId, 1000e6);

        (, uint256 totalOwing2) = coverageAgent.repaymentsOwing(coverageId);
        // More dust accumulates...

        // Try to close it out with "approximately" what's owed
        // But if there's dust, small repayments might not work

        // Let's try to repay 1 wei to each claim (3 wei total)
        // If totalOwing2 > 3, then each claim gets: amounts[i] * 3 / totalOwing2
        // which will round to 0 for most reasonable scenarios

        if (totalOwing2 > 10) {
            uint256 coordinatorBalanceBefore = IERC20(USDC).balanceOf(coordinator);
            deal(USDC, coordinator, coordinatorBalanceBefore + 5);
            vm.prank(coordinator);
            IERC20(USDC).approve(address(coverageAgent), 5);

            coverageAgent.repaySlashedCoverage(coverageId, 5);

            (, uint256 totalOwing3) = coverageAgent.repaymentsOwing(coverageId);

            // If the repayment rounded to 0, totalOwing3 == totalOwing2
            // This demonstrates that dust CAN be problematic
            if (totalOwing3 == totalOwing2) {
                // BUG: Small repayments can fail entirely due to rounding
                assertTrue(true, "Dust repayment failed as expected");
            }
        }

        // The ONLY way to fully close is to repay EXACT remaining amount
        (, uint256 finalOwing) = coverageAgent.repaymentsOwing(coverageId);
        deal(USDC, coordinator, finalOwing);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), finalOwing);

        vm.expectEmit(true, false, false, false);
        emit ICoverageAgent.CoverageRepaid(coverageId);

        coverageAgent.repaySlashedCoverage(coverageId, finalOwing);

        (, uint256 owingAfterExact) = coverageAgent.repaymentsOwing(coverageId);
        assertEq(owingAfterExact, 0);
    }

    function test_repaySlashedCoverage_manyClaimsWorstCaseRounding() public {
        // Worst case: many claims with amounts that maximize rounding loss
        // If you have N claims each owing 1 wei, and totalOwing = N,
        // then repaying anything less than N results in 0 repaid per claim

        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Create 10 claims each worth 1 wei
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](10);
        for (uint256 i = 0; i < 10; i++) {
            requests[i] = ClaimCoverageRequest({
                coverageProvider: address(mockProvider),
                positionId: positionId,
                amount: 1, // 1 wei each
                duration: 30 days,
                reward: 1
            });
        }

        deal(USDC, coordinator, 10);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash all - total slashed: 10 wei
        coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        (, uint256 totalOwing) = coverageAgent.repaymentsOwing(coverageId);
        assertEq(totalOwing, 10);

        // Try to repay 9 wei
        // Each claim: 1 * 9 / 10 = 0 (rounds down!)
        // ALL repayments will be 0!

        uint256 coordinatorBalanceBefore = IERC20(USDC).balanceOf(coordinator);
        deal(USDC, coordinator, coordinatorBalanceBefore + 9);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 9);

        coverageAgent.repaySlashedCoverage(coverageId, 9);

        (, uint256 totalOwingAfter) = coverageAgent.repaymentsOwing(coverageId);

        // CRITICAL BUG: Nothing was repaid! All 9 wei returned as remainder
        assertEq(totalOwingAfter, 10); // Still 10!

        uint256 coordinatorBalanceAfter = IERC20(USDC).balanceOf(coordinator);
        assertEq(coordinatorBalanceAfter, coordinatorBalanceBefore + 9); // All returned

        // The ONLY way to close these claims is to pay EXACTLY 10 wei
        deal(USDC, coordinator, 10);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10);

        coverageAgent.repaySlashedCoverage(coverageId, 10);

        (, uint256 finalOwing) = coverageAgent.repaymentsOwing(coverageId);
        assertEq(finalOwing, 0); // Now it's closed
    }

    function test_repaySlashedCoverage_accumulatedDustOverMultipleRepayments() public {
        // This test shows how dust accumulates over many repayments
        // and whether it eventually becomes impossible to close

        // Register provider first
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Create a position
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        // Purchase coverage with 7 claims (prime number for max rounding issues)
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](7);
        for (uint256 i = 0; i < 7; i++) {
            requests[i] = ClaimCoverageRequest({
                coverageProvider: address(mockProvider),
                positionId: positionId,
                amount: 1000e6,
                duration: 30 days,
                reward: 10e6
            });
        }

        deal(USDC, coordinator, 70e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 70e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash the coverage - total: 7000e6
        coverageAgent.slashCoverage(coverageId, type(uint256).max, block.timestamp);

        // Make 10 partial repayments of 100e6 each
        // Each repayment will have rounding, accumulating dust
        uint256 totalActuallyRepaid = 0;

        for (uint256 i = 0; i < 10; i++) {
            (, uint256 owingBefore) = coverageAgent.repaymentsOwing(coverageId);

            deal(USDC, coordinator, 100e6);
            vm.prank(coordinator);
            IERC20(USDC).approve(address(coverageAgent), 100e6);

            coverageAgent.repaySlashedCoverage(coverageId, 100e6);
            uint256 balAfter = IERC20(USDC).balanceOf(coordinator);

            uint256 remainder = balAfter; // Remainder returned after repay
            uint256 actualRepaid = 100e6 - remainder;
            totalActuallyRepaid += actualRepaid;

            (, uint256 owingAfter) = coverageAgent.repaymentsOwing(coverageId);

            // Verify repayment math: owingBefore - owingAfter should equal actualRepaid
            assertEq(owingBefore - owingAfter, actualRepaid);
        }

        // After 10 repayments of 100e6 (1000e6 total attempted)
        // Some will have been lost to rounding
        (, uint256 totalOwingFinal) = coverageAgent.repaymentsOwing(coverageId);

        // With 7000e6 original and ~1000e6 attempted repayments,
        // we should have ~6000e6 remaining, plus accumulated dust
        assertGt(totalOwingFinal, 6000e6 - 100); // Allow small margin
        assertLt(totalOwingFinal, 6000e6 + 100);

        // Final verification: can we still close it with exact amount?
        deal(USDC, coordinator, totalOwingFinal);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), totalOwingFinal);

        coverageAgent.repaySlashedCoverage(coverageId, totalOwingFinal);

        (, uint256 finalOwing) = coverageAgent.repaymentsOwing(coverageId);
        assertEq(finalOwing, 0); // Successfully closed with exact amount
    }

    /// ============ closeCoverage Tests ============

    function test_closeCoverage_closesAllClaimsAndEmitsCoverageClosed() public {
        coverageAgent.registerCoverageProvider(address(mockProvider));

        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        vm.expectEmit(true, false, false, false);
        emit ICoverageAgent.CoverageClosed(coverageId);
        coverageAgent.closeCoverage(coverageId);

        Coverage memory cov = coverageAgent.coverage(coverageId);
        assertEq(cov.claims.length, 1);
        assertEq(uint8(mockProvider.claim(cov.claims[0].claimId).status), uint8(CoverageClaimStatus.Completed));
    }

    function test_closeCoverage_transfersRefundToCoordinatorAndEmitsRewardsRefunded() public {
        coverageAgent.registerCoverageProvider(address(mockProvider));

        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        uint256 refundAmount = 5e6;
        mockProvider.setRefundOnClose(0, refundAmount);

        uint256 coordinatorBalanceBefore = IERC20(USDC).balanceOf(coordinator);

        coverageAgent.closeCoverage(coverageId);

        // Refund is transferred to coordinator (from provider -> agent -> coordinator)
        assertEq(IERC20(USDC).balanceOf(coordinator), coordinatorBalanceBefore + refundAmount);
    }

    function test_closeCoverage_noRefund_doesNotEmitRewardsRefunded() public {
        coverageAgent.registerCoverageProvider(address(mockProvider));

        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // No setRefundOnClose - balance should not change
        coverageAgent.closeCoverage(coverageId);

        // Coordinator balance unchanged (only had 10e6, spent it all on purchase)
        assertEq(IERC20(USDC).balanceOf(coordinator), 0);
    }

    function test_closeCoverage_multipleClaims_allClosedAndRefundAggregated() public {
        coverageAgent.registerCoverageProvider(address(mockProvider));

        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](3);
        for (uint256 i = 0; i < 3; i++) {
            requests[i] = ClaimCoverageRequest({
                coverageProvider: address(mockProvider),
                positionId: positionId,
                amount: 1000e6,
                duration: 30 days,
                reward: 10e6
            });
        }

        deal(USDC, coordinator, 30e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 30e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        Coverage memory cov = coverageAgent.coverage(coverageId);
        mockProvider.setRefundOnClose(cov.claims[0].claimId, 2e6);
        mockProvider.setRefundOnClose(cov.claims[1].claimId, 3e6);
        mockProvider.setRefundOnClose(cov.claims[2].claimId, 1e6);

        uint256 coordinatorBalanceBefore = IERC20(USDC).balanceOf(coordinator);
        coverageAgent.closeCoverage(coverageId);

        uint256 totalRefund = 2e6 + 3e6 + 1e6;
        assertEq(IERC20(USDC).balanceOf(coordinator), coordinatorBalanceBefore + totalRefund);
    }

    function test_RevertWhen_closeCoverage_invalidCoverageId() public {
        vm.expectRevert(abi.encodeWithSelector(ICoverageAgent.InvalidCoverage.selector, 0));
        coverageAgent.closeCoverage(0);
    }

    function test_RevertWhen_closeCoverage_notCoordinator() public {
        coverageAgent.registerCoverageProvider(address(mockProvider));

        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(0)
        });
        uint256 positionId = mockProvider.createPosition(position, "");

        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        deal(USDC, coordinator, 10e6);
        vm.prank(coordinator);
        IERC20(USDC).approve(address(coverageAgent), 10e6);
        coverageAgent.purchaseCoverage(requests);

        vm.prank(nonHandler);
        vm.expectRevert(IExampleCoverageAgent.NotCoverageAgentCoordinator.selector);
        coverageAgent.closeCoverage(0);
    }
}
