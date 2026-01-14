// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestDeployer} from "test/utils/TestDeployer.sol";
import {ExampleCoverageAgent} from "src/ExampleCoverageAgent.sol";
import {NotCoverageAgentCoordinator, CoverageProviderNotActive} from "src/Errors.sol";
import {ICoverageAgent, ClaimCoverageRequest, Coverage} from "src/interfaces/ICoverageAgent.sol";
import {
    ICoverageProvider,
    CoveragePosition,
    CoverageClaim,
    CoverageClaimStatus,
    Refundable
} from "src/interfaces/ICoverageProvider.sol";

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

    function createPosition(address coverageAgent, CoveragePosition memory data, bytes calldata)
        external
        override
        returns (uint256 positionId)
    {
        positionId = nextPositionId++;
        _positions[positionId] = data;
        ICoverageAgent(coverageAgent).onRegisterPosition(positionId);
        emit PositionCreated(positionId);
    }

    function closePosition(uint256 positionId) external override {
        _positions[positionId].expiryTimestamp = block.timestamp;
        emit PositionClosed(positionId);
    }

    function claimCoverage(uint256 positionId, uint256 amount, uint256 duration, uint256 reward)
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
        emit ClaimIssued(positionId, claimId, amount, duration);
    }

    function liquidateClaim(uint256 claimId) external override {
        _claims[claimId].status = CoverageClaimStatus.Liquidated;
        emit Liquidated(claimId);
    }

    function completeClaims(uint256 claimId) external override {
        CoverageClaim storage coverageClaim = _claims[claimId];
        _totalCoverageByAgent[msg.sender] -= coverageClaim.amount;
        coverageClaim.status = CoverageClaimStatus.Completed;
        emit ClaimCompleted(claimId);
    }

    function slashClaims(uint256[] calldata claimIds, uint256[] calldata amounts)
        external
        override
        returns (CoverageClaimStatus[] memory slashStatuses)
    {
        slashStatuses = new CoverageClaimStatus[](claimIds.length);
        for (uint256 i = 0; i < claimIds.length; i++) {
            _claimSlashAmounts[claimIds[i]] = amounts[i];
            _claims[claimIds[i]].status = CoverageClaimStatus.Slashed;
            slashStatuses[i] = CoverageClaimStatus.Slashed;
            emit ClaimSlashed(claimIds[i], amounts[i]);
        }
    }

    function completeSlash(uint256 claimId) external override {
        if (_claimSlashAmounts[claimId] > _claims[claimId].amount) {
            revert SlashAmountExceedsClaim(claimId, _claimSlashAmounts[claimId], _claims[claimId].amount);
        }
        _claims[claimId].status = CoverageClaimStatus.Slashed;
        emit ClaimSlashed(claimId, _claimSlashAmounts[claimId]);
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

    function claimDeficit(uint256) external pure override returns (uint256) {
        return 0;
    }

    function claimTotalSlashAmount(uint256 claimId) external view override returns (uint256) {
        return _claimSlashAmounts[claimId];
    }
}

