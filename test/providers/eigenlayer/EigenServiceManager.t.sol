// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EigenTestDeployer} from "../../utils/EigenTestDeployer.sol";
import {EigenAddresses} from "src/providers/eigenlayer/Types.sol";
import {CoveragePosition, CoverageClaim, CoverageClaimStatus, Refundable} from "src/interfaces/ICoverageProvider.sol";
import {IEigenServiceManager} from "src/providers/eigenlayer/interfaces/IEigenServiceManager.sol";
import {
    IAllocationManager,
    IAllocationManagerTypes,
    IAllocationManagerEvents
} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {OperatorSet} from "eigenlayer-contracts/libraries/OperatorSetLib.sol";
import {MockStrategy} from "../../utils/mocks/MockStrategy.sol";

contract EigenServiceManagerTest is EigenTestDeployer {
    // ============ Registration and allocation ============

    function test_registerCoverageAgent() public {
        operator.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 10000);
    }

    function test_allocate() public {
        _setupwithAllocations();
        OperatorSet memory operatorSet = OperatorSet({
            avs: address(eigenCoverageDiamond), id: eigenServiceManager.getOperatorSetId(address(coverageAgent))
        });
        IAllocationManagerTypes.Allocation memory allocation = IAllocationManager(
                eigenServiceManager.eigenAddresses().allocationManager
            ).getAllocation(address(operator), operatorSet, _getTestStrategy());
        assertEq(allocation.currentMagnitude, 1e18);
    }

    function test_getAllocationedStrategies() public {
        _setupwithAllocations();

        address[] memory strategies =
            eigenServiceManager.getAllocationedStrategies(address(operator), address(coverageAgent));
        assertEq(strategies.length, 1);
        assertEq(strategies[0], address(_getTestStrategy()));
    }

    // ============ Strategy whitelist ============

    function test_whitelistedStrategies() public view {
        address[] memory strategies = eigenServiceManager.whitelistedStrategies();
        assertEq(strategies.length, 1);
        assertEq(strategies[0], address(_getTestStrategy()));
        assertTrue(eigenServiceManager.isStrategyWhitelisted(address(_getTestStrategy())));
    }

    function test_whitelistedStrategies_afterRemoval() public {
        eigenServiceManager.setStrategyWhitelist(address(_getTestStrategy()), false);

        address[] memory strategies = eigenServiceManager.whitelistedStrategies();
        assertEq(strategies.length, 0);
        assertFalse(eigenServiceManager.isStrategyWhitelisted(address(_getTestStrategy())));
    }

    function test_whitelistedStrategies_addAndRemove() public {
        address[] memory strategies = eigenServiceManager.whitelistedStrategies();
        assertEq(strategies.length, 1);

        eigenServiceManager.setStrategyWhitelist(address(_getTestStrategy()), false);
        strategies = eigenServiceManager.whitelistedStrategies();
        assertEq(strategies.length, 0);

        eigenServiceManager.setStrategyWhitelist(address(_getTestStrategy()), true);
        strategies = eigenServiceManager.whitelistedStrategies();
        assertEq(strategies.length, 1);
        assertEq(strategies[0], address(_getTestStrategy()));
    }

    function test_RevertWhen_whitelistStrategy_alreadyWhitelisted() public {
        assertTrue(eigenServiceManager.isStrategyWhitelisted(address(_getTestStrategy())));

        vm.expectRevert(
            abi.encodeWithSelector(
                IEigenServiceManager.StrategyAssetAlreadyRegistered.selector,
                address(_getTestStrategy().underlyingToken())
            )
        );
        eigenServiceManager.setStrategyWhitelist(address(_getTestStrategy()), true);
    }

    function test_RevertWhen_whitelistStrategy_sameAssetDifferentStrategy() public {
        assertTrue(eigenServiceManager.isStrategyWhitelisted(address(_getTestStrategy())));

        MockStrategy mockStrategy = new MockStrategy(address(_getTestStrategy().underlyingToken()));

        vm.expectRevert(
            abi.encodeWithSelector(
                IEigenServiceManager.StrategyAssetAlreadyRegistered.selector,
                address(_getTestStrategy().underlyingToken())
            )
        );
        eigenServiceManager.setStrategyWhitelist(address(mockStrategy), true);
    }

    function test_whitelistStrategy_sameAssetAfterRemoval() public {
        assertTrue(eigenServiceManager.isStrategyWhitelisted(address(_getTestStrategy())));

        MockStrategy mockStrategy = new MockStrategy(address(_getTestStrategy().underlyingToken()));

        eigenServiceManager.setStrategyWhitelist(address(_getTestStrategy()), false);
        assertFalse(eigenServiceManager.isStrategyWhitelisted(address(_getTestStrategy())));

        eigenServiceManager.setStrategyWhitelist(address(mockStrategy), true);
        assertTrue(eigenServiceManager.isStrategyWhitelisted(address(mockStrategy)));

        address[] memory strategies = eigenServiceManager.whitelistedStrategies();
        assertEq(strategies.length, 1);
        assertEq(strategies[0], address(mockStrategy));
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

        (amount, duration,) = eigenServiceManager.captureRewards(claimId);
        assertEq(amount, 0);
        assertEq(duration, 0);

        vm.warp(block.timestamp + 1);
        (amount, duration, distributionStartTime) = eigenServiceManager.captureRewards(claimId);
        assertEq(amount, 10e6, "Full reward should be capturable immediately for None policy");

        vm.warp(block.timestamp + 40 days);
        (amount,,) = eigenServiceManager.captureRewards(claimId);
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

        (amount, duration,) = eigenServiceManager.captureRewards(claimId);
        assertEq(amount, 0);
        assertEq(duration, 0);

        vm.warp(block.timestamp + 15 days);
        (amount, duration, distributionStartTime) = eigenServiceManager.captureRewards(claimId);
        assertEq(amount, 5e6);
        assertEq(duration, 15 days);
        assertEq(distributionStartTime, toRewardsInterval(block.timestamp - 15 days));

        vm.warp(block.timestamp + 25 days);
        (amount, duration, distributionStartTime) = eigenServiceManager.captureRewards(claimId);
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

        (uint256 amount, uint32 duration, uint32 distributionStartTime) = eigenServiceManager.captureRewards(claimId);
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

        (uint256 amount,,) = eigenServiceManager.captureRewards(claimId);
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

        (uint256 amount,,) = eigenServiceManager.captureRewards(claimId);
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

        (uint256 amount, uint32 duration, uint32 distributionStartTime) = eigenServiceManager.captureRewards(claimId);
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
        (uint256 amount1,,) = eigenServiceManager.captureRewards(claimId);
        totalCaptured += amount1;
        assertApproxEqAbs(amount1, 3333333, 1, "First capture should be ~1/3 of reward");

        vm.warp(block.timestamp + 10 days);
        (uint256 amount2,,) = eigenServiceManager.captureRewards(claimId);
        totalCaptured += amount2;
        assertApproxEqAbs(amount2, 3333333, 1, "Second capture should be ~1/3 of reward");

        vm.warp(block.timestamp + 10 days);
        (uint256 amount3,,) = eigenServiceManager.captureRewards(claimId);
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
        (uint256 amount,,) = eigenServiceManager.captureRewards(claimId);
        assertEq(amount, 10e6, "Should capture full reward regardless of elapsed time for None policy");

        (uint256 amountAgain, uint32 durationAgain,) = eigenServiceManager.captureRewards(claimId);
        assertEq(amountAgain, 0, "Second capture in same block should return 0");
        assertEq(durationAgain, 0, "Duration should be 0 for second capture in same block");
    }

    // ============ updateAVSMetadataURI ============

    function test_updateAVSMetadataURI() public {
        string memory newMetadataURI = "https://new-coverage.example.com/metadata.json";

        vm.expectEmit(true, false, false, true, eigenServiceManager.eigenAddresses().allocationManager);
        emit IAllocationManagerEvents.AVSMetadataURIUpdated(address(eigenCoverageDiamond), newMetadataURI);

        eigenServiceManager.updateAVSMetadataURI(newMetadataURI);
    }

    function test_updateAVSMetadataURI_multipleTimes() public {
        string memory uri1 = "https://first-uri.example.com/metadata.json";
        string memory uri2 = "https://second-uri.example.com/metadata.json";

        vm.expectEmit(true, false, false, true, eigenServiceManager.eigenAddresses().allocationManager);
        emit IAllocationManagerEvents.AVSMetadataURIUpdated(address(eigenCoverageDiamond), uri1);
        eigenServiceManager.updateAVSMetadataURI(uri1);

        vm.expectEmit(true, false, false, true, eigenServiceManager.eigenAddresses().allocationManager);
        emit IAllocationManagerEvents.AVSMetadataURIUpdated(address(eigenCoverageDiamond), uri2);
        eigenServiceManager.updateAVSMetadataURI(uri2);
    }

    function test_updateAVSMetadataURI_emptyString() public {
        string memory emptyURI = "";

        vm.expectEmit(true, false, false, true, eigenServiceManager.eigenAddresses().allocationManager);
        emit IAllocationManagerEvents.AVSMetadataURIUpdated(address(eigenCoverageDiamond), emptyURI);

        eigenServiceManager.updateAVSMetadataURI(emptyURI);
    }

    // ============ registerOperator ============

    function test_registerOperator_succeeds() public {
        uint32[] memory operatorSetIds = new uint32[](0);
        eigenServiceManager.registerOperator(address(this), address(eigenCoverageDiamond), operatorSetIds, "");
    }

    // ============ ensureAllocations ============

    function test_RevertWhen_ensureAllocations_notAllocated() public {
        vm.roll(block.number + 126001);
        operator.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEigenServiceManager.NotAllocated.selector,
                address(operator),
                address(_getTestStrategy()),
                address(coverageAgent)
            )
        );
        eigenServiceManager.ensureAllocations(address(operator), address(coverageAgent), address(_getTestStrategy()));
    }

    function test_ensureAllocations_succeeds() public {
        _setupwithAllocations();

        eigenServiceManager.ensureAllocations(address(operator), address(coverageAgent), address(_getTestStrategy()));
    }

    function test_ensureAllocations_addsStrategyToSet() public {
        _setupwithAllocations();

        MockStrategy newStrategy = new MockStrategy(WETH);
        eigenServiceManager.setStrategyWhitelist(address(newStrategy), true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEigenServiceManager.NotAllocated.selector,
                address(operator),
                address(newStrategy),
                address(coverageAgent)
            )
        );
        eigenServiceManager.ensureAllocations(address(operator), address(coverageAgent), address(newStrategy));
    }

    // ============ setSwapSlippage (AssetPriceOracle facet) ============

    function test_setSwapSlippage() public {
        uint16 slippageBps = 50; // 0.5%
        eigenPriceOracle.setSwapSlippage(slippageBps);
        assertEq(eigenPriceOracle.swapSlippage(), slippageBps);
    }

    // ============ View functions ============

    function test_coverageAllocated_returnsCorrectValue() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(10e18);

        uint256 allocated = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );
        assertGt(allocated, 0, "Coverage allocated should be greater than 0 after staking and allocation");
    }

    function test_getOperatorSetId_afterRegistration() public {
        _setupwithAllocations();

        uint32 operatorSetId = eigenServiceManager.getOperatorSetId(address(coverageAgent));
        assertGt(operatorSetId, 0, "Operator set ID should be greater than 0");
    }

    function test_getOperatorSetId_unregistered() public {
        address unregistered = makeAddr("unregistered");
        uint32 operatorSetId = eigenServiceManager.getOperatorSetId(unregistered);
        assertEq(operatorSetId, 0, "Operator set ID should be 0 for unregistered agent");
    }

    function test_eigenAddresses_returnsValidAddresses() public view {
        EigenAddresses memory addrs = eigenServiceManager.eigenAddresses();
        assertTrue(addrs.allocationManager != address(0), "Allocation manager should not be zero");
        assertTrue(addrs.delegationManager != address(0), "Delegation manager should not be zero");
        assertTrue(addrs.strategyManager != address(0), "Strategy manager should not be zero");
        assertTrue(addrs.rewardsCoordinator != address(0), "Rewards coordinator should not be zero");
        assertTrue(addrs.permissionController != address(0), "Permission controller should not be zero");
    }

    function test_isStrategyWhitelisted_nonWhitelisted() public {
        address randomStrategy = makeAddr("randomStrategy");
        assertFalse(
            eigenServiceManager.isStrategyWhitelisted(randomStrategy), "Non-whitelisted strategy should return false"
        );
    }
}
