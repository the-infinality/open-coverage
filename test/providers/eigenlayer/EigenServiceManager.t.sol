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

    // ============ setCoverageThreshold / getCoverageThreshold ============

    function test_getCoverageThreshold_defaultAfterRegistration() public {
        uint32[] memory operatorSetIds = new uint32[](0);
        eigenServiceManager.registerOperator(address(operator), address(eigenCoverageDiamond), operatorSetIds, "");

        uint16 threshold = eigenServiceManager.getCoverageThreshold(address(operator));
        assertEq(threshold, 7000, "Default coverage threshold should be 7000 (70%)");
    }

    function test_setCoverageThreshold() public {
        _setupwithAllocations();

        uint16 newThreshold = 8500;
        eigenServiceManager.setCoverageThreshold(address(operator), newThreshold);

        uint16 threshold = eigenServiceManager.getCoverageThreshold(address(operator));
        assertEq(threshold, newThreshold, "Coverage threshold should be updated to 8500");
    }

    function test_setCoverageThreshold_updatesValue() public {
        _setupwithAllocations();

        eigenServiceManager.setCoverageThreshold(address(operator), 5000);
        assertEq(eigenServiceManager.getCoverageThreshold(address(operator)), 5000);

        eigenServiceManager.setCoverageThreshold(address(operator), 9000);
        assertEq(eigenServiceManager.getCoverageThreshold(address(operator)), 9000);
    }

    function test_setCoverageThreshold_zeroValue() public {
        _setupwithAllocations();

        eigenServiceManager.setCoverageThreshold(address(operator), 0);
        assertEq(eigenServiceManager.getCoverageThreshold(address(operator)), 0, "Coverage threshold should be 0");
    }

    function test_setCoverageThreshold_maxValue() public {
        _setupwithAllocations();

        eigenServiceManager.setCoverageThreshold(address(operator), type(uint16).max);
        assertEq(
            eigenServiceManager.getCoverageThreshold(address(operator)),
            type(uint16).max,
            "Coverage threshold should be max uint16"
        );
    }

    function test_getCoverageThreshold_unregisteredOperator() public {
        address unregistered = makeAddr("unregistered");
        uint16 threshold = eigenServiceManager.getCoverageThreshold(unregistered);
        assertEq(threshold, 0, "Unregistered operator should have 0 threshold");
    }
}