/// @notice Test suite for ExampleCoverageAgent
contract CoverageAgentTest is TestDeployer {
    ExampleCoverageAgent public coverageAgent;
    MockCoverageProvider public mockProvider;

    address public handler;
    address public nonHandler;

    function setUp() public override {
        super.setUp();

        handler = address(this);
        nonHandler = address(0x123);

        // Deploy coverage agent
        coverageAgent = new ExampleCoverageAgent(handler, USDC);

        // Deploy mock provider and price oracle
        mockProvider = new MockCoverageProvider();
    }

    /// ============ Constructor Tests ============

    function test_constructor() public view {
        // Verify asset is set correctly (handler is tested via access control)
        assertEq(coverageAgent.asset(), USDC);
    }

    function test_constructor_handlerAccessControl() public {
        // Verify handler is set correctly by testing access control
        // Handler (address(this)) should be able to register providers
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Non-handler should not be able to register providers
        vm.prank(nonHandler);
        vm.expectRevert(NotCoverageAgentCoordinator.selector);
        coverageAgent.registerCoverageProvider(address(0x999));
    }

    function test_RevertWhen_constructor_zeroHandler() public {
        vm.expectRevert(NotCoverageAgentCoordinator.selector);
        new ExampleCoverageAgent(address(0), USDC);
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
        vm.expectRevert(NotCoverageAgentCoordinator.selector);
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

        vm.expectEmit(true, true, false, false);
        emit ICoverageAgent.PositionRegistered(address(mockProvider), positionId);

        vm.prank(address(mockProvider));
        coverageAgent.onRegisterPosition(positionId);
    }

    function test_RevertWhen_onRegisterPosition_providerNotActive() public {
        uint256 positionId = 123;

        vm.prank(address(mockProvider));
        vm.expectRevert(CoverageProviderNotActive.selector);
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
            slashCoordinator: address(0)
        });

        vm.expectEmit(true, true, false, false);
        emit ICoverageAgent.PositionRegistered(address(mockProvider), 0);

        uint256 positionId = mockProvider.createPosition(address(coverageAgent), position, "");
        assertEq(positionId, 0);
    }

    /// ============ Integration Tests ============

    function test_fullWorkflow_registerAndCreatePosition() public {
        // Step 1: Register coverage provider
        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Step 2: Create position through provider
        CoveragePosition memory position = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.TimeWeighted,
            slashCoordinator: address(0)
        });

        uint256 positionId = mockProvider.createPosition(address(coverageAgent), position, "");

        // Step 3: Verify position was created
        CoveragePosition memory createdPosition = mockProvider.position(positionId);
        assertEq(createdPosition.minRate, 100);
        assertEq(createdPosition.maxDuration, 30 days);
        assertEq(createdPosition.asset, USDC);

        // Step 4: Claim coverage
        uint256 claimId = mockProvider.claimCoverage(positionId, 1000e6, 30 days, 10e6);

        // Step 5: Verify claim
        CoverageClaim memory coverageClaim = mockProvider.claim(claimId);
        assertEq(coverageClaim.positionId, positionId);
        assertEq(coverageClaim.amount, 1000e6);
        assertEq(coverageClaim.duration, 30 days);
        assertEq(uint8(coverageClaim.status), uint8(CoverageClaimStatus.Issued));
    }

    function test_multipleProviders_andPositions() public {
        // Register multiple providers
        MockCoverageProvider provider2 = new MockCoverageProvider();
        coverageAgent.registerCoverageProvider(address(mockProvider));
        coverageAgent.registerCoverageProvider(address(provider2));

        // Create positions on both providers
        CoveragePosition memory position1 = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0)
        });

        CoveragePosition memory position2 = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 200,
            maxDuration: 60 days,
            expiryTimestamp: block.timestamp + 180 days,
            asset: USDC,
            refundable: Refundable.Full,
            slashCoordinator: address(0x456)
        });

        uint256 positionId1 = mockProvider.createPosition(address(coverageAgent), position1, "");
        uint256 positionId2 = provider2.createPosition(address(coverageAgent), position2, "");

        // Verify positions
        assertEq(positionId1, 0);
        assertEq(positionId2, 0); // Each provider has their own counter

        CoveragePosition memory retrieved1 = mockProvider.position(positionId1);
        CoveragePosition memory retrieved2 = provider2.position(positionId2);

        assertEq(retrieved1.minRate, 100);
        assertEq(retrieved2.minRate, 200);
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
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0)
        });
        uint256 positionId = mockProvider.createPosition(address(coverageAgent), position, "");

        // Prepare coverage request
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

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
            slashCoordinator: address(0)
        });
        uint256 positionId = mockProvider.createPosition(address(coverageAgent), position, "");

        // Purchase one coverage
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });
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
            slashCoordinator: address(0)
        });
        uint256 positionId = mockProvider.createPosition(address(coverageAgent), position, "");

        // Purchase first coverage
        ClaimCoverageRequest[] memory requests1 = new ClaimCoverageRequest[](1);
        requests1[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });
        uint256 coverageId1 = coverageAgent.purchaseCoverage(requests1);
        assertEq(coverageId1, 0);

        // Purchase second coverage
        ClaimCoverageRequest[] memory requests2 = new ClaimCoverageRequest[](1);
        requests2[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 500e6,
            duration: 30 days,
            reward: 5e6
        });
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
            slashCoordinator: address(0)
        });
        uint256 positionId = mockProvider.createPosition(address(coverageAgent), position, "");

        // Purchase coverage
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        // Ensure coverage agent has tokens for reward
        deal(USDC, address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Verify claim is issued before slashing
        Coverage memory cov = coverageAgent.coverage(coverageId);
        uint256 claimId = cov.claims[0].claimId;
        CoverageClaim memory claimBefore = mockProvider.claim(claimId);
        assertEq(uint8(claimBefore.status), uint8(CoverageClaimStatus.Issued));

        // Slash the coverage
        CoverageClaimStatus[] memory slashStatuses = coverageAgent.slashCoverage(coverageId);

        // Verify slash statuses
        assertEq(slashStatuses.length, 1);
        assertEq(uint8(slashStatuses[0]), uint8(CoverageClaimStatus.Slashed));

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
            slashCoordinator: address(0)
        });
        uint256 positionId = mockProvider.createPosition(address(coverageAgent), position, "");

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

        // Ensure coverage agent has tokens for rewards
        deal(USDC, address(coverageAgent), 15e6);
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

        // Slash the coverage
        CoverageClaimStatus[] memory slashStatuses = coverageAgent.slashCoverage(coverageId);

        // Verify slash statuses
        assertEq(slashStatuses.length, 2);
        assertEq(uint8(slashStatuses[0]), uint8(CoverageClaimStatus.Slashed));
        assertEq(uint8(slashStatuses[1]), uint8(CoverageClaimStatus.Slashed));

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
            slashCoordinator: address(0)
        });
        CoveragePosition memory position2 = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: USDC,
            refundable: Refundable.None,
            slashCoordinator: address(0)
        });
        uint256 positionId1 = mockProvider.createPosition(address(coverageAgent), position1, "");
        uint256 positionId2 = provider2.createPosition(address(coverageAgent), position2, "");

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

        // Ensure coverage agent has tokens for rewards
        deal(USDC, address(coverageAgent), 15e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Slash the coverage
        CoverageClaimStatus[] memory slashStatuses = coverageAgent.slashCoverage(coverageId);

        // Verify slash statuses
        assertEq(slashStatuses.length, 2);
        assertEq(uint8(slashStatuses[0]), uint8(CoverageClaimStatus.Slashed));
        assertEq(uint8(slashStatuses[1]), uint8(CoverageClaimStatus.Slashed));

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
            slashCoordinator: address(0)
        });
        uint256 positionId = mockProvider.createPosition(address(coverageAgent), position, "");

        // Purchase coverage
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        deal(USDC, address(coverageAgent), 10e6);
        uint256 coverageId = coverageAgent.purchaseCoverage(requests);

        // Try to slash as non-coordinator
        vm.prank(nonHandler);
        vm.expectRevert(NotCoverageAgentCoordinator.selector);
        coverageAgent.slashCoverage(coverageId);
    }

    function test_RevertWhen_slashCoverage_invalidCoverageId() public {
        // Try to slash coverage with invalid ID (no coverage purchased yet)
        vm.expectRevert(abi.encodeWithSelector(ICoverageAgent.InvalidCoverage.selector, 0));
        coverageAgent.slashCoverage(0);
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
            slashCoordinator: address(0)
        });
        uint256 positionId = mockProvider.createPosition(address(coverageAgent), position, "");

        // Purchase one coverage
        ClaimCoverageRequest[] memory requests = new ClaimCoverageRequest[](1);
        requests[0] = ClaimCoverageRequest({
            coverageProvider: address(mockProvider),
            positionId: positionId,
            amount: 1000e6,
            duration: 30 days,
            reward: 10e6
        });

        deal(USDC, address(coverageAgent), 10e6);
        coverageAgent.purchaseCoverage(requests);

        // Try to slash coverage with out-of-bounds ID
        vm.expectRevert(abi.encodeWithSelector(ICoverageAgent.InvalidCoverage.selector, 1));
        coverageAgent.slashCoverage(1);
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
            slashCoordinator: address(0)
        });
        uint256 positionId = mockProvider.createPosition(address(coverageAgent), position, "");

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

        deal(USDC, address(coverageAgent), 15e6);
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

        // Slash only the first coverage
        CoverageClaimStatus[] memory slashStatuses = coverageAgent.slashCoverage(coverageId1);

        // Verify first coverage was slashed
        assertEq(slashStatuses.length, 1);
        assertEq(uint8(slashStatuses[0]), uint8(CoverageClaimStatus.Slashed));
        assertEq(uint8(mockProvider.claim(claimId1).status), uint8(CoverageClaimStatus.Slashed));

        // Verify second coverage was NOT slashed
        assertEq(uint8(mockProvider.claim(claimId2).status), uint8(CoverageClaimStatus.Issued));
    }
}

