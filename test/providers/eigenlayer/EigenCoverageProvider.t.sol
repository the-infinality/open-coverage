// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EigenTestDeployer} from "../../utils/EigenTestDeployer.sol";
import {CoveragePosition, CoverageClaim, CoverageClaimStatus, Refundable} from "src/interfaces/ICoverageProvider.sol";
import {IEigenServiceManager} from "src/providers/eigenlayer/interfaces/IEigenServiceManager.sol";
import {IEigenOperatorProxy} from "src/providers/eigenlayer/interfaces/IEigenOperatorProxy.sol";
import {ICoverageProvider} from "src/interfaces/ICoverageProvider.sol";
import {ICoverageAgent} from "src/interfaces/ICoverageAgent.sol";
import {IExampleCoverageAgent} from "src/interfaces/IExampleCoverageAgent.sol";
import {ExampleCoverageAgent} from "src/ExampleCoverageAgent.sol";
import {SlashCoordinationStatus} from "src/interfaces/ISlashCoordinator.sol";
import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";
import {IAllocationManager} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {OperatorSet} from "eigenlayer-contracts/libraries/OperatorSetLib.sol";
import {IAssetPriceOracleAndSwapper} from "src/interfaces/IAssetPriceOracleAndSwapper.sol";
import {ISwapperEngine} from "src/interfaces/ISwapperEngine.sol";
import {Vm} from "forge-std/Vm.sol";
import {MockSlashCoordinator, MockSlashCoordinatorImmediate} from "../../utils/mocks/MockSlashCoordinator.sol";
import {EigenCoverageProviderFacet} from "src/providers/eigenlayer/facets/EigenCoverageProviderFacet.sol";
import {ICoverageLiquidatable} from "src/interfaces/ICoverageLiquidatable.sol";

