// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {TestDeployer} from "test/utils/TestDeployer.sol";
import {ExampleCoverageAgent} from "src/ExampleCoverageAgent.sol";
import {ICoverageAgent, ClaimCoverageRequest, Coverage} from "src/interfaces/ICoverageAgent.sol";
import {
    ICoverageProvider,
    CoveragePosition,
    CoverageClaim,
    CoverageClaimStatus,
    Refundable
} from "src/interfaces/ICoverageProvider.sol";
import {IExampleCoverageAgent} from "src/interfaces/IExampleCoverageAgent.sol";

/// @notice Mock Coverage Provider for testing
contract MockCoverageProvider is ICoverageProvider {
    bool public isRegistered;
    uint256 public nextPositionId;
    uint256 public nextClaimId;
    mapping(uint256 => CoveragePosition) private _positions;
    mapping(uint256 => CoverageClaim) private _claims;
    mapping(address => uint256) private _totalCoverageByAgent;
    mapping(uint256 => uint256) private _claimSlashAmounts;

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

    function closeClaim(uint256 claimId) external override {
        _claims[claimId].status = CoverageClaimStatus.Completed;
        emit ClaimClosed(claimId);
    }

    function liquidateClaim(uint256 claimId) external override {
        emit ClaimLiquidated(claimId);
    }

    function slashClaims(uint256[] calldata claimIds, uint256[] calldata amounts)
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
                emit ClaimSlashed(claimIds[i], amounts[i]);
            }
        }
    }

    function completeSlash(uint256 claimId) external override {
        if (_claimSlashAmounts[claimId] > _claims[claimId].amount) {
            revert SlashAmountExceedsClaim(claimId, _claimSlashAmounts[claimId], _claims[claimId].amount);
        }
        _claims[claimId].status = CoverageClaimStatus.Slashed;
        emit ClaimSlashed(claimId, _claimSlashAmounts[claimId]);
    }

    function repaySlashedClaim(uint256 claimId, uint256 amount) external override {
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

    function position(uint256 positionId) external view override returns (CoveragePosition memory) {
        return _positions[positionId];
    }

    function positionMaxAmount(uint256) external pure override returns (uint256) {
        return 1000e6;
    }

    function claim(uint256 claimId) external view override returns (CoverageClaim memory) {
        return _claims[claimId];
    }

    function claimBacking(uint256) external pure override returns (int256) {
        return 0;
    }

    function claimTotalSlashAmount(uint256 claimId) external view override returns (uint256) {
        return _claimSlashAmounts[claimId];
    }

    function providerTypeId() external pure override returns (uint256) {
        return 1;
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
            coverageAgent.slashCoverage(coverageId, type(uint256).max);

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
            coverageAgent.slashCoverage(coverageId, type(uint256).max);

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
            coverageAgent.slashCoverage(coverageId, type(uint256).max);

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
        coverageAgent.slashCoverage(coverageId, type(uint256).max);
    }

    function test_RevertWhen_slashCoverage_invalidCoverageId() public {
        // Try to slash coverage with invalid ID (no coverage purchased yet)
        vm.expectRevert(abi.encodeWithSelector(ICoverageAgent.InvalidCoverage.selector, 0));
        coverageAgent.slashCoverage(0, type(uint256).max);
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
        coverageAgent.slashCoverage(1, type(uint256).max);
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
            coverageAgent.slashCoverage(coverageId1, type(uint256).max);

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
            coverageAgent.slashCoverage(coverageId, 1200e6);

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
            coverageAgent.slashCoverage(coverageId, 1000e6);

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
            coverageAgent.slashCoverage(coverageId, 5000e6);

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
        (CoverageClaimStatus[] memory slashStatuses, uint256 totalSlashed) = coverageAgent.slashCoverage(coverageId, 0);

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
            coverageAgent.slashCoverage(coverageId, type(uint256).max);

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
}