contract EigenCoverageProviderTest is EigenTestDeployer {
    /// @notice Test that coverage agent emits MetadataUpdated on deployment
    function test_coverageAgent_emitsMetadataUpdated_onDeployment() public {
        string memory uri = "https://coverage.example.com/agent-metadata.json";
        vm.expectEmit(false, false, false, true);
        emit ICoverageAgent.MetadataUpdated(uri);
        new ExampleCoverageAgent(address(this), USDC, uri);
    }

    /// @notice Test that coverage agent emits MetadataUpdated when updateMetadata is called
    function test_coverageAgent_emitsMetadataUpdated_onUpdate() public {
        string memory newUri = "https://new-metadata.example.com/updated.json";
        vm.expectEmit(false, false, false, true);
        emit ICoverageAgent.MetadataUpdated(newUri);
        coverageAgent.updateMetadata(newUri);
    }

    function test_createPosition() public {
        _setupwithAllocations();

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });

        // Expect PositionCreated event
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.PositionCreated(0);

        uint256 positionId = eigenCoverageProvider.createPosition(data, "");
        assertEq(positionId, 0);
    }

    function test_closePosition() public {
        _setupwithAllocations();

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        // Expect PositionClosed event
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.PositionClosed(positionId);

        eigenCoverageProvider.closePosition(positionId);
        assertEq(eigenCoverageProvider.position(positionId).expiryTimestamp, block.timestamp);
    }

    function test_RevertWhen_closePosition_expired() public {
        _setupwithAllocations();

        uint256 expiryTimestamp = block.timestamp + 365 days;
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: expiryTimestamp,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        // Warp past the expiry timestamp
        vm.warp(block.timestamp + 366 days);

        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.PositionExpired.selector, positionId, expiryTimestamp));
        eigenCoverageProvider.closePosition(positionId);
    }

    /// @notice Test that anyone can close a position when the strategy is no longer whitelisted
    function test_closePosition_strategyNotWhitelisted() public {
        _setupwithAllocations();

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        // Remove the strategy from the whitelist
        address strategy = address(_getTestStrategy());
        eigenServiceManager.setStrategyWhitelist(strategy, false);
        assertFalse(eigenServiceManager.isStrategyWhitelisted(strategy));

        // Now anyone can close the position (no authorization required)
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);

        // Expect PositionClosed event
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.PositionClosed(positionId);

        eigenCoverageProvider.closePosition(positionId);
    }

    function test_claimPosition() public {
        _setupwithAllocations();

        _stakeAndDelegateToOperator(10e18);

        // Create the position
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);

        // Expect ClaimIssued event
        vm.expectEmit(true, true, false, true);
        emit ICoverageProvider.ClaimIssued(positionId, 0, 1000e6, 30 days);

        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        assertEq(claimId, 0);

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(claim.amount, 1000e6);
        assertEq(claim.duration, 30 days);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Issued));
        assertEq(claim.reward, 10e6);
        assertEq(claim.positionId, positionId);

        // Verify position backing and coverage percentage
        uint256 totalAllocated = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );
        (int256 backing, uint16 coveragePercentage) = eigenCoverageProvider.positionBacking(positionId);
        assertGt(backing, 0, "Position should be fully backed after issuance");
        uint256 expectedCoverageBps = (1000e6 * 10000) / totalAllocated;
        // forge-lint: disable-next-line(unsafe-typecast)
        assertApproxEqAbs(coveragePercentage, uint16(expectedCoverageBps), 1, "Coverage utilization should match");
    }

    /// @notice Fuzz test to verify claim coverage with various claim amounts up to the maximum staked coverage
    /// @param claimAmountBps The claim amount as a percentage of maximum coverage in basis points (1-10000)
    ///                       This will be bounded to ensure we don't exceed available coverage
    function testFuzz_claimPosition(uint256 claimAmountBps) public {
        _setupwithAllocations();

        uint256 stakeAmount = 10e18;
        _stakeAndDelegateToOperator(stakeAmount);

        // Create the position
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        // Calculate the maximum coverage available based on allocated stake
        uint256 maxCoverage = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        // Bound claimAmountBps to 1-7000 (0.01% to 70% of max coverage)
        // Coverage utilization must stay at or below the operator's 70% coverage threshold
        claimAmountBps = bound(claimAmountBps, 1, 7000);
        uint256 claimAmount = (maxCoverage * claimAmountBps) / 10000;

        // Ensure claimAmount is at least 1 to pass validation
        if (claimAmount == 0) {
            claimAmount = 1;
        }

        // Calculate reward proportionally (using a reasonable reward rate)
        // Using 1% of claim amount as reward, minimum 1e6
        uint256 reward = claimAmount / 100;
        if (reward < 1e6) {
            reward = 1e6;
        }

        // Give the coverage agent a large balance to handle rewards for any claim amount
        // Reward is at most maxCoverage/100 (when claimAmount = maxCoverage), but ensure we have enough
        // Set balance to maxCoverage to provide ample buffer for any reward calculation
        deal(coverageAgent.asset(), address(coverageAgent), maxCoverage);

        vm.startPrank(address(coverageAgent));
        // Approve enough tokens for the reward
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), reward);

        // Track the expected claim ID (should be 0 for first claim in a fresh test)
        // Since each fuzz test run is independent, this will be the first claim
        uint256 expectedClaimId = 0;
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, claimAmount, 30 days, reward);
        vm.stopPrank();

        // Verify claim ID (should be 0 for first claim)
        assertEq(claimId, expectedClaimId);

        // Verify claim properties
        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(claim.amount, claimAmount);
        assertEq(claim.duration, 30 days);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Issued));
        assertEq(claim.reward, reward);
        assertEq(claim.positionId, positionId);

        // Verify position backing and coverage percentage (utilization = claimAmount/maxCoverage in bps)
        (int256 backing, uint16 coveragePercentage) = eigenCoverageProvider.positionBacking(positionId);
        assertGe(backing, 0, "Position should be fully backed after issuance");
        uint256 expectedCoverageBps = (claimAmount * 10000) / maxCoverage;
        // forge-lint: disable-next-line(unsafe-typecast)
        assertApproxEqAbs(coveragePercentage, uint16(expectedCoverageBps), 1, "Coverage utilization should match");
    }

    function test_providerTypeId() public view {
        // Should return the correct provider type ID (20 for Eigen coverage provider)
        uint256 typeId = eigenCoverageProvider.providerTypeId();
        assertEq(typeId, 20);
    }

    function test_liquidationThreshold_returnsDefault() public view {
        uint16 threshold = eigenCoverageLiquidatable.liquidationThreshold();
        assertEq(threshold, 9000, "Default liquidation threshold should be 9000 (90%)");
    }

    function test_liquidationThreshold_afterUpdate() public {
        uint16 newThreshold = 8500;
        eigenCoverageLiquidatable.setLiquidationThreshold(newThreshold);

        uint16 threshold = eigenCoverageLiquidatable.liquidationThreshold();
        assertEq(threshold, newThreshold, "Liquidation threshold should match updated value");
    }

    // ============ setCoverageThreshold / coverageThreshold (ICoverageLiquidatable) ============

    function test_coverageThreshold_defaultAfterRegistration() public {
        uint32[] memory operatorSetIds = new uint32[](0);
        eigenServiceManager.registerOperator(address(operator), address(eigenCoverageDiamond), operatorSetIds, "");

        uint16 threshold = eigenCoverageLiquidatable.coverageThreshold(bytes32(uint256(uint160(address(operator)))));
        assertEq(threshold, 7000, "Default coverage threshold should be 7000 (70%)");
    }

    function test_setCoverageThreshold() public {
        _setupwithAllocations();

        uint16 newThreshold = 8500;
        eigenCoverageLiquidatable.setCoverageThreshold(bytes32(uint256(uint160(address(operator)))), newThreshold);

        uint16 threshold = eigenCoverageLiquidatable.coverageThreshold(bytes32(uint256(uint160(address(operator)))));
        assertEq(threshold, newThreshold, "Coverage threshold should be updated to 8500");
    }

    function test_setCoverageThreshold_updatesValue() public {
        _setupwithAllocations();

        eigenCoverageLiquidatable.setCoverageThreshold(bytes32(uint256(uint160(address(operator)))), 5000);
        assertEq(eigenCoverageLiquidatable.coverageThreshold(bytes32(uint256(uint160(address(operator))))), 5000);

        eigenCoverageLiquidatable.setCoverageThreshold(bytes32(uint256(uint160(address(operator)))), 9000);
        assertEq(eigenCoverageLiquidatable.coverageThreshold(bytes32(uint256(uint160(address(operator))))), 9000);
    }

    function test_setCoverageThreshold_zeroValue() public {
        _setupwithAllocations();

        eigenCoverageLiquidatable.setCoverageThreshold(bytes32(uint256(uint160(address(operator)))), 0);
        assertEq(
            eigenCoverageLiquidatable.coverageThreshold(bytes32(uint256(uint160(address(operator))))),
            0,
            "Coverage threshold should be 0"
        );
    }

    function test_setCoverageThreshold_maxAllowed() public {
        _setupwithAllocations();

        eigenCoverageLiquidatable.setCoverageThreshold(bytes32(uint256(uint160(address(operator)))), 10000);
        assertEq(
            eigenCoverageLiquidatable.coverageThreshold(bytes32(uint256(uint160(address(operator))))),
            10000,
            "Coverage threshold should be 10000 (100%)"
        );
    }

    function test_RevertWhen_setCoverageThreshold_exceedsMax() public {
        _setupwithAllocations();

        vm.expectRevert(
            abi.encodeWithSelector(ICoverageLiquidatable.ThresholdExceedsMax.selector, uint16(10000), uint16(10001))
        );
        eigenCoverageLiquidatable.setCoverageThreshold(bytes32(uint256(uint160(address(operator)))), 10001);
    }

    function test_coverageThreshold_unregisteredOperator() public {
        address unregistered = makeAddr("unregistered");
        uint16 threshold = eigenCoverageLiquidatable.coverageThreshold(bytes32(uint256(uint160(unregistered))));
        assertEq(threshold, 0, "Unregistered operator should have 0 threshold");
    }

    // ============ setLiquidationThreshold / liquidationThreshold (EigenCoverageProviderFacet) ============

    function test_setLiquidationThreshold() public {
        uint16 newThreshold = 8500;
        eigenCoverageLiquidatable.setLiquidationThreshold(newThreshold);

        uint16 threshold = eigenCoverageLiquidatable.liquidationThreshold();
        assertEq(threshold, newThreshold, "Liquidation threshold should match set value");
    }

    function test_setLiquidationThreshold_updatesValue() public {
        eigenCoverageLiquidatable.setLiquidationThreshold(8000);
        assertEq(eigenCoverageLiquidatable.liquidationThreshold(), 8000);

        eigenCoverageLiquidatable.setLiquidationThreshold(9500);
        assertEq(eigenCoverageLiquidatable.liquidationThreshold(), 9500);
    }

    function test_setLiquidationThreshold_zeroValue() public {
        eigenCoverageLiquidatable.setLiquidationThreshold(0);
        assertEq(eigenCoverageLiquidatable.liquidationThreshold(), 0, "Liquidation threshold should be 0");
    }

    function test_setLiquidationThreshold_maxAllowed() public {
        eigenCoverageLiquidatable.setLiquidationThreshold(10000);
        assertEq(
            eigenCoverageLiquidatable.liquidationThreshold(), 10000, "Liquidation threshold should be 10000 (100%)"
        );
    }

    function test_RevertWhen_setLiquidationThreshold_exceedsMax() public {
        vm.expectRevert(
            abi.encodeWithSelector(ICoverageLiquidatable.ThresholdExceedsMax.selector, uint16(10000), uint16(10001))
        );
        eigenCoverageLiquidatable.setLiquidationThreshold(10001);
    }

    function test_RevertWhen_setLiquidationThreshold_notOwner() public {
        address nonOwner = makeAddr("nonOwner");

        vm.prank(nonOwner);
        vm.expectRevert("LibDiamond: Must be contract owner");
        eigenCoverageLiquidatable.setLiquidationThreshold(8500);
    }

    function test_RevertWhen_claimPosition_insufficientCoverageOnClaim() public {
        _setupwithAllocations();

        // Calculate the minimum stake needed to cover 1000e6 USDC
        // The coverage calculation converts allocated stake (in strategy asset) to coverage asset (USDC)
        // We need to find what stake amount would result in coverage < 1000e6 USDC
        address strategyAsset = address(_getTestStrategy().underlyingToken());
        address coverageAsset = address(coverageAgent.asset());
        uint256 claimAmount = 1000e6; // USDC

        // The coverage calculation does: getQuote(allocatedStake, coverageAsset, strategyAsset)
        // This converts allocatedStake FROM coverageAsset TO strategyAsset
        // To find the stake that gives us exactly claimAmount coverage, we reverse it:
        // getQuote(claimAmount, strategyAsset, coverageAsset) gives us the stake amount
        (uint256 requiredStake,) = eigenPriceOracle.getQuote(claimAmount, strategyAsset, coverageAsset);

        // Stake slightly less than required to trigger insufficient coverage error
        // Use 99% of required stake to ensure we're under the threshold
        uint256 stakeAmount = (requiredStake * 90) / 100;

        _stakeAndDelegateToOperator(stakeAmount);

        // Create the position
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        uint256 coverageAllocated = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);

        // forge-lint: disable-next-line(unsafe-typecast)
        uint16 coveragePercentage = uint16((claimAmount * 10000) / coverageAllocated);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICoverageProvider.InsufficientCoverageAvailable.selector,
                claimAmount - coverageAllocated,
                coveragePercentage
            )
        );
        eigenCoverageProvider.issueClaim(positionId, claimAmount, 30 days, 10e6);
    }

    /// @notice Fuzz test to verify insufficient coverage error with various stake amounts
    /// @param stakePercentBps The stake amount as a percentage of required stake in basis points (0-10000)
    /// @param stakePercentBps The stake amount as a percentage of required stake in basis points (0-10000)
    ///                         Values < 10000 (100%) will trigger insufficient coverage
    function testFuzz_RevertWhen_claimPosition_insufficientCoverageOnClaim(uint256 stakePercentBps) public {
        _setupwithAllocations();

        address strategyAsset = address(_getTestStrategy().underlyingToken());
        address coverageAsset = address(coverageAgent.asset());
        uint256 claimAmount = 1000e6; // USDC

        // Calculate the minimum stake needed to cover the claim amount
        (uint256 requiredStake,) = eigenPriceOracle.getQuote(claimAmount, strategyAsset, coverageAsset);

        // Bound stakePercentBps to a reasonable range: 1-99% of required stake
        // This ensures we always have insufficient coverage
        // Using basis points: 1 = 0.01%, 9900 = 99%
        stakePercentBps = bound(stakePercentBps, 1, 9900);
        uint256 stakeAmount = (requiredStake * stakePercentBps) / 10000;

        // Skip if stakeAmount is too small (would cause issues with staking)
        if (stakeAmount < 1e3) {
            stakeAmount = 1e3;
        }

        _stakeAndDelegateToOperator(stakeAmount);

        // Create the position
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        uint256 coverageAllocated = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);

        uint16 coveragePercentage =
        // forge-lint: disable-next-line(unsafe-typecast)
        coverageAllocated == 0 ? type(uint16).max : uint16((claimAmount * 10000) / coverageAllocated);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICoverageProvider.InsufficientCoverageAvailable.selector,
                claimAmount - coverageAllocated,
                coveragePercentage
            )
        );
        eigenCoverageProvider.issueClaim(positionId, claimAmount, 30 days, 10e6);
    }

    function test_RevertWhen_claimPosition_invalidAmount() public {
        _setupwithAllocations();

        _stakeAndDelegateToOperator(10e18);

        // Create the position
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        vm.expectRevert(ICoverageProvider.ZeroAmount.selector);
        eigenCoverageProvider.issueClaim(positionId, 0, 30 days, 10e6);
        vm.stopPrank();
    }

    function test_positionMaxAmount() public {
        _setupwithAllocations();

        _stakeAndDelegateToOperator(1e16);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");
        assertApproxEqAbs(eigenCoverageProvider.positionMaxAmount(positionId), 35735542, 4e5);
    }

    function test_RevertWhen_claimPosition_durationExceedsMax() public {
        _setupwithAllocations();

        _stakeAndDelegateToOperator(1000e18);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });

        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.DurationExceedsMax.selector, 30 days, 365 days));
        eigenCoverageProvider.issueClaim(positionId, 1000e6, 365 days, 10e6);
        vm.stopPrank();
    }

    function test_RevertWhen_claimPosition_insufficientReward() public {
        _setupwithAllocations();

        _stakeAndDelegateToOperator(1000e18);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        uint256 amount = 1000e6;
        uint256 duration = 30 days;
        uint256 minimumReward = (amount * data.minRate * duration) / (10000 * 365 days);
        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.InsufficientReward.selector, minimumReward, 10));
        eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10);
        vm.stopPrank();
    }

    function test_RevertWhen_claimPosition_durationExceedsExpiry() public {
        _setupwithAllocations();

        _stakeAndDelegateToOperator(1000e18);

        // Create position with expiry 100 days from now
        uint256 expiryTimestamp = block.timestamp + 100 days;
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 0, // No max duration limit
            expiryTimestamp: expiryTimestamp,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);

        // Try to claim with duration that would exceed expiry (101 days)
        uint256 duration = 101 days;
        uint256 completionTimestamp = block.timestamp + duration;
        vm.expectRevert(
            abi.encodeWithSelector(
                ICoverageProvider.DurationExceedsExpiry.selector, expiryTimestamp, completionTimestamp
            )
        );
        eigenCoverageProvider.issueClaim(positionId, 1000e6, duration, 10e6);
        vm.stopPrank();
    }

    function test_slashClaims() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        // Verify position backing before slashing
        (int256 backingBeforeSlash,) = eigenCoverageProvider.positionBacking(positionId);
        assertGt(backingBeforeSlash, 0, "Position should be fully backed before slashing");

        // Get asset addresses
        address coverageAsset = coverageAgent.asset();
        address positionAsset = eigenCoverageProvider.position(positionId).asset;

        // Check balances before slashing
        uint256 contractCoverageBalanceBefore = IERC20(coverageAsset).balanceOf(address(eigenCoverageDiamond));
        uint256 coverageAgentBalanceBefore = IERC20(coverageAsset).balanceOf(address(coverageAgent));
        uint256 coverageAgentCoordinatorBalanceBefore =
            IERC20(coverageAsset).balanceOf(address(IExampleCoverageAgent(coverageAgent).coordinator()));
        uint256 contractPositionBalanceBefore = IERC20(positionAsset).balanceOf(address(eigenCoverageDiamond));

        uint256 slashAmount = 10e6;
        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, slashAmount);

        // Expect ClaimSlashed event
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimSlashed(claimId, slashAmount);

        _executeSlash(claimIds, amounts);

        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
        assertEq(eigenCoverageDiamond.claimSlashAmounts(claimId), slashAmount);

        // Verify coverage agent has the same balance as before the slashing
        assertEq(
            IERC20(coverageAsset).balanceOf(address(coverageAgent)),
            coverageAgentBalanceBefore,
            "Coverage agent should have exact same amount before and after slashing"
        );

        // Verify coverage agent receives exactly the slashed amount
        assertEq(
            IERC20(coverageAsset).balanceOf(address(IExampleCoverageAgent(coverageAgent).coordinator()))
                - coverageAgentCoordinatorBalanceBefore,
            slashAmount,
            "Coverage agent coordinator should receive exact slashed amount"
        );

        // Verify contract coverage asset balance returns to baseline (tokens transferred out)
        assertEq(
            IERC20(coverageAsset).balanceOf(address(eigenCoverageDiamond)),
            contractCoverageBalanceBefore,
            "Contract should transfer out all slashed coverage tokens"
        );

        // Verify position asset balance returns to baseline (no tokens left over)
        assertEq(
            IERC20(positionAsset).balanceOf(address(eigenCoverageDiamond)),
            contractPositionBalanceBefore,
            "No position asset should remain after conversion to coverage asset"
        );
    }

    // ============ Comprehensive Slashing Flow Tests ============

    /// @notice Test slashing a claim with partial amount
    function test_slashClaims_partialAmount() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        // Verify position backing before slashing
        (int256 backingBeforeSlash,) = eigenCoverageProvider.positionBacking(positionId);
        assertGt(backingBeforeSlash, 0, "Position should be fully backed before slashing");

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 500e6);

        // Expect ClaimSlashed event
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimSlashed(claimId, 500e6);

        CoverageClaimStatus[] memory statuses = _executeSlash(claimIds, amounts);

        assertEq(uint8(statuses[0]), uint8(CoverageClaimStatus.Slashed));
        assertEq(eigenCoverageDiamond.claimSlashAmounts(claimId), 500e6);
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
    }

    /// @notice Test slashing multiple claims at once
    function test_slashClaims_multipleClaims() public {
        deal(rETH, staker, 2000e18);
        uint256 positionId = _setupSlashingPosition(2000e18);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 20e6);
        uint256 claimId1 = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        uint256 claimId2 = eigenCoverageProvider.issueClaim(positionId, 500e6, 30 days, 5e6);
        vm.stopPrank();

        // Verify both claims are fully backed after issuance and share same coverage utilization
        uint256 totalAllocated = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );
        (int256 backing1, uint16 coveragePct1) = eigenCoverageProvider.positionBacking(positionId);
        (int256 backing2, uint16 coveragePct2) = eigenCoverageProvider.positionBacking(positionId);
        assertGt(backing1, 0, "Position should be fully backed (first check)");
        assertGt(backing2, 0, "Position should be fully backed (second check)");
        uint256 expectedCoveragePct = (1500e6 * 10000) / totalAllocated;
        // forge-lint: disable-next-line(unsafe-typecast)
        assertApproxEqAbs(coveragePct1, uint16(expectedCoveragePct), 1, "Coverage % for claim1");
        // forge-lint: disable-next-line(unsafe-typecast)
        assertApproxEqAbs(coveragePct2, uint16(expectedCoveragePct), 1, "Coverage % for claim2");

        uint256[] memory claimIds = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        claimIds[0] = claimId1;
        claimIds[1] = claimId2;
        amounts[0] = 1000e6;
        amounts[1] = 500e6;

        // Expect ClaimSlashed events for both claims
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimSlashed(claimId1, 1000e6);
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimSlashed(claimId2, 500e6);

        CoverageClaimStatus[] memory statuses = _executeSlash(claimIds, amounts);

        assertEq(uint8(statuses[0]), uint8(CoverageClaimStatus.Slashed));
        assertEq(uint8(statuses[1]), uint8(CoverageClaimStatus.Slashed));
        assertEq(uint8(eigenCoverageProvider.claim(claimId1).status), uint8(CoverageClaimStatus.Slashed));
        assertEq(uint8(eigenCoverageProvider.claim(claimId2).status), uint8(CoverageClaimStatus.Slashed));
    }

    /// @notice Test slashing with exact claim amount
    function test_slashClaims_exactAmount() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);

        // Expect ClaimSlashed event
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimSlashed(claimId, 1000e6);

        CoverageClaimStatus[] memory statuses = _executeSlash(claimIds, amounts);

        assertEq(uint8(statuses[0]), uint8(CoverageClaimStatus.Slashed));
        assertEq(eigenCoverageDiamond.claimSlashAmounts(claimId), 1000e6);
    }

    /// @notice Test that slashing transfers tokens to coverage agent
    function test_slashClaims_tokenTransfer() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 initialBalance =
            IERC20(coverageAgent.asset()).balanceOf(address(IExampleCoverageAgent(coverageAgent).coordinator()));
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);

        // Expect ClaimSlashed event
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimSlashed(claimId, 1000e6);

        _executeSlash(claimIds, amounts);

        uint256 finalBalance =
            IERC20(coverageAgent.asset()).balanceOf(address(IExampleCoverageAgent(coverageAgent).coordinator()));
        // The coverage agent should receive the slashed amount (1000e6 USDC)
        // Account for potential swap slippage - allow 1% tolerance
        uint256 expectedMinBalance = initialBalance + (1000e6 * 99) / 100;
        assertGe(finalBalance, expectedMinBalance);
    }

    /// @notice Test that slash reverts with InsufficientSlashableCoverageAvailable(0) when wadToSlash > WAD and totalAllocatedStakeValue > amount (rounding edge case)
    /// @dev Mocks the swapper engine so swapForOutputQuote returns more than totalAllocatedStake (wadToSlash > WAD) and getQuote returns > amount (rounding branch).
    function test_RevertWhen_slash_InsufficientSlashableCoverageAvailable_rounding() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        _createAndApproveClaim(positionId, 1000e6, 10e6);

        uint256 slashAmount = 1000e6;
        address strategy = address(_getTestStrategy());
        address strategyAsset = address(IStrategy(strategy).underlyingToken());
        address coverageAsset = coverageAgent.asset();
        bytes memory poolInfo = abi.encodePacked(rETH, uint24(100), WETH, uint24(500), USDC);

        OperatorSet memory operatorSet = OperatorSet({
            avs: address(eigenCoverageDiamond),
            id: eigenServiceManager.getOperatorSetId(address(coverageAgent))
        });
        address[] memory operators = new address[](1);
        operators[0] = address(operator);
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = IStrategy(strategy);
        uint256 totalAllocatedStake = IAllocationManager(eigenServiceManager.eigenAddresses().allocationManager)
            .getAllocatedStake(operatorSet, operators, strategies)[0][0];

        // Mock swapper.getQuote(poolInfo, slashAmount, strategyAsset, coverageAsset) so swapForOutputQuote returns > totalAllocatedStake → wadToSlash > WAD
        vm.mockCall(
            address(uniswapV3SwapperEngine),
            abi.encodeWithSelector(
                ISwapperEngine.getQuote.selector,
                poolInfo,
                slashAmount,
                strategyAsset,
                coverageAsset
            ),
            abi.encode(totalAllocatedStake + 1)
        );
        // Mock swapper.getQuote(poolInfo, totalAllocatedStake, coverageAsset, strategyAsset) so getQuote returns > amount → rounding branch
        vm.mockCall(
            address(uniswapV3SwapperEngine),
            abi.encodeWithSelector(
                ISwapperEngine.getQuote.selector,
                poolInfo,
                totalAllocatedStake,
                coverageAsset,
                strategyAsset
            ),
            abi.encode(slashAmount + 1)
        );

        vm.prank(address(eigenCoverageDiamond));
        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.InsufficientSlashableCoverageAvailable.selector, 0)
        );
        eigenServiceManager.slashOperator(address(operator), strategy, address(coverageAgent), slashAmount);
    }

    /// @notice Test that slash reverts with InsufficientSlashableCoverageAvailable(deficit) when wadToSlash > WAD and totalAllocatedStakeValue <= amount
    /// @dev Mocks the swapper engine so swapForOutputQuote returns > totalAllocatedStake and getQuote returns < amount (deficit branch).
    function test_RevertWhen_slash_InsufficientSlashableCoverageAvailable_deficit() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        _createAndApproveClaim(positionId, 1000e6, 10e6);

        uint256 slashAmount = 1000e6;
        address strategy = address(_getTestStrategy());
        address strategyAsset = address(IStrategy(strategy).underlyingToken());
        address coverageAsset = coverageAgent.asset();
        bytes memory poolInfo = abi.encodePacked(rETH, uint24(100), WETH, uint24(500), USDC);

        OperatorSet memory operatorSet = OperatorSet({
            avs: address(eigenCoverageDiamond),
            id: eigenServiceManager.getOperatorSetId(address(coverageAgent))
        });
        address[] memory operators = new address[](1);
        operators[0] = address(operator);
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = IStrategy(strategy);
        uint256 totalAllocatedStake = IAllocationManager(eigenServiceManager.eigenAddresses().allocationManager)
            .getAllocatedStake(operatorSet, operators, strategies)[0][0];

        // Mock swapper.getQuote so swapForOutputQuote returns > totalAllocatedStake → wadToSlash > WAD
        vm.mockCall(
            address(uniswapV3SwapperEngine),
            abi.encodeWithSelector(
                ISwapperEngine.getQuote.selector,
                poolInfo,
                slashAmount,
                strategyAsset,
                coverageAsset
            ),
            abi.encode(totalAllocatedStake + 1)
        );
        // Mock swapper.getQuote so getQuote returns totalAllocatedStakeValue < amount → deficit branch
        uint256 totalAllocatedStakeValue = slashAmount - 1e6;
        vm.mockCall(
            address(uniswapV3SwapperEngine),
            abi.encodeWithSelector(
                ISwapperEngine.getQuote.selector,
                poolInfo,
                totalAllocatedStake,
                coverageAsset,
                strategyAsset
            ),
            abi.encode(totalAllocatedStakeValue)
        );

        vm.prank(address(eigenCoverageDiamond));
        uint256 expectedDeficit = slashAmount - totalAllocatedStakeValue;
        vm.expectRevert(
            abi.encodeWithSelector(
                ICoverageProvider.InsufficientSlashableCoverageAvailable.selector,
                expectedDeficit
            )
        );
        eigenServiceManager.slashOperator(address(operator), strategy, address(coverageAgent), slashAmount);
    }

    /// @notice Test slashing immediately after claim creation should succeed
    /// @dev The code allows slashing at any time during the coverage period (createdAt <= block.timestamp <= createdAt + duration)
    function test_slashClaims_immediatelyAfterCreation() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);

        // Verify position backing immediately after creation
        (int256 backingBeforeSlash,) = eigenCoverageProvider.positionBacking(positionId);
        assertGt(backingBeforeSlash, 0, "Position should be fully backed immediately after creation");

        // Slash immediately after creation (should succeed)
        uint256[] memory claimIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        claimIds[0] = claimId;
        amounts[0] = 1000e6;

        // Expect ClaimSlashed event
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimSlashed(claimId, 1000e6);

        CoverageClaimStatus[] memory statuses = eigenCoverageProvider.slashClaims(claimIds, amounts);
        vm.stopPrank();

        assertEq(uint8(statuses[0]), uint8(CoverageClaimStatus.Slashed));
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
    }

    /// @notice Test slashing after duration elapsed should revert
    function test_RevertWhen_slashClaims_afterDuration() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICoverageProvider.ClaimExpired.selector,
                claimId,
                eigenCoverageProvider.claim(claimId).createdAt + 30 days
            )
        );
        _executeSlash(claimIds, amounts, 31 days);
    }

    /// @notice Test slashing with amount exceeding claim should revert
    function test_RevertWhen_slashClaims_amountExceedsClaim() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 30 days, 10e6, 0);

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1001e6);

        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.SlashAmountExceedsClaim.selector, claimId, 1001e6, 1000e6)
        );
        _executeSlash(claimIds, amounts, 15 days);
    }

    /// @notice Test slashing with invalid claim status should revert
    function test_RevertWhen_slashClaims_invalidStatus() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 30 days, 10e6, 31 days);

        // Expect ClaimClosed event
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimClosed(claimId);

        eigenCoverageProvider.closeClaim(claimId);

        // Try to slash a completed claim
        vm.warp(block.timestamp - 1 days); // Go back to within duration window
        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);

        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.InvalidClaim.selector, claimId, CoverageClaimStatus.Completed)
        );
        _executeSlash(claimIds, amounts);
    }

    /// @notice Fuzz test for slashing with various amounts
    /// @param slashAmountBps The slash amount as percentage of claim amount in basis points (1-10000)
    function testFuzz_slashClaims_variousAmounts(uint256 slashAmountBps) public {
        // Bound early to skip invalid cases before expensive setup
        slashAmountBps = bound(slashAmountBps, 1, 10000);

        // Use smaller stake amount for faster setup (still sufficient for 1000e6 claim)
        uint256 positionId = _setupSlashingPosition(100e18);
        uint256 claimAmount = 1000e6;
        uint256 claimId = _createAndApproveClaim(positionId, claimAmount, 10e6);

        uint256 slashAmount = (claimAmount * slashAmountBps) / 10000;
        if (slashAmount == 0) {
            slashAmount = 1;
        }

        // Get asset addresses
        address coverageAsset = coverageAgent.asset();
        address positionAsset = eigenCoverageProvider.position(positionId).asset;

        // Check balances before slashing
        uint256 contractCoverageBalanceBefore = IERC20(coverageAsset).balanceOf(address(eigenCoverageDiamond));
        uint256 coverageAgentBalanceBefore = IERC20(coverageAsset).balanceOf(address(coverageAgent));
        uint256 contractPositionBalanceBefore = IERC20(positionAsset).balanceOf(address(eigenCoverageDiamond));
        uint256 coverageAgentCoordinatorBalanceBefore =
            IERC20(coverageAsset).balanceOf(address(IExampleCoverageAgent(coverageAgent).coordinator()));

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, slashAmount);
        CoverageClaimStatus[] memory statuses = _executeSlash(claimIds, amounts, 15 days);

        assertEq(uint8(statuses[0]), uint8(CoverageClaimStatus.Slashed));
        assertEq(eigenCoverageDiamond.claimSlashAmounts(claimId), slashAmount);
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));

        // Verify coverage agent has the same balance as before the slashing
        assertEq(
            IERC20(coverageAsset).balanceOf(address(coverageAgent)),
            coverageAgentBalanceBefore,
            "Coverage agent should have exact same amount before and after slashing"
        );

        // Verify coverage agent receives exactly the slashed amount
        assertEq(
            IERC20(coverageAsset).balanceOf(address(IExampleCoverageAgent(coverageAgent).coordinator()))
                - coverageAgentCoordinatorBalanceBefore,
            slashAmount,
            "Coverage agent coordinator should receive exact slashed amount"
        );

        // Verify contract coverage asset balance returns to baseline (tokens transferred out)
        assertEq(
            IERC20(coverageAsset).balanceOf(address(eigenCoverageDiamond)),
            contractCoverageBalanceBefore,
            "Contract should transfer out all slashed coverage tokens"
        );

        // Verify position asset balance returns to baseline (no tokens left over)
        assertEq(
            IERC20(positionAsset).balanceOf(address(eigenCoverageDiamond)),
            contractPositionBalanceBefore,
            "No position asset should remain after conversion to coverage asset"
        );
    }

    /// @notice Fuzz test for slashing timing (within valid window)
    /// @param timeOffset The time offset from claim creation in seconds (must be within duration)
    function testFuzz_slashClaims_timing(uint256 timeOffset) public {
        uint256 duration = 30 days;
        // Bound early to skip invalid cases before expensive setup
        timeOffset = bound(timeOffset, 1, duration);

        // Use smaller stake amount for faster setup (still sufficient for 1000e6 claim)
        uint256 positionId = _setupSlashingPosition(100e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, duration, 10e6, 0);
        uint256 createdAt = eigenCoverageProvider.claim(claimId).createdAt;

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);
        // Warp to the correct time based on createdAt
        vm.warp(createdAt + timeOffset);
        CoverageClaimStatus[] memory statuses = _executeSlash(claimIds, amounts);

        assertEq(uint8(statuses[0]), uint8(CoverageClaimStatus.Slashed));
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
    }

    /// @notice Fuzz test for multiple claims slashing with various amounts
    /// @param numClaims Number of claims to create and slash (1-10)
    function testFuzz_slashClaims_multipleClaims(uint256 numClaims) public {
        // Bound early to skip invalid cases before expensive setup
        numClaims = bound(numClaims, 1, 10);

        // Calculate required stake: max claim is 1000e6 + (9 * 100e6) = 1900e6, use 2000e18 stake
        uint256 maxStakeNeeded = 2000e18;
        deal(rETH, staker, maxStakeNeeded);
        uint256 positionId = _setupSlashingPosition(maxStakeNeeded);
        uint256[] memory claimIds = new uint256[](numClaims);
        uint256[] memory amounts = new uint256[](numClaims);

        // Calculate total reward needed (sum of all rewards)
        uint256 totalReward = 0;
        for (uint256 i = 0; i < numClaims; i++) {
            totalReward += (10e6 + (i * 1e6));
        }

        // Ensure coverage agent has enough tokens
        deal(coverageAgent.asset(), address(coverageAgent), totalReward);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), totalReward);

        // Create multiple claims
        for (uint256 i = 0; i < numClaims; i++) {
            uint256 claimAmount = 1000e6 + (i * 100e6); // Varying amounts
            uint256 reward = 10e6 + (i * 1e6);
            claimIds[i] = eigenCoverageProvider.issueClaim(positionId, claimAmount, 30 days, reward);
            amounts[i] = claimAmount; // Slash full amount
        }
        vm.stopPrank();

        CoverageClaimStatus[] memory statuses = _executeSlash(claimIds, amounts, 15 days);

        // Verify all claims are slashed
        for (uint256 i = 0; i < numClaims; i++) {
            assertEq(uint8(statuses[i]), uint8(CoverageClaimStatus.Slashed));
            assertEq(uint8(eigenCoverageProvider.claim(claimIds[i]).status), uint8(CoverageClaimStatus.Slashed));
            assertEq(eigenCoverageDiamond.claimSlashAmounts(claimIds[i]), amounts[i]);
        }
    }

    /// @notice Test slashing with slash coordinator (pending -> complete flow)
    function test_slashClaims_withCoordinator() public {
        MockSlashCoordinator coordinator = new MockSlashCoordinator();
        uint256 positionId = _setupSlashingPosition(1000e18, address(coordinator), Refundable.None);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        // Verify position backing before slashing
        (int256 backingBeforeSlash,) = eigenCoverageProvider.positionBacking(positionId);
        assertGt(backingBeforeSlash, 0, "Position should be fully backed before slashing");

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);

        // Warp time and expect ClaimSlashPending event (coordinator is set)
        vm.warp(block.timestamp + 15 days);

        vm.expectEmit(true, false, false, true);
        emit ICoverageProvider.ClaimSlashPending(claimId, address(coordinator));

        vm.startPrank(address(coverageAgent));
        CoverageClaimStatus[] memory statuses = eigenCoverageProvider.slashClaims(claimIds, amounts);
        vm.stopPrank();

        assertEq(uint8(statuses[0]), uint8(CoverageClaimStatus.PendingSlash));
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.PendingSlash));
        assertEq(eigenCoverageDiamond.claimSlashAmounts(claimId), 1000e6);

        // Complete the slash through coordinator
        coordinator.setStatus(claimId, SlashCoordinationStatus.Passed);

        // Expect ClaimSlashed event when completing the slash
        vm.expectEmit(true, false, false, true);
        emit ICoverageProvider.ClaimSlashed(claimId, 1000e6);

        eigenCoverageProvider.completeSlash(claimId);

        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
    }

    /// @notice Test completeSlash with invalid status should revert
    function test_RevertWhen_completeSlash_invalidStatus() public {
        MockSlashCoordinator coordinator = new MockSlashCoordinator();
        uint256 positionId = _setupSlashingPosition(1000e18, address(coordinator), Refundable.None);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        // Try to complete slash without initiating it first
        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.InvalidClaim.selector, claimId, CoverageClaimStatus.Issued)
        );
        eigenCoverageProvider.completeSlash(claimId);
    }

    /// @notice Test completeSlash with coordinator status not completed should revert
    function test_RevertWhen_completeSlash_coordinatorNotCompleted() public {
        MockSlashCoordinator coordinator = new MockSlashCoordinator();
        uint256 positionId = _setupSlashingPosition(1000e18, address(coordinator), Refundable.None);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);
        _executeSlash(claimIds, amounts, 15 days);

        // Coordinator status is still Pending
        assertEq(
            uint8(coordinator.status(address(eigenCoverageDiamond), claimId)), uint8(SlashCoordinationStatus.Pending)
        );

        // Try to complete slash
        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.SlashFailed.selector, claimId));
        eigenCoverageProvider.completeSlash(claimId);
    }

    /// @notice Test that slashing updates claim status correctly
    function test_slashClaims_statusUpdate() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        // Verify initial status
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Issued));

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);
        _executeSlash(claimIds, amounts, 15 days);

        // Verify status updated to Slashed
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
    }

    /// @notice Test that slashing cannot be done twice on the same claim
    function test_RevertWhen_slashClaims_alreadySlashed() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);
        _executeSlash(claimIds, amounts, 15 days);

        // Second slash should fail
        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.InvalidClaim.selector, claimId, CoverageClaimStatus.Slashed)
        );
        _executeSlash(claimIds, amounts);
    }

    /// @notice Test that _initiateSlash reverts when claim status is already Slashed
    function test_RevertWhen_initiateSlash_alreadySlashed() public {
        MockSlashCoordinator coordinator = new MockSlashCoordinator();
        uint256 positionId = _setupSlashingPosition(1000e18, address(coordinator), Refundable.None);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);

        // First slash with coordinator
        vm.warp(block.timestamp + 15 days);
        vm.startPrank(address(coverageAgent));
        eigenCoverageProvider.slashClaims(claimIds, amounts);
        vm.stopPrank();

        // Complete the slash through coordinator
        coordinator.setStatus(claimId, SlashCoordinationStatus.Passed);
        eigenCoverageProvider.completeSlash(claimId);

        // Verify claim is slashed
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));

        // Attempt to complete slash again should revert with InvalidClaim
        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.InvalidClaim.selector, claimId, CoverageClaimStatus.Slashed)
        );
        eigenCoverageProvider.completeSlash(claimId);
    }

    /// @notice Test that _initiateSlash runs immediately when coordinator returns Completed status
    function test_slashClaims_coordinatorCompletedImmediately() public {
        MockSlashCoordinatorImmediate coordinator = new MockSlashCoordinatorImmediate();
        uint256 positionId = _setupSlashingPosition(1000e18, address(coordinator), Refundable.None);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);

        // Warp time and expect ClaimSlashed event (coordinator returns Completed immediately)
        vm.warp(block.timestamp + 15 days);

        vm.expectEmit(true, false, false, true);
        emit ICoverageProvider.ClaimSlashed(claimId, 1000e6);

        vm.startPrank(address(coverageAgent));
        CoverageClaimStatus[] memory statuses = eigenCoverageProvider.slashClaims(claimIds, amounts);
        vm.stopPrank();

        // Verify status is PendingSlash in return value (set before initiateSlash is called)
        assertEq(uint8(statuses[0]), uint8(CoverageClaimStatus.PendingSlash));

        // But the actual claim status should be Slashed (updated by _initiateSlash)
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));

        // Verify slash amount was recorded
        assertEq(eigenCoverageDiamond.claimSlashAmounts(claimId), 1000e6);
    }

    // ============ Reservation Tests ============

    /// @notice Test reserving a claim
    function test_reserveClaim() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));

        // Expect ClaimReserved event
        vm.expectEmit(true, true, false, true);
        emit ICoverageProvider.ClaimReserved(positionId, 0, 1000e6, 30 days);

        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        assertEq(claimId, 0);

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(claim.amount, 1000e6);
        assertEq(claim.duration, 30 days);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Reserved));
        assertEq(claim.reward, 10e6);

        // Verify position backing is positive (fully backed even for reservation)
        (int256 backing,) = eigenCoverageProvider.positionBacking(positionId);
        assertGt(backing, 0, "Position should be fully backed");
    }

    /// @notice Test that reservations are not allowed when maxReservationTime is 0
    function test_RevertWhen_reserveClaim_reservationsNotAllowed() public {
        // Create position without reservation enabled (maxReservationTime = 0)
        uint256 positionId = _setupSlashingPosition(10e18);

        vm.startPrank(address(coverageAgent));
        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.ReservationNotAllowed.selector, positionId));
        eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();
    }

    /// @notice Test that issueClaim fails when strategy is no longer whitelisted after position creation
    function test_RevertWhen_issueClaim_strategyNotWhitelisted() public {
        // Setup position while strategy is whitelisted
        uint256 positionId = _setupSlashingPosition(10e18);

        // Remove the strategy from the whitelist
        address strategy = address(_getTestStrategy());
        eigenServiceManager.setStrategyWhitelist(strategy, false);
        assertFalse(eigenServiceManager.isStrategyWhitelisted(strategy));

        // Attempt to issue a claim - should fail because strategy is no longer whitelisted
        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        vm.expectRevert(abi.encodeWithSelector(IEigenOperatorProxy.StrategyNotWhitelisted.selector, strategy));
        eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();
    }

    /// @notice Test that reserveClaim fails when strategy is no longer whitelisted after position creation
    function test_RevertWhen_reserveClaim_strategyNotWhitelisted() public {
        // Setup position with reservation enabled while strategy is whitelisted
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        // Remove the strategy from the whitelist
        address strategy = address(_getTestStrategy());
        eigenServiceManager.setStrategyWhitelist(strategy, false);
        assertFalse(eigenServiceManager.isStrategyWhitelisted(strategy));

        // Attempt to reserve a claim - should fail because strategy is no longer whitelisted
        vm.startPrank(address(coverageAgent));
        vm.expectRevert(abi.encodeWithSelector(IEigenOperatorProxy.StrategyNotWhitelisted.selector, strategy));
        eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();
    }

    /// @notice Test converting a reserved claim to issued
    function test_convertReservedClaim() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);

        // Verify backing after reservation
        (int256 backingAfterReservation,) = eigenCoverageProvider.positionBacking(positionId);
        assertGt(backingAfterReservation, 0, "Reserved claim should be fully backed");

        // Approve tokens for the reward
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);

        // Expect ClaimIssued event
        vm.expectEmit(true, true, false, true);
        emit ICoverageProvider.ClaimIssued(positionId, claimId, 1000e6, 30 days);

        eigenCoverageProvider.convertReservedClaim(claimId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Issued));
        assertEq(claim.amount, 1000e6);
        assertEq(claim.duration, 30 days);

        // Verify backing after conversion (should remain the same since amount didn't change)
        (int256 backingAfterConversion,) = eigenCoverageProvider.positionBacking(positionId);
        assertEq(
            backingAfterConversion,
            backingAfterReservation,
            "Backing should remain same after conversion with same amount"
        );
    }

    /// @notice Test converting a reserved claim with smaller amount and duration
    function test_convertReservedClaim_partialConversion() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);

        // Verify backing after reservation
        (int256 backingAfterReservation,) = eigenCoverageProvider.positionBacking(positionId);
        assertGt(backingAfterReservation, 0, "Reserved claim should be fully backed");

        // Approve tokens for a smaller reward (pro-rata)
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 5e6);

        // Convert with smaller amount and duration
        eigenCoverageProvider.convertReservedClaim(claimId, 500e6, 15 days, 5e6);
        vm.stopPrank();

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Issued));
        assertEq(claim.amount, 500e6);
        assertEq(claim.duration, 15 days);

        // Verify backing increased after partial conversion (released 500e6 of coverage)
        (int256 backingAfterConversion,) = eigenCoverageProvider.positionBacking(positionId);
        assertGt(backingAfterConversion, backingAfterReservation, "Backing should increase after partial conversion");
    }

    /// @notice Test that converting a claim fails if reservation has expired
    function test_RevertWhen_convertReservedClaim_expired() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);

        uint256 expiredAt = block.timestamp + 1 hours;

        // Warp past reservation time
        vm.warp(block.timestamp + 2 hours);

        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);

        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.ReservationExpired.selector, claimId, expiredAt));
        eigenCoverageProvider.convertReservedClaim(claimId, 1000e6, 30 days, 10e6);
        vm.stopPrank();
    }

    /// @notice Test that amount cannot exceed reserved amount
    function test_RevertWhen_convertReservedClaim_amountExceedsReserved() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);

        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 20e6);

        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.AmountExceedsReserved.selector, claimId, 2000e6, 1000e6)
        );
        eigenCoverageProvider.convertReservedClaim(claimId, 2000e6, 30 days, 20e6);
        vm.stopPrank();
    }

    /// @notice Test that duration cannot exceed reserved duration
    function test_RevertWhen_convertReservedClaim_durationExceedsReserved() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);

        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 20e6);

        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.DurationExceedsReserved.selector, claimId, 60 days, 30 days)
        );
        eigenCoverageProvider.convertReservedClaim(claimId, 1000e6, 60 days, 20e6);
        vm.stopPrank();
    }

    /// @notice Test closing an expired reservation
    function test_closeClaim_expiredReservation() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        // Verify backing after reservation
        (int256 backingBeforeClose,) = eigenCoverageProvider.positionBacking(positionId);
        assertGt(backingBeforeClose, 0, "Reserved claim should be fully backed");

        // Warp past reservation time
        vm.warp(block.timestamp + 2 hours);

        // Anyone can close an expired reservation
        address anyone = makeAddr("anyone");
        vm.prank(anyone);

        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimClosed(claimId);

        eigenCoverageProvider.closeClaim(claimId);

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Completed));
    }

    /// @notice Test that non-coverage-agent cannot close a non-expired reservation
    function test_RevertWhen_closeClaim_reservationNotExpired() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);
        uint256 expiresAt = block.timestamp + 1 hours;
        vm.stopPrank();

        // Try to close before expiration as non-coverage-agent
        address anyone = makeAddr("anyone");
        vm.prank(anyone);
        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.ClaimNotExpired.selector, claimId, expiresAt));
        eigenCoverageProvider.closeClaim(claimId);
    }

    /// @notice Test that coverage agent can close their own claim
    function test_closeClaim_byCoverageAgent() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);

        // Verify backing after reservation
        (int256 backingBeforeClose,) = eigenCoverageProvider.positionBacking(positionId);
        assertGt(backingBeforeClose, 0, "Reserved claim should be fully backed");

        // Coverage agent can close their own claim even before expiration
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimClosed(claimId);

        eigenCoverageProvider.closeClaim(claimId);
        vm.stopPrank();

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Completed));
    }

    /// @notice Test closing an issued claim by coverage agent
    function test_closeClaim_issuedClaim() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));
        // Create a reservation and convert it
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);

        // Verify backing after reservation
        (int256 backingAfterReservation,) = eigenCoverageProvider.positionBacking(positionId);
        assertGt(backingAfterReservation, 0, "Reserved claim should be fully backed");

        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        eigenCoverageProvider.convertReservedClaim(claimId, 1000e6, 30 days, 10e6);

        // Verify backing after conversion
        (int256 backingAfterConversion,) = eigenCoverageProvider.positionBacking(positionId);
        assertEq(
            backingAfterConversion,
            backingAfterReservation,
            "Backing should remain same after conversion with same amount"
        );

        // Coverage agent can close their own issued claim
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimClosed(claimId);

        eigenCoverageProvider.closeClaim(claimId);
        vm.stopPrank();

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Completed));
    }

    /// @notice Test that anyone can close an issued claim after duration has elapsed
    function test_closeClaim_afterDurationElapsed() public {
        uint256 positionId = _setupSlashingPosition(10e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 30 days, 10e6, 0);

        // Verify backing after issuance
        (int256 backingBeforeClose,) = eigenCoverageProvider.positionBacking(positionId);
        assertGt(backingBeforeClose, 0, "Claim should be fully backed");

        // Warp past duration
        vm.warp(block.timestamp + 31 days);

        // Anyone can close an issued claim after duration has elapsed
        address anyone = makeAddr("anyone");
        vm.prank(anyone);

        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimClosed(claimId);

        eigenCoverageProvider.closeClaim(claimId);

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Completed));
    }

    /// @notice Test that closing an issued claim early with Full refundable policy refunds proportionally
    /// @dev Full means provider holds all rewards (no distribution over time), but refund is still time-based
    function test_closeClaim_earlyWithFullRefund() public {
        uint256 positionId = _setupSlashingPosition(10e18, address(0), Refundable.Full);
        uint256 reward = 10e6;
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 30 days, reward, 0);

        // Warp to halfway through the claim duration
        vm.warp(block.timestamp + 15 days);

        // Track coordinator balance before close (refund flows: provider -> agent -> coordinator)
        address coordinator = coverageAgent.coordinator();
        uint256 coordinatorBalanceBefore = IERC20(coverageAgent.asset()).balanceOf(coordinator);

        // Coverage agent closes claim early
        vm.prank(address(coverageAgent));
        eigenCoverageProvider.closeClaim(claimId);

        // Refundable.Full uses time-proportional refund on closeClaim (full refund only on liquidation).
        // 15 days remaining of 30 days = 50% refund.
        uint256 coordinatorBalanceAfter = IERC20(coverageAgent.asset()).balanceOf(coordinator);
        uint256 expectedRefund = reward / 2;
        assertEq(
            coordinatorBalanceAfter - coordinatorBalanceBefore,
            expectedRefund,
            "Half of reward should be refunded for remaining time"
        );

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Completed));
        assertEq(claim.duration, 15 days, "Duration should reflect actual coverage time");
        assertEq(claim.reward, reward - expectedRefund, "Reward should be reduced by refund amount");
    }

    /// @notice Test that closing an issued claim early with TimeWeighted refundable policy refunds proportionally
    function test_closeClaim_earlyWithTimeWeightedRefund() public {
        uint256 positionId = _setupSlashingPosition(10e18, address(0), Refundable.TimeWeighted);
        uint256 reward = 10e6;
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 30 days, reward, 0);

        // Warp to halfway through the claim duration
        vm.warp(block.timestamp + 15 days);

        // Track coordinator balance before close (refund flows: provider -> agent -> coordinator)
        address coordinator = coverageAgent.coordinator();
        uint256 coordinatorBalanceBefore = IERC20(coverageAgent.asset()).balanceOf(coordinator);

        // Coverage agent closes claim early
        vm.prank(address(coverageAgent));
        eigenCoverageProvider.closeClaim(claimId);

        // Verify time-weighted refund (50% remaining = 50% refund)
        uint256 coordinatorBalanceAfter = IERC20(coverageAgent.asset()).balanceOf(coordinator);
        uint256 expectedRefund = reward / 2; // 15 days remaining out of 30 days
        assertEq(
            coordinatorBalanceAfter - coordinatorBalanceBefore, expectedRefund, "Half of reward should be refunded"
        );

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Completed));
        assertEq(claim.duration, 15 days, "Duration should reflect actual coverage time");
    }

    /// @notice Test that closing an issued claim after duration elapsed with Full refundable policy does not refund
    function test_closeClaim_afterDurationElapsed_noRefund() public {
        uint256 positionId = _setupSlashingPosition(10e18, address(0), Refundable.Full);
        uint256 reward = 10e6;
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 30 days, reward, 0);

        // Warp past the claim duration
        vm.warp(block.timestamp + 31 days);

        // Track coordinator balance before close (refund flows: provider -> agent -> coordinator)
        address coordinator = coverageAgent.coordinator();
        uint256 coordinatorBalanceBefore = IERC20(coverageAgent.asset()).balanceOf(coordinator);

        // Anyone can close after duration elapsed
        eigenCoverageProvider.closeClaim(claimId);

        // Verify no refund was given (claim completed naturally)
        uint256 coordinatorBalanceAfter = IERC20(coverageAgent.asset()).balanceOf(coordinator);
        assertEq(coordinatorBalanceAfter, coordinatorBalanceBefore, "No refund should be given after duration elapsed");

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Completed));
    }

    /// @notice Test that closing an issued claim early with None refundable policy does not refund
    function test_closeClaim_earlyWithNoRefund() public {
        uint256 positionId = _setupSlashingPosition(10e18, address(0), Refundable.None);
        uint256 reward = 10e6;
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 30 days, reward, 0);

        // Warp to halfway through the claim duration
        vm.warp(block.timestamp + 15 days);

        // Track coordinator balance before close (refund flows: provider -> agent -> coordinator)
        address coordinator = coverageAgent.coordinator();
        uint256 coordinatorBalanceBefore = IERC20(coverageAgent.asset()).balanceOf(coordinator);

        // Coverage agent closes claim early
        vm.prank(address(coverageAgent));
        eigenCoverageProvider.closeClaim(claimId);

        // Verify no refund was given
        uint256 coordinatorBalanceAfter = IERC20(coverageAgent.asset()).balanceOf(coordinator);
        assertEq(coordinatorBalanceAfter, coordinatorBalanceBefore, "No refund should be given with None policy");

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Completed));
        assertEq(claim.duration, 15 days, "Duration should reflect actual coverage time");
    }

    // ============ Position Backing Tests ============

    /// @notice Test that backing decreases as multiple claims consume coverage
    function test_positionBacking_decreasesWithMultipleClaims() public {
        deal(rETH, staker, 2000e18);
        uint256 positionId = _setupSlashingPosition(2000e18);

        // Get total allocated coverage
        uint256 totalAllocated = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 30e6);

        // Issue first claim
        eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        (int256 backing1, uint16 coveragePct1) = eigenCoverageProvider.positionBacking(positionId);
        assertGt(backing1, 0, "First claim should be fully backed");
        uint256 expectedPct1 = (1000e6 * 10000) / totalAllocated;
        // forge-lint: disable-next-line(unsafe-typecast)
        assertApproxEqAbs(coveragePct1, uint16(expectedPct1), 1, "Coverage % after first claim");

        // Issue second claim - backing should decrease
        eigenCoverageProvider.issueClaim(positionId, 500e6, 30 days, 5e6);
        (int256 backing2, uint16 coveragePct2) = eigenCoverageProvider.positionBacking(positionId);
        assertGt(backing2, 0, "Second claim should still be backed");
        assertLt(backing2, backing1, "Backing should decrease with more claims");
        uint256 expectedPct2 = (1500e6 * 10000) / totalAllocated;
        // forge-lint: disable-next-line(unsafe-typecast)
        assertApproxEqAbs(coveragePct2, uint16(expectedPct2), 1, "Coverage % after second claim");

        // Issue third claim - further decrease
        eigenCoverageProvider.issueClaim(positionId, 500e6, 30 days, 5e6);
        (int256 backing3, uint16 coveragePct3) = eigenCoverageProvider.positionBacking(positionId);
        assertGt(backing3, 0, "Third claim should still be backed");
        assertLt(backing3, backing2, "Backing should continue decreasing");
        uint256 expectedPct3 = (2000e6 * 10000) / totalAllocated;
        // forge-lint: disable-next-line(unsafe-typecast)
        assertApproxEqAbs(coveragePct3, uint16(expectedPct3), 1, "Coverage % after third claim");

        vm.stopPrank();

        // All claims share the same backing since they're for the same operator/strategy/agent
        // Verify backing reflects remaining coverage
        uint256 totalClaimed = 1000e6 + 500e6 + 500e6;
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expectedBacking = int256(totalAllocated) - int256(totalClaimed);
        assertEq(backing3, expectedBacking, "Backing should equal allocated minus claimed");
    }

    /// @notice Test that claiming at exactly the coverage threshold succeeds and has positive backing
    function test_positionBacking_atCoverageThreshold() public {
        _setupwithAllocations();

        // Get allocated coverage amount
        uint256 totalAllocated = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        // Stake enough to cover exactly the claim amount
        address strategyAsset = address(_getTestStrategy().underlyingToken());
        address coverageAsset = address(coverageAgent.asset());
        (uint256 requiredStake,) = eigenPriceOracle.getQuote(totalAllocated, strategyAsset, coverageAsset);

        // Stake exactly what's needed (with small buffer for rounding)
        _stakeAndDelegateToOperator(requiredStake + 1e15);

        // Re-fetch allocated coverage after staking
        totalAllocated = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);

        // Issue claim for 70% of the allocated amount (at the coverage threshold)
        uint256 claimAmount = (totalAllocated * 70) / 100;
        eigenCoverageProvider.issueClaim(positionId, claimAmount, 30 days, 10e6);
        vm.stopPrank();

        // Backing should be positive (30% buffer remaining)
        (int256 backing, uint16 coveragePercentage) = eigenCoverageProvider.positionBacking(positionId);
        assertGt(backing, 0, "Backing should be positive at the coverage threshold");
        assertApproxEqAbs(coveragePercentage, 7000, 1, "Coverage utilization should be ~70% (7000 bps)");
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(backing, int256(totalAllocated - claimAmount), "Backing should equal remaining allocation");
    }

    /// @notice Test that positionMaxAmount reflects remaining coverage correctly
    function test_positionMaxAmount_decreasesWithClaims() public {
        deal(rETH, staker, 2000e18);
        uint256 positionId = _setupSlashingPosition(2000e18);

        uint256 initialMaxAmount = eigenCoverageProvider.positionMaxAmount(positionId);
        assertGt(initialMaxAmount, 0, "Initial max amount should be positive");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 20e6);

        // Issue a claim
        eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);

        uint256 maxAmountAfterClaim = eigenCoverageProvider.positionMaxAmount(positionId);
        assertEq(maxAmountAfterClaim, initialMaxAmount - 1000e6, "Max amount should decrease by claimed amount");

        // Issue another claim
        eigenCoverageProvider.issueClaim(positionId, 500e6, 30 days, 5e6);

        uint256 maxAmountAfterSecondClaim = eigenCoverageProvider.positionMaxAmount(positionId);
        assertEq(maxAmountAfterSecondClaim, initialMaxAmount - 1500e6, "Max amount should decrease by total claimed");
        vm.stopPrank();
    }

    /// @notice Test backing increases when claims are closed
    function test_positionBacking_increasesWhenClaimsClosed() public {
        deal(rETH, staker, 2000e18);
        uint256 positionId = _setupSlashingPosition(2000e18);

        uint256 totalAllocated = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 20e6);

        // Issue two claims
        eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        uint256 claimId2 = eigenCoverageProvider.issueClaim(positionId, 500e6, 30 days, 5e6);

        (int256 backingWithBothClaims, uint16 coveragePctWithBoth) = eigenCoverageProvider.positionBacking(positionId);
        uint256 expectedPctBoth = (1500e6 * 10000) / totalAllocated;
        // forge-lint: disable-next-line(unsafe-typecast)
        assertApproxEqAbs(coveragePctWithBoth, uint16(expectedPctBoth), 1, "Coverage % with both claims");

        // Close the second claim
        eigenCoverageProvider.closeClaim(claimId2);

        // Backing should increase for remaining claims
        (int256 backingAfterClose, uint16 coveragePctAfterClose) = eigenCoverageProvider.positionBacking(positionId);
        assertGt(backingAfterClose, backingWithBothClaims, "Backing should increase when claims are closed");
        assertEq(backingAfterClose, backingWithBothClaims + 500e6, "Backing should increase by closed claim amount");
        uint256 expectedPctAfterClose = (1000e6 * 10000) / totalAllocated;
        // forge-lint: disable-next-line(unsafe-typecast)
        assertApproxEqAbs(coveragePctAfterClose, uint16(expectedPctAfterClose), 1, "Coverage % after closing one");
        vm.stopPrank();
    }

    /// @notice Test that InsufficientCoverageAvailable error includes correct deficit amount and coverage percentage
    function test_RevertWhen_positionBacking_insufficientCoverage_correctDeficit() public {
        _setupwithAllocations();

        // Stake a small amount to get limited coverage
        _stakeAndDelegateToOperator(1e16); // Small stake

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        uint256 allocatedCoverage = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        // Try to claim more than allocated
        uint256 excessiveClaimAmount = allocatedCoverage + 1000e6;

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);

        // The deficit should be exactly the amount over the allocation
        uint256 expectedDeficit = excessiveClaimAmount - allocatedCoverage;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint16 coveragePercentage = uint16((excessiveClaimAmount * 10000) / allocatedCoverage);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICoverageProvider.InsufficientCoverageAvailable.selector, expectedDeficit, coveragePercentage
            )
        );
        eigenCoverageProvider.issueClaim(positionId, excessiveClaimAmount, 30 days, 10e6);
        vm.stopPrank();
    }

    /// @notice Test that backing becomes deficient (negative) when operator deallocates after claim is issued
    function test_positionBacking_deficientAfterDeallocation() public {
        deal(rETH, staker, 2000e18);
        uint256 positionId = _setupSlashingPosition(2000e18);

        // Get initial allocated coverage
        uint256 initialAllocated = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );
        assertGt(initialAllocated, 0, "Should have initial allocation");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);

        // Issue a claim while fully backed
        uint256 claimAmount = 1000e6;
        eigenCoverageProvider.issueClaim(positionId, claimAmount, 30 days, 10e6);
        vm.stopPrank();

        // Verify position is initially backed and coverage % matches
        {
            (int256 backingBefore, uint16 coveragePctBefore) = eigenCoverageProvider.positionBacking(positionId);
            assertGt(backingBefore, 0, "Position should be backed initially");
            uint256 expectedPctBefore = (claimAmount * 10000) / initialAllocated;
            // forge-lint: disable-next-line(unsafe-typecast)
            assertApproxEqAbs(coveragePctBefore, uint16(expectedPctBefore), 1, "Initial coverage %");
        }

        // Operator deallocates all coverage (sets magnitude to 0)
        address[] memory strategyAddresses = new address[](1);
        strategyAddresses[0] = address(_getTestStrategy());
        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = 0; // Deallocate

        operator.allocate(address(eigenCoverageDiamond), address(coverageAgent), strategyAddresses, magnitudes);

        // Roll forward past the deallocation delay (14 days worth of blocks)
        uint32 deallocationDelay = _getAllocationManager().DEALLOCATION_DELAY();
        vm.roll(block.number + deallocationDelay + 1);

        // Clear the deallocation queue to finalize the deallocation
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = _getTestStrategy();
        uint16[] memory numToClear = new uint16[](1);
        numToClear[0] = 1;
        _getAllocationManager().clearDeallocationQueue(address(operator), strategies, numToClear);

        // Verify allocation is now 0
        uint256 allocatedAfterDeallocation = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );
        assertEq(allocatedAfterDeallocation, 0, "Allocation should be zero after deallocation");

        // Now backing should be negative (deficient); allocation is 0 so coverage % is type(uint16).max
        (int256 backingAfter, uint16 coveragePctAfter) = eigenCoverageProvider.positionBacking(positionId);
        assertLt(backingAfter, 0, "Backing should be negative (deficient) after deallocation");
        assertEq(coveragePctAfter, type(uint16).max, "Coverage % should be max when allocation is zero");
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(backingAfter, -int256(claimAmount), "Backing deficit should equal claimed amount");
    }

    /// @notice Test that backing becomes partially deficient after partial deallocation
    function test_positionBacking_partialDeficitAfterPartialDeallocation() public {
        deal(rETH, staker, 2000e18);
        uint256 positionId = _setupSlashingPosition(2000e18);

        // Get initial allocation so we can calculate a claim amount that will be deficient after 50% deallocation
        uint256 initialAllocated = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        // Claim 60% of the initial allocation (within 70% threshold) - after 50% deallocation, this will be deficient
        uint256 claimAmount = (initialAllocated * 60) / 100;

        // Calculate minimum reward: (amount * minRate * duration) / (10000 * 365 days)
        // Position minRate is 100, duration is 30 days
        uint256 minReward = (claimAmount * 100 * 30 days) / (10000 * 365 days) + 1;

        vm.startPrank(address(coverageAgent));
        deal(coverageAgent.asset(), address(coverageAgent), minReward);
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), minReward);

        eigenCoverageProvider.issueClaim(positionId, claimAmount, 30 days, minReward);
        vm.stopPrank();

        // Verify position is initially backed (60% utilization = 6000 bps)
        {
            (int256 backingBefore, uint16 coveragePctBefore) = eigenCoverageProvider.positionBacking(positionId);
            assertGt(backingBefore, 0, "Position should be backed initially");
            assertApproxEqAbs(coveragePctBefore, 6000, 1, "Initial coverage % should be 60%");
        }

        // Operator partially deallocates (reduces magnitude to 50%)
        address[] memory strategyAddresses = new address[](1);
        strategyAddresses[0] = address(_getTestStrategy());
        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = 0.5e18; // Reduce to 50% of original 1e18

        operator.allocate(address(eigenCoverageDiamond), address(coverageAgent), strategyAddresses, magnitudes);

        // Roll forward past the deallocation delay
        uint32 deallocationDelay = _getAllocationManager().DEALLOCATION_DELAY();
        vm.roll(block.number + deallocationDelay + 1);

        // Clear the deallocation queue
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = _getTestStrategy();
        uint16[] memory numToClear = new uint16[](1);
        numToClear[0] = 1;
        _getAllocationManager().clearDeallocationQueue(address(operator), strategies, numToClear);

        // Get the new allocated amount (should be ~50% of initial)
        uint256 allocatedAfterDeallocation = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        // Verify deallocation occurred (allocation should be roughly half)
        assertLt(allocatedAfterDeallocation, initialAllocated, "Allocation should have decreased");

        // After 50% deallocation: allocation is ~50% of initial, claim is 60% of initial
        // So claim (60%) > allocation (50%), resulting in a deficit; utilization > 100% (> 10000 bps)
        (int256 backingAfter, uint16 coveragePctAfter) = eigenCoverageProvider.positionBacking(positionId);
        assertGt(coveragePctAfter, 10000, "Coverage % should exceed 100% when deficient");

        // Backing should be negative (deficient)
        assertLt(backingAfter, 0, "Backing should be negative after partial deallocation");

        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expectedBacking = int256(allocatedAfterDeallocation) - int256(claimAmount);
        assertEq(backingAfter, expectedBacking, "Backing deficit should match expected");
    }

    /// @notice Test that backing remains positive after partial deallocation when claim is small
    function test_positionBacking_remainsPositiveAfterPartialDeallocation() public {
        deal(rETH, staker, 2000e18);
        uint256 positionId = _setupSlashingPosition(2000e18);

        // Get initial allocation
        uint256 initialAllocated = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        // Claim only 25% of the initial allocation - after 50% deallocation, this will still be backed
        uint256 claimAmount = (initialAllocated * 25) / 100;

        // Calculate minimum reward: (amount * minRate * duration) / (10000 * 365 days)
        uint256 minReward = (claimAmount * 100 * 30 days) / (10000 * 365 days) + 1;

        vm.startPrank(address(coverageAgent));
        deal(coverageAgent.asset(), address(coverageAgent), minReward);
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), minReward);

        eigenCoverageProvider.issueClaim(positionId, claimAmount, 30 days, minReward);
        vm.stopPrank();

        // Verify position is initially backed (25% utilization = 2500 bps)
        {
            (int256 backingBefore, uint16 coveragePctBefore) = eigenCoverageProvider.positionBacking(positionId);
            assertGt(backingBefore, 0, "Position should be backed initially");
            assertApproxEqAbs(coveragePctBefore, 2500, 1, "Initial coverage % should be 25%");
        }

        // Operator partially deallocates (reduces magnitude to 50%)
        address[] memory strategyAddresses = new address[](1);
        strategyAddresses[0] = address(_getTestStrategy());
        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = 0.5e18; // Reduce to 50% of original 1e18

        operator.allocate(address(eigenCoverageDiamond), address(coverageAgent), strategyAddresses, magnitudes);

        // Roll forward past the deallocation delay
        uint32 deallocationDelay = _getAllocationManager().DEALLOCATION_DELAY();
        vm.roll(block.number + deallocationDelay + 1);

        // Clear the deallocation queue
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = _getTestStrategy();
        uint16[] memory numToClear = new uint16[](1);
        numToClear[0] = 1;
        _getAllocationManager().clearDeallocationQueue(address(operator), strategies, numToClear);

        // Get the new allocated amount (should be ~50% of initial)
        uint256 allocatedAfterDeallocation = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        // After 50% deallocation: allocation is ~50% of initial, claim is 25% of initial
        // So allocation (50%) > claim (25%), backing remains positive; utilization ~50% (5000 bps)
        (int256 backingAfter, uint16 coveragePctAfter) = eigenCoverageProvider.positionBacking(positionId);
        uint256 expectedPctAfter = (claimAmount * 10000) / allocatedAfterDeallocation;
        // forge-lint: disable-next-line(unsafe-typecast)
        assertApproxEqAbs(coveragePctAfter, uint16(expectedPctAfter), 1, "Coverage % after partial deallocation");

        // Backing should still be positive
        assertGt(backingAfter, 0, "Backing should remain positive when allocation > claim");

        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expectedBacking = int256(allocatedAfterDeallocation) - int256(claimAmount);
        assertEq(backingAfter, expectedBacking, "Backing should match expected");
    }

    // ============ claimTotalSlashAmount Tests ============

    /// @notice Test claimTotalSlashAmount returns correct amount after slashing
    function test_claimTotalSlashAmount() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        uint256 slashAmount = 500e6;
        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, slashAmount);

        _executeSlash(claimIds, amounts);

        // Verify claimTotalSlashAmount returns the correct amount
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), slashAmount);
    }

    /// @notice Test claimTotalSlashAmount returns 0 for non-existent claim
    function test_claimTotalSlashAmount_nonExistentClaim() public view {
        // Query slash amount for a claim ID that doesn't exist
        uint256 nonExistentClaimId = 999;
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(nonExistentClaimId), 0);
    }

    /// @notice Test claimTotalSlashAmount returns 0 for claim that hasn't been slashed
    function test_claimTotalSlashAmount_notSlashed() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        // Verify claimTotalSlashAmount returns 0 before any slashing
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), 0);
    }

    /// @notice Test claimTotalSlashAmount returns correct amount for partial slash
    function test_claimTotalSlashAmount_partialSlash() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        // Slash only 25% of the claim amount
        uint256 slashAmount = 250e6;
        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, slashAmount);

        _executeSlash(claimIds, amounts);

        // Verify claimTotalSlashAmount returns exactly the partial amount
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), slashAmount);
    }

    /// @notice Test claimTotalSlashAmount returns correct amount for exact (full) slash
    function test_claimTotalSlashAmount_exactAmount() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimAmount = 1000e6;
        uint256 claimId = _createAndApproveClaim(positionId, claimAmount, 10e6);

        // Slash the full claim amount
        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, claimAmount);

        _executeSlash(claimIds, amounts);

        // Verify claimTotalSlashAmount returns the full claim amount
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), claimAmount);
    }

    /// @notice Test claimTotalSlashAmount returns correct amounts for multiple claims
    function test_claimTotalSlashAmount_multipleClaims() public {
        deal(rETH, staker, 2000e18);
        uint256 positionId = _setupSlashingPosition(2000e18);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 20e6);
        uint256 claimId1 = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        uint256 claimId2 = eigenCoverageProvider.issueClaim(positionId, 500e6, 30 days, 5e6);
        vm.stopPrank();

        // Verify both claims have 0 slash amount before slashing
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId1), 0);
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId2), 0);

        uint256 slashAmount1 = 750e6;
        uint256 slashAmount2 = 300e6;

        uint256[] memory claimIds = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        claimIds[0] = claimId1;
        claimIds[1] = claimId2;
        amounts[0] = slashAmount1;
        amounts[1] = slashAmount2;

        _executeSlash(claimIds, amounts);

        // Verify each claim has its correct slash amount
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId1), slashAmount1);
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId2), slashAmount2);
    }

    /// @notice Test claimTotalSlashAmount with slash coordinator (PendingSlash state)
    function test_claimTotalSlashAmount_withSlashCoordinator() public {
        MockSlashCoordinator mockCoordinator = new MockSlashCoordinator();
        uint256 positionId = _setupSlashingPosition(1000e18, address(mockCoordinator), Refundable.None);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        uint256 slashAmount = 500e6;
        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, slashAmount);

        vm.startPrank(address(coverageAgent));
        CoverageClaimStatus[] memory statuses = eigenCoverageProvider.slashClaims(claimIds, amounts);
        vm.stopPrank();

        // Verify status is PendingSlash
        assertEq(uint8(statuses[0]), uint8(CoverageClaimStatus.PendingSlash));

        // Verify claimTotalSlashAmount is set even in PendingSlash state
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), slashAmount);

        // Complete the slash via coordinator
        mockCoordinator.setStatus(claimId, SlashCoordinationStatus.Passed);
        eigenCoverageProvider.completeSlash(claimId);

        // Verify slash amount remains the same after completion
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), slashAmount);
    }

    /// @notice Fuzz test for claimTotalSlashAmount with various amounts
    /// @param slashAmountBps The slash amount as percentage of claim amount in basis points (1-10000)
    function testFuzz_claimTotalSlashAmount(uint256 slashAmountBps) public {
        // Bound early to skip invalid cases before expensive setup
        slashAmountBps = bound(slashAmountBps, 1, 10000);

        uint256 positionId = _setupSlashingPosition(100e18);
        uint256 claimAmount = 1000e6;
        uint256 claimId = _createAndApproveClaim(positionId, claimAmount, 10e6);

        // Calculate slash amount from basis points
        uint256 slashAmount = (claimAmount * slashAmountBps) / 10000;
        if (slashAmount == 0) slashAmount = 1; // Ensure at least 1 wei

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, slashAmount);
        _executeSlash(claimIds, amounts, 15 days);

        // Verify claimTotalSlashAmount returns the exact slash amount
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), slashAmount);
    }

    // ============ repaySlashedClaim Tests ============

    /// @notice Test repaying a slashed claim fully
    function test_repaySlashedClaim() public {
        uint256 slashAmount = 500e6;
        (, uint256 claimId) = _setupSlashedClaim(1000e18, 1000e6, slashAmount);

        // Give coverage agent tokens to repay
        deal(coverageAgent.asset(), address(coverageAgent), slashAmount);

        // Approve diamond to spend tokens
        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), slashAmount);

        // Expect ClaimRepaid event (full repayment - emitted without amount)
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimRepaid(claimId);

        // Expect ClaimRepayment event (emitted on every repayment with amount)
        vm.expectEmit(true, false, false, true);
        emit ICoverageProvider.ClaimRepayment(claimId, slashAmount);

        eigenCoverageProvider.repaySlashedClaim(claimId, slashAmount);
        vm.stopPrank();

        // Verify claim status is now Repaid
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Repaid));

        // Verify slash amount is cleared
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), 0);
    }

    /// @notice Test partial repayment of a slashed claim
    function test_repaySlashedClaim_partialRepayment() public {
        uint256 slashAmount = 500e6;
        uint256 partialRepayment = 200e6;
        (, uint256 claimId) = _setupSlashedClaim(1000e18, 1000e6, slashAmount);

        // Give coverage agent tokens to repay
        deal(coverageAgent.asset(), address(coverageAgent), partialRepayment);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), partialRepayment);

        // Expect ClaimRepayment event (partial repayment - no ClaimRepaid event)
        vm.expectEmit(true, false, false, true);
        emit ICoverageProvider.ClaimRepayment(claimId, partialRepayment);

        eigenCoverageProvider.repaySlashedClaim(claimId, partialRepayment);
        vm.stopPrank();

        // Verify claim status remains Slashed (not fully repaid)
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));

        // Verify remaining slash amount
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), slashAmount - partialRepayment);
    }

    /// @notice Test multiple partial repayments leading to full repayment
    function test_repaySlashedClaim_multiplePartialRepayments() public {
        uint256 slashAmount = 500e6;
        (, uint256 claimId) = _setupSlashedClaim(1000e18, 1000e6, slashAmount);

        // First partial repayment
        uint256 firstRepayment = 200e6;
        deal(coverageAgent.asset(), address(coverageAgent), firstRepayment);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), firstRepayment);
        eigenCoverageProvider.repaySlashedClaim(claimId, firstRepayment);
        vm.stopPrank();

        // Verify still slashed
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), 300e6);

        // Second partial repayment
        uint256 secondRepayment = 150e6;
        deal(coverageAgent.asset(), address(coverageAgent), secondRepayment);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), secondRepayment);
        eigenCoverageProvider.repaySlashedClaim(claimId, secondRepayment);
        vm.stopPrank();

        // Verify still slashed
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), 150e6);

        // Final repayment (remaining amount)
        uint256 finalRepayment = 150e6;
        deal(coverageAgent.asset(), address(coverageAgent), finalRepayment);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), finalRepayment);
        eigenCoverageProvider.repaySlashedClaim(claimId, finalRepayment);
        vm.stopPrank();

        // Verify now fully repaid
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Repaid));
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), 0);
    }

    /// @notice Test overpayment is allowed (amount > slashAmount)
    function test_repaySlashedClaim_overpayment() public {
        uint256 slashAmount = 500e6;
        uint256 overpayment = 700e6; // More than slash amount
        (, uint256 claimId) = _setupSlashedClaim(1000e18, 1000e6, slashAmount);

        // Give coverage agent tokens to overpay
        deal(coverageAgent.asset(), address(coverageAgent), overpayment);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), overpayment);

        // Expect ClaimRepaid event (full repayment - overpayment counts as full)
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimRepaid(claimId);

        // Expect ClaimRepayment event with full overpayment amount
        vm.expectEmit(true, false, false, true);
        emit ICoverageProvider.ClaimRepayment(claimId, overpayment);

        eigenCoverageProvider.repaySlashedClaim(claimId, overpayment);
        vm.stopPrank();

        // Verify claim status is Repaid
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Repaid));

        // Verify slash amount is cleared (not negative)
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), 0);
    }

    /// @notice Test repayment reverts when claim is not slashed
    function test_RevertWhen_repaySlashedClaim_notSlashed() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        // Claim is Issued, not Slashed
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Issued));

        deal(coverageAgent.asset(), address(coverageAgent), 100e6);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 100e6);

        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.InvalidClaim.selector, claimId, CoverageClaimStatus.Issued)
        );
        eigenCoverageProvider.repaySlashedClaim(claimId, 100e6);
        vm.stopPrank();
    }

    /// @notice Test repayment reverts when claim is already repaid
    /// @notice Test additional repayment after claim is already repaid
    function test_repaySlashedClaim_additionalRepaymentAfterRepaid() public {
        uint256 slashAmount = 500e6;
        (, uint256 claimId) = _setupSlashedClaim(1000e18, 1000e6, slashAmount);

        // First repayment - full amount
        deal(coverageAgent.asset(), address(coverageAgent), slashAmount);
        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), slashAmount);
        eigenCoverageProvider.repaySlashedClaim(claimId, slashAmount);
        vm.stopPrank();

        // Verify claim is Repaid
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Repaid));

        // Additional repayment after already being Repaid should succeed
        uint256 additionalAmount = 100e6;
        deal(coverageAgent.asset(), address(coverageAgent), additionalAmount);
        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), additionalAmount);

        // Record logs to verify ClaimRepaid is NOT emitted
        vm.recordLogs();

        eigenCoverageProvider.repaySlashedClaim(claimId, additionalAmount);
        vm.stopPrank();

        // Get recorded logs and verify ClaimRepaid was NOT emitted
        bytes32 claimRepaidSelector = ICoverageProvider.ClaimRepaid.selector;
        bytes32 claimRepaymentSelector = ICoverageProvider.ClaimRepayment.selector;

        bool foundClaimRepaid = false;
        bool foundClaimRepayment = false;

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == claimRepaidSelector) {
                foundClaimRepaid = true;
            }
            if (logs[i].topics[0] == claimRepaymentSelector) {
                foundClaimRepayment = true;
            }
        }

        // ClaimRepaid should NOT be emitted for additional repayments
        assertFalse(foundClaimRepaid, "ClaimRepaid should not be emitted for additional repayments");

        // ClaimRepayment should be emitted
        assertTrue(foundClaimRepayment, "ClaimRepayment should be emitted for additional repayments");

        // Verify claim status remains Repaid
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Repaid));

        // Verify slash amount is still 0 (already cleared from first full repayment)
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), 0);
    }

    /// @notice Test that repayment transfers tokens from coverage agent to diamond
    function test_repaySlashedClaim_tokenTransfer() public {
        uint256 slashAmount = 500e6;
        uint256 repayAmount = 300e6;
        (, uint256 claimId) = _setupSlashedClaim(1000e18, 1000e6, slashAmount);

        // Give coverage agent tokens to repay
        deal(coverageAgent.asset(), address(coverageAgent), repayAmount);

        uint256 coverageAgentBalanceBefore = IERC20(coverageAgent.asset()).balanceOf(address(coverageAgent));

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), repayAmount);
        eigenCoverageProvider.repaySlashedClaim(claimId, repayAmount);
        vm.stopPrank();

        // Verify tokens were transferred from coverage agent
        assertEq(
            IERC20(coverageAgent.asset()).balanceOf(address(coverageAgent)), coverageAgentBalanceBefore - repayAmount
        );

        // Note: Diamond balance may not increase by full amount due to reward submission
        // The tokens are used to submit operator rewards, so we just verify they left the coverage agent
    }

    /// @notice Test repayment with exact slash amount (boundary condition)
    function test_repaySlashedClaim_exactAmount() public {
        uint256 slashAmount = 500e6;
        (, uint256 claimId) = _setupSlashedClaim(1000e18, 1000e6, slashAmount);

        // Give coverage agent exact tokens to repay
        deal(coverageAgent.asset(), address(coverageAgent), slashAmount);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), slashAmount);
        eigenCoverageProvider.repaySlashedClaim(claimId, slashAmount);
        vm.stopPrank();

        // Verify claim status is Repaid (amount >= slashAmount)
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Repaid));
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), 0);
    }

    /// @notice Fuzz test for repaySlashedClaim with various repayment amounts
    /// @param repaymentBps The repayment amount as percentage of slash amount in basis points (1-15000)
    function testFuzz_repaySlashedClaim(uint256 repaymentBps) public {
        // Bound early to include overpayment scenarios (up to 150% of slash amount)
        repaymentBps = bound(repaymentBps, 1, 15000);

        uint256 slashAmount = 500e6;
        (, uint256 claimId) = _setupSlashedClaim(100e18, 1000e6, slashAmount);

        // Calculate repayment amount from basis points
        uint256 repayAmount = (slashAmount * repaymentBps) / 10000;
        if (repayAmount == 0) repayAmount = 1; // Ensure at least 1 wei

        // Give coverage agent tokens to repay
        deal(coverageAgent.asset(), address(coverageAgent), repayAmount);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), repayAmount);
        eigenCoverageProvider.repaySlashedClaim(claimId, repayAmount);
        vm.stopPrank();

        // Verify results based on repayment amount
        if (repayAmount >= slashAmount) {
            // Full repayment or overpayment
            assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Repaid));
            assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), 0);
        } else {
            // Partial repayment
            assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
            assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), slashAmount - repayAmount);
        }
    }

    // ============ EigenCoverageProviderFacet Branch Coverage Tests ============

    // --- onIsRegistered (line 35) ---

    /// @notice Test that onIsRegistered reverts if coverage agent is already registered
    function test_RevertWhen_onIsRegistered_alreadyRegistered() public {
        // coverageAgent is already registered in setUp via coverageAgent.registerCoverageProvider(...)
        // Calling onIsRegistered again from the same coverage agent should revert
        vm.prank(address(coverageAgent));
        vm.expectRevert(abi.encodeWithSelector(IEigenServiceManager.CoverageAgentAlreadyRegistered.selector));
        eigenCoverageProvider.onIsRegistered();
    }

    // --- createPosition validation branches (lines 62, 63, 69, 75, 77) ---

    /// @notice Test that createPosition reverts when expiryTimestamp is in the past
    function test_RevertWhen_createPosition_expiredTimestamp() public {
        _setupwithAllocations();

        uint256 pastTimestamp = block.timestamp - 1;
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: pastTimestamp,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });

        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.TimestampInvalid.selector, pastTimestamp));
        eigenCoverageProvider.createPosition(data, "");
    }

    /// @notice Test that createPosition reverts when minRate exceeds 10000
    function test_RevertWhen_createPosition_invalidMinRate() public {
        _setupwithAllocations();

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 10001,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });

        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.MinRateInvalid.selector, uint16(10001)));
        eigenCoverageProvider.createPosition(data, "");
    }

    /// @notice Test that createPosition reverts when asset has no mapped strategy (strategy == address(0))
    function test_RevertWhen_createPosition_unmappedAsset() public {
        _setupwithAllocations();

        // Use an asset that has no strategy mapping (e.g., WETH which is not mapped in setUp)
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: WETH, // No strategy mapped for WETH
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });

        vm.expectRevert(abi.encodeWithSelector(IEigenOperatorProxy.StrategyNotWhitelisted.selector, address(0)));
        eigenCoverageProvider.createPosition(data, "");
    }

    /// @notice Test that createPosition reverts when strategy is not whitelisted
    function test_RevertWhen_createPosition_strategyNotWhitelisted() public {
        _setupwithAllocations();

        // Remove the strategy from whitelist
        address strategy = address(_getTestStrategy());
        eigenServiceManager.setStrategyWhitelist(strategy, false);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });

        vm.expectRevert(abi.encodeWithSelector(IEigenOperatorProxy.StrategyNotWhitelisted.selector, strategy));
        eigenCoverageProvider.createPosition(data, "");
    }

    // --- reserveClaim validation branches (lines 160, 163) ---

    /// @notice Test that reserveClaim reverts with zero amount
    function test_RevertWhen_reserveClaim_zeroAmount() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.prank(address(coverageAgent));
        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.ZeroAmount.selector));
        eigenCoverageProvider.reserveClaim(positionId, 0, 30 days, 10e6);
    }

    // --- convertReservedClaim validation branches (lines 203, 206, 222, 226) ---

    /// @notice Test that convertReservedClaim reverts when claim is not in Reserved status
    function test_RevertWhen_convertReservedClaim_notReserved() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(10e18);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        // Issue a regular claim (status = Issued, not Reserved)
        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);

        // Try to convert an Issued claim (not Reserved)
        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.ClaimNotReserved.selector, claimId));
        eigenCoverageProvider.convertReservedClaim(claimId, 1000e6, 30 days, 10e6);
        vm.stopPrank();
    }

    /// @notice Test that convertReservedClaim reverts when amount is zero
    function test_RevertWhen_convertReservedClaim_zeroAmount() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);

        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.ZeroAmount.selector));
        eigenCoverageProvider.convertReservedClaim(claimId, 0, 30 days, 0);
        vm.stopPrank();
    }

    /// @notice Test that convertReservedClaim reverts when reward is insufficient
    function test_RevertWhen_convertReservedClaim_insufficientReward() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);

        // The minimum reward for 1000e6 coverage at 100 bps for 30 days:
        // minReward = (1000e6 * 100 * 30 days) / (10000 * 365 days)
        // Try with a very small reward that doesn't meet the minimum
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 1);
        vm.expectRevert(); // InsufficientReward
        eigenCoverageProvider.convertReservedClaim(claimId, 1000e6, 30 days, 1);
        vm.stopPrank();
    }

    // --- closeClaim validation branch (line 269) ---

    /// @notice Test that closeClaim reverts when claim status is neither Reserved nor Issued
    function test_RevertWhen_closeClaim_invalidStatus() public {
        uint256 positionId = _setupSlashingPosition(100e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        // Slash the claim first to change its status to Slashed
        uint256[] memory claimIds = new uint256[](1);
        claimIds[0] = claimId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500e6;
        _executeSlash(claimIds, amounts);

        // Verify claim is now Slashed
        CoverageClaim memory slashedClaim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(slashedClaim.status), uint8(CoverageClaimStatus.Slashed));

        // Try to close a Slashed claim - should revert
        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.InvalidClaim.selector, claimId, CoverageClaimStatus.Slashed)
        );
        eigenCoverageProvider.closeClaim(claimId);
    }

    // ============ liquidateClaim ============

    // --- Revert Cases ---

    /// @notice Test 1: Revert when attempting to liquidate to the same position
    function test_RevertWhen_liquidateClaim_samePosition() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.SamePosition.selector, positionId));
        eigenCoverageLiquidatable.liquidateClaim(claimId, positionId);
    }

    /// @notice Test 2: Revert when old and new positions have different coverage agents
    function test_RevertWhen_liquidateClaim_differentCoverageAgent() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        // Create a second position (same agent/asset) then override its coverageAgent via vm.store
        uint256 newPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);

        // Overwrite coverageAgent (lower 160 bits of struct slot 0) to a different address
        bytes32 slot = _positionStorageSlot(newPositionId, 0);
        bytes32 currentValue = vm.load(address(eigenCoverageDiamond), slot);
        address fakeAgent = address(0xBEEF);
        bytes32 newValue = (currentValue & bytes32(~uint256(type(uint160).max))) | bytes32(uint256(uint160(fakeAgent)));
        vm.store(address(eigenCoverageDiamond), slot, newValue);

        // Verify the override worked
        CoveragePosition memory newPos = eigenCoverageProvider.position(newPositionId);
        assertEq(newPos.coverageAgent, fakeAgent);

        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.InvalidCoverageAgent.selector, address(coverageAgent), fakeAgent)
        );
        eigenCoverageLiquidatable.liquidateClaim(claimId, newPositionId);
    }

    /// @notice Test 3: Revert when old and new positions have different assets
    function test_RevertWhen_liquidateClaim_differentAsset() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        // Create a second position (same agent/asset) then override its asset via vm.store
        uint256 newPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);

        // Overwrite asset (lower 160 bits of struct slot 3) to a different address
        bytes32 slot = _positionStorageSlot(newPositionId, 3);
        bytes32 currentValue = vm.load(address(eigenCoverageDiamond), slot);
        address fakeAsset = address(0xDEAD);
        bytes32 newValue = (currentValue & bytes32(~uint256(type(uint160).max))) | bytes32(uint256(uint160(fakeAsset)));
        vm.store(address(eigenCoverageDiamond), slot, newValue);

        // Verify the override worked
        CoveragePosition memory newPos = eigenCoverageProvider.position(newPositionId);
        assertEq(newPos.coverageAgent, address(coverageAgent), "Coverage agent should still match");
        assertEq(newPos.asset, fakeAsset, "Asset should be overridden");

        address realAsset = address(_getTestStrategy().underlyingToken());
        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.InvalidCoverageAsset.selector, realAsset, fakeAsset));
        eigenCoverageLiquidatable.liquidateClaim(claimId, newPositionId);
    }

    /// @notice Test 4: Revert when caller is not authorized by the new position's operator
    function test_RevertWhen_liquidateClaim_notOperatorAuthorized() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        uint256 oldPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);
        uint256 newPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);
        uint256 claimId = _createAndApproveClaim(oldPositionId, 1000e6, 10e6);

        address unauthorizedCaller = makeAddr("unauthorized");
        vm.prank(unauthorizedCaller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IEigenServiceManager.NotOperatorAuthorized.selector, address(operator), unauthorizedCaller
            )
        );
        eigenCoverageLiquidatable.liquidateClaim(claimId, newPositionId);
    }

    /// @notice Test 5: Revert when claim status is Completed
    function test_RevertWhen_liquidateClaim_invalidClaim_completed() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        uint256 oldPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);
        uint256 newPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);
        uint256 claimId = _createAndApproveClaim(oldPositionId, 1000e6, 10e6);

        // Close the claim by warping past duration
        vm.warp(block.timestamp + 31 days);
        eigenCoverageProvider.closeClaim(claimId);
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Completed));

        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.InvalidClaim.selector, claimId, CoverageClaimStatus.Completed)
        );
        eigenCoverageLiquidatable.liquidateClaim(claimId, newPositionId);
    }

    /// @notice Test 6: Revert when claim status is PendingSlash
    function test_RevertWhen_liquidateClaim_invalidClaim_pendingSlash() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        // Create position with a slash coordinator that holds slashes as pending
        MockSlashCoordinator mockCoordinator = new MockSlashCoordinator();
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(mockCoordinator),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 oldPositionId = eigenCoverageProvider.createPosition(data, "");
        uint256 newPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);
        uint256 claimId = _createAndApproveClaim(oldPositionId, 1000e6, 10e6);

        // Slash to get PendingSlash status
        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 500e6);
        _executeSlash(claimIds, amounts);
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.PendingSlash));

        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.InvalidClaim.selector, claimId, CoverageClaimStatus.PendingSlash)
        );
        eigenCoverageLiquidatable.liquidateClaim(claimId, newPositionId);
    }

    /// @notice Test 7: Revert when claim status is Slashed
    function test_RevertWhen_liquidateClaim_invalidClaim_slashed() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        uint256 oldPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);
        uint256 newPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);
        uint256 claimId = _createAndApproveClaim(oldPositionId, 1000e6, 10e6);

        // Slash (no coordinator = instant slash)
        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 500e6);
        _executeSlash(claimIds, amounts);
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));

        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.InvalidClaim.selector, claimId, CoverageClaimStatus.Slashed)
        );
        eigenCoverageLiquidatable.liquidateClaim(claimId, newPositionId);
    }

    /// @notice Test 8: Revert when claim status is Reserved
    function test_RevertWhen_liquidateClaim_invalidClaim_reserved() public {
        uint256 positionId = _setupPositionWithReservation(1000e18, 7 days);
        uint256 newPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);

        // Reserve a claim (status = Reserved)
        vm.startPrank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Reserved));

        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.InvalidClaim.selector, claimId, CoverageClaimStatus.Reserved)
        );
        eigenCoverageLiquidatable.liquidateClaim(claimId, newPositionId);
    }

    /// @notice Test 9: Revert when claim status is Repaid
    function test_RevertWhen_liquidateClaim_invalidClaim_repaid() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        uint256 oldPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);
        uint256 newPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);
        uint256 claimId = _createAndApproveClaim(oldPositionId, 1000e6, 10e6);

        // Slash then fully repay to reach Repaid status
        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 500e6);
        _executeSlash(claimIds, amounts);

        // Repay the slashed amount (must be called by the coverage agent with funds + approval)
        address coverageAsset = coverageAgent.asset();
        deal(coverageAsset, address(coverageAgent), 500e6);
        vm.startPrank(address(coverageAgent));
        IERC20(coverageAsset).approve(address(eigenCoverageDiamond), 500e6);
        eigenCoverageProvider.repaySlashedClaim(claimId, 500e6);
        vm.stopPrank();
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Repaid));

        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.InvalidClaim.selector, claimId, CoverageClaimStatus.Repaid)
        );
        eigenCoverageLiquidatable.liquidateClaim(claimId, newPositionId);
    }

    /// @notice Test 10: Revert when claim has expired
    function test_RevertWhen_liquidateClaim_claimExpired() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        uint256 oldPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);
        uint256 newPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);
        uint256 claimId = _createAndApproveClaim(oldPositionId, 1000e6, 10e6);

        CoverageClaim memory claimData = eigenCoverageProvider.claim(claimId);
        uint256 expiresAt = claimData.createdAt + claimData.duration;

        // Warp past the claim's duration
        vm.warp(expiresAt + 1);

        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.ClaimExpired.selector, claimId, expiresAt));
        eigenCoverageLiquidatable.liquidateClaim(claimId, newPositionId);
    }

    /// @notice Test 11: Revert when coverage percentage is below liquidation threshold (position is healthy)
    function test_RevertWhen_liquidateClaim_meetsLiquidationThreshold() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        uint256 oldPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);
        uint256 newPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);

        // Issue a small claim that keeps utilization well below 90%
        uint256 maxCoverage = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );
        uint256 claimAmount = (maxCoverage * 5000) / 10000; // 50% utilization
        uint256 reward = (claimAmount * 100 * 30 days) / (10000 * 365 days);
        if (reward < 1e6) reward = 1e6;
        deal(coverageAgent.asset(), address(coverageAgent), reward * 2);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), reward);
        uint256 claimId = eigenCoverageProvider.issueClaim(oldPositionId, claimAmount, 30 days, reward);
        vm.stopPrank();

        (, uint16 coveragePercentage) = eigenCoverageProvider.positionBacking(oldPositionId);
        assertTrue(coveragePercentage < 9000, "Coverage should be below liquidation threshold");

        vm.expectRevert(
            abi.encodeWithSelector(
                ICoverageLiquidatable.MeetsLiquidationThreshold.selector, uint16(9000), coveragePercentage
            )
        );
        eigenCoverageLiquidatable.liquidateClaim(claimId, newPositionId);
    }

    /// @notice Test 12: Revert when claim duration exceeds the new position's expiry
    function test_RevertWhen_liquidateClaim_durationExceedsExpiry() public {
        (,, uint256 claimId) = _setupLiquidatableScenario(1000e18, 9100, Refundable.None);

        // Create a new position with a short expiry (15 days from now) - claim has 30 days duration
        uint256 shortExpiryPositionId = _createPositionForOperator(operator, Refundable.None, 15 days);

        CoverageClaim memory claimData = eigenCoverageProvider.claim(claimId);
        uint256 claimEnd = claimData.createdAt + claimData.duration;
        CoveragePosition memory shortPos = eigenCoverageProvider.position(shortExpiryPositionId);

        assertTrue(claimEnd > shortPos.expiryTimestamp, "Claim end should exceed short position expiry");

        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.DurationExceedsExpiry.selector, claimEnd, shortPos.expiryTimestamp)
        );
        eigenCoverageLiquidatable.liquidateClaim(claimId, shortExpiryPositionId);
    }

    /// @notice Test 13: Revert when the new position's operator has insufficient coverage
    function test_RevertWhen_liquidateClaim_insufficientCoverageOnNewPosition() public {
        // Set up first operator with high utilization
        (,, uint256 claimId) = _setupLiquidatableScenario(1000e18, 9100, Refundable.None);

        // Set up a second operator with very small stake (insufficient to absorb the claim)
        _setupSecondOperatorWithAllocations(1e16); // Tiny stake

        uint256 op2PositionId = _createPositionForOperator(operator2, Refundable.None, 365 days);

        vm.expectRevert(); // InsufficientCoverageAvailable - exact params depend on runtime values
        eigenCoverageLiquidatable.liquidateClaim(claimId, op2PositionId);
    }

    // --- Happy Path Cases ---

    /// @notice Test 14: Successful liquidation updates all state correctly
    function test_liquidateClaim_success() public {
        (uint256 oldPositionId, uint256 newPositionId, uint256 claimId) =
            _setupLiquidatableScenario(1000e18, 9100, Refundable.None);

        CoverageClaim memory claimBefore = eigenCoverageProvider.claim(claimId);
        assertEq(claimBefore.positionId, oldPositionId);

        // Expect the ClaimLiquidated event
        vm.expectEmit(true, true, true, true);
        emit ICoverageLiquidatable.ClaimLiquidated(claimId, oldPositionId, newPositionId);

        eigenCoverageLiquidatable.liquidateClaim(claimId, newPositionId);

        // Verify state changes
        CoverageClaim memory claimAfter = eigenCoverageProvider.claim(claimId);
        assertEq(claimAfter.positionId, newPositionId, "Claim should point to new position");
        assertEq(claimAfter.createdAt, block.timestamp, "createdAt should be reset to current timestamp");
        assertEq(uint8(claimAfter.status), uint8(CoverageClaimStatus.Issued), "Status should remain Issued");
        assertEq(claimAfter.amount, claimBefore.amount, "Claim amount should not change");
        assertEq(claimAfter.duration, claimBefore.duration, "Duration should not change");
    }

    /// @notice Test 15: Rewards are captured for old operator before position swap
    function test_liquidateClaim_capturesRewardsBeforeSwap() public {
        (, uint256 newPositionId, uint256 claimId) = _setupLiquidatableScenario(1000e18, 9100, Refundable.None);

        // Warp forward 15 days (half the duration) so there are rewards to capture
        vm.warp(block.timestamp + 15 days);

        // Check reward distribution before liquidation
        (uint256 distAmount,) =
            EigenCoverageProviderFacet(address(eigenCoverageDiamond)).claimRewardDistributions(claimId);
        assertEq(distAmount, 0, "No rewards should be distributed yet");

        eigenCoverageLiquidatable.liquidateClaim(claimId, newPositionId);

        // After liquidation, rewards should have been captured for the old operator
        (uint256 distAmountAfter,) =
            EigenCoverageProviderFacet(address(eigenCoverageDiamond)).claimRewardDistributions(claimId);
        assertGt(distAmountAfter, 0, "Rewards should have been distributed during liquidation");
    }

    /// @notice Test 16: TimeWeighted refundable rewards are captured correctly before swap
    function test_liquidateClaim_refundableTimeWeighted() public {
        (, uint256 newPositionId, uint256 claimId) = _setupLiquidatableScenario(1000e18, 9100, Refundable.TimeWeighted);

        // Warp forward 15 days (half duration)
        vm.warp(block.timestamp + 15 days);

        eigenCoverageLiquidatable.liquidateClaim(claimId, newPositionId);

        // Verify time-weighted rewards were captured (should be ~50% of total reward)
        (uint256 distAmount,) =
            EigenCoverageProviderFacet(address(eigenCoverageDiamond)).claimRewardDistributions(claimId);
        // Time-weighted: reward proportional to elapsed time. After 15 of 30 days ≈ 50%
        assertGt(distAmount, 0, "Time-weighted rewards should be distributed");
    }

    /// @notice Test 17: Full refundable policy returns 0 rewards during liquidation (claim still Issued)
    function test_liquidateClaim_refundableFull() public {
        (, uint256 newPositionId, uint256 claimId) = _setupLiquidatableScenario(1000e18, 9100, Refundable.Full);

        vm.warp(block.timestamp + 15 days);

        // For Full refund, captureRewards returns 0 when claim is Issued (not Completed)
        eigenCoverageLiquidatable.liquidateClaim(claimId, newPositionId);

        (uint256 distAmount,) =
            EigenCoverageProviderFacet(address(eigenCoverageDiamond)).claimRewardDistributions(claimId);
        assertEq(distAmount, 0, "Full refundable should not distribute rewards while claim is Issued");
    }

    /// @notice Test 18: Multiple sequential liquidations on the same claim
    function test_liquidateClaim_multipleLiquidations() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);
        eigenCoverageLiquidatable.setCoverageThreshold(bytes32(uint256(uint160(address(operator)))), 9500);

        // Create 3 positions
        uint256 posA = _createPositionForOperator(operator, Refundable.None, 365 days);
        uint256 posB = _createPositionForOperator(operator, Refundable.None, 365 days);
        uint256 posC = _createPositionForOperator(operator, Refundable.None, 365 days);

        // Issue claim at 91% on position A
        uint256 maxCoverage = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );
        uint256 claimAmount = (maxCoverage * 9100) / 10000;
        uint256 reward = (claimAmount * 100 * 30 days) / (10000 * 365 days);
        if (reward < 1e6) reward = 1e6;
        deal(coverageAgent.asset(), address(coverageAgent), reward * 2);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), reward);
        uint256 claimId = eigenCoverageProvider.issueClaim(posA, claimAmount, 30 days, reward);
        vm.stopPrank();

        // First liquidation: A -> B
        eigenCoverageLiquidatable.liquidateClaim(claimId, posB);
        CoverageClaim memory afterFirst = eigenCoverageProvider.claim(claimId);
        assertEq(afterFirst.positionId, posB, "Should now point to position B");
        uint256 firstCreatedAt = afterFirst.createdAt;

        // Warp a bit and liquidate again: B -> C
        vm.warp(block.timestamp + 1 days);
        eigenCoverageLiquidatable.liquidateClaim(claimId, posC);
        CoverageClaim memory afterSecond = eigenCoverageProvider.claim(claimId);
        assertEq(afterSecond.positionId, posC, "Should now point to position C");
        assertGt(afterSecond.createdAt, firstCreatedAt, "createdAt should be updated again");
    }

    /// @notice Test 19: Liquidation succeeds when new position expiry exactly matches claim end
    function test_liquidateClaim_atExactExpiry() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);
        eigenCoverageLiquidatable.setCoverageThreshold(bytes32(uint256(uint160(address(operator)))), 9500);

        uint256 oldPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);

        // Issue a claim with 30 days duration
        uint256 maxCoverage = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );
        uint256 claimAmount = (maxCoverage * 9100) / 10000;
        uint256 reward = (claimAmount * 100 * 30 days) / (10000 * 365 days);
        if (reward < 1e6) reward = 1e6;
        deal(coverageAgent.asset(), address(coverageAgent), reward * 2);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), reward);
        uint256 claimId = eigenCoverageProvider.issueClaim(oldPositionId, claimAmount, 30 days, reward);
        vm.stopPrank();

        CoverageClaim memory claimData = eigenCoverageProvider.claim(claimId);
        uint256 claimEnd = claimData.createdAt + claimData.duration;

        // Create new position with expiry EXACTLY at the claim's end time
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: claimEnd,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 exactExpiryPositionId = eigenCoverageProvider.createPosition(data, "");

        // Should succeed (claim.createdAt + duration <= newPosition.expiryTimestamp, i.e. claimEnd <= claimEnd)
        eigenCoverageLiquidatable.liquidateClaim(claimId, exactExpiryPositionId);

        CoverageClaim memory claimAfter = eigenCoverageProvider.claim(claimId);
        assertEq(claimAfter.positionId, exactExpiryPositionId);
    }

    /// @notice Test 20: Liquidation succeeds at the exact moment the claim ends (boundary: > not >=)
    function test_liquidateClaim_atExactClaimEnd() public {
        (, uint256 newPositionId, uint256 claimId) = _setupLiquidatableScenario(1000e18, 9100, Refundable.None);

        CoverageClaim memory claimData = eigenCoverageProvider.claim(claimId);
        uint256 expiresAt = claimData.createdAt + claimData.duration;

        // Warp to exactly the claim expiry (block.timestamp == createdAt + duration)
        // The check is: block.timestamp > createdAt + duration, so == should NOT revert
        vm.warp(expiresAt);

        eigenCoverageLiquidatable.liquidateClaim(claimId, newPositionId);

        CoverageClaim memory claimAfter = eigenCoverageProvider.claim(claimId);
        assertEq(claimAfter.positionId, newPositionId);
    }

    // --- Fuzz Tests ---

    /// @notice Test 21: Fuzz varying claim amounts for liquidation
    function testFuzz_liquidateClaim_varyingClaimAmounts(uint256 claimAmountBps) public {
        // Bound to 9001-9499 to be above liquidation threshold (9000) but below coverage threshold (9500)
        claimAmountBps = bound(claimAmountBps, 9001, 9499);

        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);
        eigenCoverageLiquidatable.setCoverageThreshold(bytes32(uint256(uint160(address(operator)))), 9500);

        uint256 oldPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);
        uint256 newPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);

        uint256 maxCoverage = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );
        uint256 claimAmount = (maxCoverage * claimAmountBps) / 10000;
        uint256 reward = (claimAmount * 100 * 30 days) / (10000 * 365 days);
        if (reward < 1e6) reward = 1e6;
        deal(coverageAgent.asset(), address(coverageAgent), reward * 2);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), reward);
        uint256 claimId = eigenCoverageProvider.issueClaim(oldPositionId, claimAmount, 30 days, reward);
        vm.stopPrank();

        eigenCoverageLiquidatable.liquidateClaim(claimId, newPositionId);

        CoverageClaim memory claimAfter = eigenCoverageProvider.claim(claimId);
        assertEq(claimAfter.positionId, newPositionId, "Claim should point to new position");
        assertEq(claimAfter.createdAt, block.timestamp, "createdAt should be reset");
    }

    /// @notice Test 22: Fuzz varying durations for liquidation
    function testFuzz_liquidateClaim_varyingDurations(uint256 duration) public {
        // Bound duration to 1 second to 30 days (maxDuration)
        duration = bound(duration, 1, 30 days);

        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);
        eigenCoverageLiquidatable.setCoverageThreshold(bytes32(uint256(uint160(address(operator)))), 9500);

        uint256 oldPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);
        uint256 newPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);

        uint256 maxCoverage = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );
        uint256 claimAmount = (maxCoverage * 9100) / 10000;
        uint256 reward = (claimAmount * 100 * duration) / (10000 * 365 days);
        if (reward < 1e6) reward = 1e6;
        deal(coverageAgent.asset(), address(coverageAgent), reward * 2);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), reward);
        uint256 claimId = eigenCoverageProvider.issueClaim(oldPositionId, claimAmount, duration, reward);
        vm.stopPrank();

        eigenCoverageLiquidatable.liquidateClaim(claimId, newPositionId);

        CoverageClaim memory claimAfter = eigenCoverageProvider.claim(claimId);
        assertEq(claimAfter.positionId, newPositionId);
        assertEq(claimAfter.duration, duration, "Duration should not change");
    }

    /// @notice Test 23: Fuzz varying timing within claim duration for reward capture
    function testFuzz_liquidateClaim_varyingTimingWithinDuration(uint256 timeOffset) public {
        (, uint256 newPositionId, uint256 claimId) = _setupLiquidatableScenario(1000e18, 9100, Refundable.TimeWeighted);

        CoverageClaim memory claimData = eigenCoverageProvider.claim(claimId);
        // Bound timeOffset to stay within the claim duration
        timeOffset = bound(timeOffset, 0, claimData.duration - 1);

        if (timeOffset > 0) {
            vm.warp(block.timestamp + timeOffset);
        }

        eigenCoverageLiquidatable.liquidateClaim(claimId, newPositionId);

        CoverageClaim memory claimAfter = eigenCoverageProvider.claim(claimId);
        assertEq(claimAfter.positionId, newPositionId);
    }

    /// @notice Test 24: Fuzz varying old and new position stake combos
    function testFuzz_liquidateClaim_varyingOldAndNewPositionCombos(
        uint256 oldStakeBps,
        uint256 newStakeBps,
        uint256 claimAmountBps
    ) public {
        // Bound stake amounts (as bps of 1000e18 base)
        oldStakeBps = bound(oldStakeBps, 100, 10000); // 1%-100% of 1000e18
        newStakeBps = bound(newStakeBps, 100, 10000);
        claimAmountBps = bound(claimAmountBps, 9001, 9499);

        uint256 oldStake = (1000e18 * oldStakeBps) / 10000;
        uint256 newStake = (1000e18 * newStakeBps) / 10000;

        // Set up first operator with old stake
        _setupwithAllocations();
        deal(rETH, staker, oldStake);
        _stakeAndDelegateToOperator(oldStake);
        eigenCoverageLiquidatable.setCoverageThreshold(bytes32(uint256(uint160(address(operator)))), 9500);

        uint256 oldPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);

        uint256 maxCoverage = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );
        uint256 claimAmount = (maxCoverage * claimAmountBps) / 10000;
        uint256 reward = (claimAmount * 100 * 30 days) / (10000 * 365 days);
        if (reward < 1e6) reward = 1e6;
        deal(coverageAgent.asset(), address(coverageAgent), reward * 2);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), reward);
        uint256 claimId = eigenCoverageProvider.issueClaim(oldPositionId, claimAmount, 30 days, reward);
        vm.stopPrank();

        // Set up second operator with new stake
        _setupSecondOperatorWithAllocations(newStake);
        eigenCoverageLiquidatable.setCoverageThreshold(bytes32(uint256(uint160(address(operator2)))), 9500);
        uint256 newPositionId = _createPositionForOperator(operator2, Refundable.None, 365 days);

        uint256 newMaxCoverage = eigenServiceManager.coverageAllocated(
            address(operator2), address(_getTestStrategy()), address(coverageAgent)
        );

        // The new operator's _checkCoverageForAgent passes only if:
        //   coveragePercentage <= coverageThreshold (9500) AND backing >= 0
        // coveragePercentage = (claimAmount * 10000) / newMaxCoverage
        // So we need: claimAmount * 10000 <= newMaxCoverage * 9500 (and newMaxCoverage > 0)
        bool hasEnoughCoverage = newMaxCoverage > 0 && claimAmount * 10000 <= newMaxCoverage * 9500;

        if (hasEnoughCoverage) {
            // New operator has enough coverage — should succeed
            eigenCoverageLiquidatable.liquidateClaim(claimId, newPositionId);
            assertEq(eigenCoverageProvider.claim(claimId).positionId, newPositionId);
        } else {
            // New operator doesn't have enough coverage — should revert
            vm.expectRevert();
            eigenCoverageLiquidatable.liquidateClaim(claimId, newPositionId);
        }
    }

    /// @notice Test 25: Fuzz varying new position expiry relative to claim end
    function testFuzz_liquidateClaim_varyingNewPositionExpiry(uint256 newExpiryOffset) public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);
        eigenCoverageLiquidatable.setCoverageThreshold(bytes32(uint256(uint160(address(operator)))), 9500);

        uint256 oldPositionId = _createPositionForOperator(operator, Refundable.None, 365 days);

        uint256 maxCoverage = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );
        uint256 claimAmount = (maxCoverage * 9100) / 10000;
        uint256 reward = (claimAmount * 100 * 30 days) / (10000 * 365 days);
        if (reward < 1e6) reward = 1e6;
        deal(coverageAgent.asset(), address(coverageAgent), reward * 2);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), reward);
        uint256 claimId = eigenCoverageProvider.issueClaim(oldPositionId, claimAmount, 30 days, reward);
        vm.stopPrank();

        CoverageClaim memory claimData = eigenCoverageProvider.claim(claimId);
        uint256 claimEnd = claimData.createdAt + claimData.duration;

        // Bound expiry offset: 1 second to 365 days from now
        newExpiryOffset = bound(newExpiryOffset, 1, 365 days);
        uint256 newExpiry = block.timestamp + newExpiryOffset;

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: newExpiry,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 newPositionId = eigenCoverageProvider.createPosition(data, "");

        if (claimEnd <= newExpiry) {
            // New position expiry accommodates the claim — should succeed
            eigenCoverageLiquidatable.liquidateClaim(claimId, newPositionId);
            assertEq(eigenCoverageProvider.claim(claimId).positionId, newPositionId);
        } else {
            // New position expires before the claim ends — should revert
            vm.expectRevert(
                abi.encodeWithSelector(ICoverageProvider.DurationExceedsExpiry.selector, claimEnd, newExpiry)
            );
            eigenCoverageLiquidatable.liquidateClaim(claimId, newPositionId);
        }
    }

    // ============ captureRewards ============

    function test_captureRewards_refundableNone() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        uint256 amount;
        uint32 duration;
        uint32 distributionStartTime;

        (amount, duration,) = eigenCoverageProvider.captureRewards(claimId);
        assertEq(amount, 0);
        assertEq(duration, 0);

        vm.warp(block.timestamp + 1);
        (amount, duration, distributionStartTime) = eigenCoverageProvider.captureRewards(claimId);
        assertEq(amount, 10e6, "Full reward should be capturable immediately for None policy");

        vm.warp(block.timestamp + 40 days);
        (amount,,) = eigenCoverageProvider.captureRewards(claimId);
        assertEq(amount, 0, "No remaining reward to capture");
    }

    function test_captureRewards_refundableTimeWeighted() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.TimeWeighted,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        uint256 amount;
        uint32 duration;
        uint32 distributionStartTime;

        (amount, duration,) = eigenCoverageProvider.captureRewards(claimId);
        assertEq(amount, 0);
        assertEq(duration, 0);

        vm.warp(block.timestamp + 15 days);
        (amount, duration, distributionStartTime) = eigenCoverageProvider.captureRewards(claimId);
        assertEq(amount, 5e6);
        assertEq(duration, 15 days);
        assertEq(distributionStartTime, toRewardsInterval(block.timestamp - 15 days));

        vm.warp(block.timestamp + 25 days);
        (amount, duration, distributionStartTime) = eigenCoverageProvider.captureRewards(claimId);
        assertEq(amount, 5e6);
        assertEq(duration, 15 days);
        assertEq(distributionStartTime, toRewardsInterval(block.timestamp - 25 days));
    }

    function test_captureRewards_refundableFull_notCompleted() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.Full,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 15 days);

        (uint256 amount, uint32 duration, uint32 distributionStartTime) = eigenCoverageProvider.captureRewards(claimId);
        assertEq(amount, 0, "Amount should be 0 for Full refundable when not Completed");
        assertEq(duration, 0, "Duration should be 0 for Full refundable when not Completed");
        assertEq(distributionStartTime, 0, "Distribution start time should be 0 for Full refundable when not Completed");
    }

    function test_captureRewards_refundableFull_completed() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.Full,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);
        eigenCoverageProvider.closeClaim(claimId);

        CoverageClaim memory _claim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(_claim.status), uint8(CoverageClaimStatus.Completed), "Claim should be Completed after close");

        (uint256 amount,,) = eigenCoverageProvider.captureRewards(claimId);
        assertEq(amount, 10e6, "Amount should equal full reward for Full refundable when Completed");
    }

    function test_captureRewards_refundableFull_afterEarlyClose() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        uint256 reward = 10e6;

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.Full,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), reward);
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, reward);
        vm.stopPrank();

        vm.warp(block.timestamp + 15 days);
        vm.prank(address(coverageAgent));
        eigenCoverageProvider.closeClaim(claimId);

        CoverageClaim memory _claim = eigenCoverageProvider.claim(claimId);
        assertEq(_claim.reward, reward / 2, "Reward should be reduced by refund amount");
        assertEq(uint8(_claim.status), uint8(CoverageClaimStatus.Completed));

        (uint256 amount,,) = eigenCoverageProvider.captureRewards(claimId);
        assertEq(amount, reward / 2, "captureRewards should distribute remaining reward after early close");
    }

    function test_captureRewards_zeroElapsedDuration() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.TimeWeighted,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        (uint256 amount, uint32 duration, uint32 distributionStartTime) = eigenCoverageProvider.captureRewards(claimId);
        assertEq(amount, 0, "Amount should be 0 when elapsed duration is 0");
        assertEq(duration, 0, "Duration should be 0 when elapsed duration is 0");
        assertEq(distributionStartTime, uint32(block.timestamp), "Should return the claim creation timestamp");
    }

    function test_captureRewards_timeWeighted_multipleCaptures() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.TimeWeighted,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        uint256 totalCaptured;

        vm.warp(block.timestamp + 10 days);
        (uint256 amount1,,) = eigenCoverageProvider.captureRewards(claimId);
        totalCaptured += amount1;
        assertApproxEqAbs(amount1, 3333333, 1, "First capture should be ~1/3 of reward");

        vm.warp(block.timestamp + 10 days);
        (uint256 amount2,,) = eigenCoverageProvider.captureRewards(claimId);
        totalCaptured += amount2;
        assertApproxEqAbs(amount2, 3333333, 1, "Second capture should be ~1/3 of reward");

        vm.warp(block.timestamp + 10 days);
        (uint256 amount3,,) = eigenCoverageProvider.captureRewards(claimId);
        totalCaptured += amount3;

        assertEq(totalCaptured, 10e6, "Total captured should equal full reward");
    }

    function test_captureRewards_refundableNone_fullCaptureImmediate() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 15 days);
        (uint256 amount,,) = eigenCoverageProvider.captureRewards(claimId);
        assertEq(amount, 10e6, "Should capture full reward regardless of elapsed time for None policy");

        (uint256 amountAgain, uint32 durationAgain,) = eigenCoverageProvider.captureRewards(claimId);
        assertEq(amountAgain, 0, "Second capture in same block should return 0");
        assertEq(durationAgain, 0, "Duration should be 0 for second capture in same block");
    }
}

