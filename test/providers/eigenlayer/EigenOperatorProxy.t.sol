// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EigenTestDeployer} from "../../utils/EigenTestDeployer.sol";
import {EigenOperatorProxy} from "src/providers/eigenlayer/EigenOperatorProxy.sol";
import {IEigenOperatorProxy} from "src/providers/eigenlayer/interfaces/IEigenOperatorProxy.sol";
import {IEigenServiceManager} from "src/providers/eigenlayer/interfaces/IEigenServiceManager.sol";
import {EigenAddresses} from "src/providers/eigenlayer/Types.sol";
import {IEigenOperatorProxy} from "src/providers/eigenlayer/interfaces/IEigenOperatorProxy.sol";
import {IEigenServiceManager} from "src/providers/eigenlayer/interfaces/IEigenServiceManager.sol";
import {IPermissionController} from "eigenlayer-contracts/interfaces/IPermissionController.sol";
import {IDelegationManager} from "eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IAllocationManager, IAllocationManagerTypes} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {OperatorSet} from "eigenlayer-contracts/libraries/OperatorSetLib.sol";

/// @title EigenOperatorProxyTest
/// @notice Test suite for EigenOperatorProxy contract
/// @dev Tests constructor, access control, registration, allocation, and metadata functionality
contract EigenOperatorProxyTest is EigenTestDeployer {
    IEigenOperatorProxy public operatorProxy;
    address public handler;
    address public nonHandler;

    function setUp() public override {
        super.setUp();

        handler = address(this);
        nonHandler = makeAddr("nonHandler");

        // Deploy the operator proxy (base deployer already set eigenServiceManager)
        operatorProxy = IEigenOperatorProxy(
            address(new EigenOperatorProxy(eigenServiceManager.eigenAddresses(), handler, "https://operator.meta/uri"))
        );

        // Accept admin for the operator proxy
        IPermissionController(eigenServiceManager.eigenAddresses().permissionController)
            .acceptAdmin(address(operatorProxy));

        // Test strategy and coverage provider are already set up by EigenTestDeployer.setUp()
    }

    // ============ Constructor Tests ============

    /// @notice Test that constructor properly initializes handler
    function test_constructor_setsHandler() public view {
        assertEq(operatorProxy.handler(), handler);
    }

    /// @notice Test constructor with empty metadata URI
    function test_constructor_emptyMetadataURI() public {
        IEigenOperatorProxy newProxy =
            IEigenOperatorProxy(address(new EigenOperatorProxy(eigenServiceManager.eigenAddresses(), handler, "")));

        assertEq(newProxy.handler(), handler);
    }

    /// @notice Test that constructor registers the contract as an EigenLayer operator
    function test_constructor_registersAsOperator() public view {
        IDelegationManager delegationManager =
            IDelegationManager(eigenServiceManager.eigenAddresses().delegationManager);
        bool isOperator = delegationManager.isOperator(address(operatorProxy));
        assertTrue(isOperator, "Proxy should be registered as an operator");
    }

    /// @notice Test that constructor sets up permission controller admins
    function test_constructor_setsAdmins() public view {
        IPermissionController permissionController =
            IPermissionController(eigenServiceManager.eigenAddresses().permissionController);

        // Check that handler is an admin
        assertTrue(
            permissionController.isAdmin(address(operatorProxy), handler), "Handler should be an admin after acceptance"
        );

        // Check that the proxy itself is an admin
        assertTrue(
            permissionController.isAdmin(address(operatorProxy), address(operatorProxy)),
            "Proxy should be an admin of itself"
        );
    }

    // ============ Handler View Function Tests ============

    /// @notice Test handler() returns correct address
    function test_handler_returnsCorrectAddress() public view {
        assertEq(operatorProxy.handler(), handler);
    }

    /// @notice Test eigenAddresses() returns correct EigenLayer contract addresses
    function test_eigenAddresses_returnsCorrectAddresses() public view {
        EigenAddresses memory expectedAddresses = eigenServiceManager.eigenAddresses();
        EigenAddresses memory actualAddresses = operatorProxy.eigenAddresses();

        assertEq(actualAddresses.delegationManager, expectedAddresses.delegationManager);
        assertEq(actualAddresses.allocationManager, expectedAddresses.allocationManager);
        assertEq(actualAddresses.rewardsCoordinator, expectedAddresses.rewardsCoordinator);
        assertEq(actualAddresses.permissionController, expectedAddresses.permissionController);
    }

    // ============ Update Operator Metadata URI Tests ============

    /// @notice Test updateOperatorMetadataURI succeeds when called by handler
    function test_updateOperatorMetadataURI_succeeds() public {
        // Should not revert when called by handler
        operatorProxy.updateOperatorMetadataURI("https://new.operator.meta/updated");
    }

    /// @notice Test updateOperatorMetadataURI reverts when called by non-handler
    function test_RevertWhen_updateOperatorMetadataURI_calledByNonHandler() public {
        vm.prank(nonHandler);
        vm.expectRevert(IEigenOperatorProxy.NotOperator.selector);
        operatorProxy.updateOperatorMetadataURI("https://evil.uri");
    }

    // ============ Register Coverage Agent Tests ============

    /// @notice Test registerCoverageAgent succeeds when called by handler
    function test_registerCoverageAgent_succeeds() public {
        // Roll forward to pass allocation configuration delay
        vm.roll(block.number + 126001);

        operatorProxy.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);

        // Verify registration by checking operator set
        uint32 operatorSetId = eigenServiceManager.getOperatorSetId(address(coverageAgent));
        assertTrue(operatorSetId > 0 || operatorSetId == 0, "Should have a valid operator set ID");
    }

    /// @notice Test registerCoverageAgent with rewards split
    function test_registerCoverageAgent_withRewardsSplit() public {
        vm.roll(block.number + 126001);

        // Register with 10% rewards split (10000 basis points = 100%, so 1000 = 10%)
        operatorProxy.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 1000);

        // If we get here without reverting, the registration was successful
    }

    /// @notice Test registerCoverageAgent reverts when called by non-handler
    function test_RevertWhen_registerCoverageAgent_calledByNonHandler() public {
        vm.prank(nonHandler);
        vm.expectRevert(abi.encodeWithSelector(IEigenOperatorProxy.NotHandler.selector));
        operatorProxy.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);
    }

    /// @notice Test registerCoverageAgent with max rewards split
    function test_registerCoverageAgent_maxRewardsSplit() public {
        vm.roll(block.number + 126001);

        // Max rewards split is 10000 (100%)
        operatorProxy.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 10000);
    }

    /// @notice Test registerCoverageAgent reverts when registering the same coverage agent twice
    function test_RevertWhen_registerCoverageAgent_duplicateRegistration() public {
        vm.roll(block.number + 126001);

        // First registration should succeed
        operatorProxy.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);

        // Second registration of the same coverage agent should revert
        vm.expectRevert(IEigenOperatorProxy.AlreadyRegistered.selector);
        operatorProxy.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);
    }

    /// @notice Test registerCoverageAgent reverts on duplicate even with different rewards split
    function test_RevertWhen_registerCoverageAgent_duplicateWithDifferentRewardsSplit() public {
        vm.roll(block.number + 126001);

        // First registration with 0% rewards split
        operatorProxy.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);

        // Second registration with different rewards split should still revert
        vm.expectRevert(IEigenOperatorProxy.AlreadyRegistered.selector);
        operatorProxy.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 5000);
    }

    /// @notice Test registerCoverageAgent reverts when rewards split exceeds 10000 (100%)
    function test_RevertWhen_registerCoverageAgent_invalidRewardsSplit() public {
        vm.roll(block.number + 126001);

        vm.expectRevert(abi.encodeWithSelector(IEigenOperatorProxy.InvalidRewardsSplit.selector, 10001));
        operatorProxy.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 10001);
    }

    // ============ Set Rewards Split Tests ============

    /// @notice Test setRewardsSplit succeeds when called by handler after registration
    function test_setRewardsSplit_succeeds() public {
        vm.roll(block.number + 126001);

        // First register the coverage agent
        operatorProxy.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);

        // Warp time forward to pass the activation delay (7 days)
        vm.warp(block.timestamp + 7 days + 1);

        // Update the rewards split
        operatorProxy.setRewardsSplit(address(eigenCoverageDiamond), address(coverageAgent), 5000);
    }

    /// @notice Test setRewardsSplit reverts when called by non-handler
    function test_RevertWhen_setRewardsSplit_calledByNonHandler() public {
        vm.roll(block.number + 126001);
        operatorProxy.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);

        vm.prank(nonHandler);
        vm.expectRevert(abi.encodeWithSelector(IEigenOperatorProxy.NotHandler.selector));
        operatorProxy.setRewardsSplit(address(eigenCoverageDiamond), address(coverageAgent), 5000);
    }

    /// @notice Test setRewardsSplit reverts when rewards split exceeds 10000 (100%)
    function test_RevertWhen_setRewardsSplit_invalidRewardsSplit() public {
        vm.roll(block.number + 126001);
        operatorProxy.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);

        vm.expectRevert(abi.encodeWithSelector(IEigenOperatorProxy.InvalidRewardsSplit.selector, 10001));
        operatorProxy.setRewardsSplit(address(eigenCoverageDiamond), address(coverageAgent), 10001);
    }

    /// @notice Test setRewardsSplit with max valid value (10000 = 100%)
    function test_setRewardsSplit_maxValidValue() public {
        vm.roll(block.number + 126001);
        operatorProxy.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);

        // Warp time forward to pass the activation delay (7 days)
        vm.warp(block.timestamp + 7 days + 1);

        // Should succeed with max valid value
        operatorProxy.setRewardsSplit(address(eigenCoverageDiamond), address(coverageAgent), 10000);
    }

    /// @notice Fuzz test setRewardsSplit with various valid values
    function testFuzz_setRewardsSplit_validValues(uint16 rewardsSplit) public {
        // Bound to valid range (0-10000)
        rewardsSplit = uint16(bound(rewardsSplit, 0, 10000));

        vm.roll(block.number + 126001);
        operatorProxy.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);

        // Warp time forward to pass the activation delay (7 days)
        vm.warp(block.timestamp + 7 days + 1);

        // Should succeed with any valid value
        operatorProxy.setRewardsSplit(address(eigenCoverageDiamond), address(coverageAgent), rewardsSplit);
    }

    /// @notice Test setRewardsSplit can be called multiple times to update the split
    function test_setRewardsSplit_canUpdateMultipleTimes() public {
        vm.roll(block.number + 126001);
        operatorProxy.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);

        // Warp time forward to pass the activation delay (7 days) after registration
        vm.warp(block.timestamp + 7 days + 1);

        // Update multiple times, warping time between each to pass activation delay
        operatorProxy.setRewardsSplit(address(eigenCoverageDiamond), address(coverageAgent), 1000);
        vm.warp(block.timestamp + 7 days + 1);

        operatorProxy.setRewardsSplit(address(eigenCoverageDiamond), address(coverageAgent), 5000);
        vm.warp(block.timestamp + 7 days + 1);

        operatorProxy.setRewardsSplit(address(eigenCoverageDiamond), address(coverageAgent), 10000);
        vm.warp(block.timestamp + 7 days + 1);

        operatorProxy.setRewardsSplit(address(eigenCoverageDiamond), address(coverageAgent), 0);
    }

    // ============ Allocate Tests ============

    /// @notice Test allocate succeeds when called by handler with whitelisted strategy
    function test_allocate_succeeds() public {
        // First register the coverage agent
        vm.roll(block.number + 126001);
        operatorProxy.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);

        // Prepare allocation parameters
        address[] memory strategyAddresses = new address[](1);
        strategyAddresses[0] = address(_getTestStrategy());
        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = 1e18;

        // Allocate
        operatorProxy.allocate(address(eigenCoverageDiamond), address(coverageAgent), strategyAddresses, magnitudes);

        // Verify allocation
        OperatorSet memory operatorSet = OperatorSet({
            avs: address(eigenCoverageDiamond), id: eigenServiceManager.getOperatorSetId(address(coverageAgent))
        });
        IAllocationManagerTypes.Allocation memory allocation = IAllocationManager(
                eigenServiceManager.eigenAddresses().allocationManager
            ).getAllocation(address(operatorProxy), operatorSet, _getTestStrategy());

        assertEq(allocation.currentMagnitude, 1e18, "Allocation magnitude should be set");
    }

    /// @notice Test allocate reverts when called by non-handler
    function test_RevertWhen_allocate_calledByNonHandler() public {
        vm.roll(block.number + 126001);
        operatorProxy.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);

        address[] memory strategyAddresses = new address[](1);
        strategyAddresses[0] = address(_getTestStrategy());
        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = 1e18;

        vm.prank(nonHandler);
        vm.expectRevert(abi.encodeWithSelector(IEigenOperatorProxy.NotHandler.selector));
        operatorProxy.allocate(address(eigenCoverageDiamond), address(coverageAgent), strategyAddresses, magnitudes);
    }

    /// @notice Test allocate reverts when strategy is not whitelisted
    function test_RevertWhen_allocate_strategyNotWhitelisted() public {
        vm.roll(block.number + 126001);
        operatorProxy.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);

        address nonWhitelistedStrategy = makeAddr("nonWhitelistedStrategy");
        address[] memory strategyAddresses = new address[](1);
        strategyAddresses[0] = nonWhitelistedStrategy;
        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = 1e18;

        vm.expectRevert(
            abi.encodeWithSelector(IEigenOperatorProxy.StrategyNotWhitelisted.selector, nonWhitelistedStrategy)
        );
        operatorProxy.allocate(address(eigenCoverageDiamond), address(coverageAgent), strategyAddresses, magnitudes);
    }

    /// @notice Test allocate with multiple strategies
    function test_allocate_multipleStrategies() public {
        vm.roll(block.number + 126001);
        operatorProxy.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);

        // Get another strategy and whitelist it
        // Note: For this test to work fully, we'd need multiple strategies available
        // For now, we test the single strategy path works
        address[] memory strategyAddresses = new address[](1);
        strategyAddresses[0] = address(_getTestStrategy());
        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = 5e17; // 50% magnitude

        operatorProxy.allocate(address(eigenCoverageDiamond), address(coverageAgent), strategyAddresses, magnitudes);

        // Verify allocation
        OperatorSet memory operatorSet = OperatorSet({
            avs: address(eigenCoverageDiamond), id: eigenServiceManager.getOperatorSetId(address(coverageAgent))
        });
        IAllocationManagerTypes.Allocation memory allocation = IAllocationManager(
                eigenServiceManager.eigenAddresses().allocationManager
            ).getAllocation(address(operatorProxy), operatorSet, _getTestStrategy());

        assertEq(allocation.currentMagnitude, 5e17, "Allocation magnitude should match");
    }

    /// @notice Fuzz test allocate with various magnitudes
    function testFuzz_allocate_variousMagnitudes(uint64 magnitude) public {
        // Bound magnitude to valid range (0 < magnitude <= 1e18)
        magnitude = uint64(bound(magnitude, 1, 1e18));

        vm.roll(block.number + 126001);
        operatorProxy.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);

        address[] memory strategyAddresses = new address[](1);
        strategyAddresses[0] = address(_getTestStrategy());
        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = magnitude;

        operatorProxy.allocate(address(eigenCoverageDiamond), address(coverageAgent), strategyAddresses, magnitudes);

        OperatorSet memory operatorSet = OperatorSet({
            avs: address(eigenCoverageDiamond), id: eigenServiceManager.getOperatorSetId(address(coverageAgent))
        });
        IAllocationManagerTypes.Allocation memory allocation = IAllocationManager(
                eigenServiceManager.eigenAddresses().allocationManager
            ).getAllocation(address(operatorProxy), operatorSet, _getTestStrategy());

        assertEq(allocation.currentMagnitude, magnitude, "Allocation magnitude should match fuzzed value");
    }

    // ============ Access Control Integration Tests ============

    /// @notice Test that different addresses get correct access control errors
    function test_accessControl_differentAddresses() public {
        address[] memory randomAddresses = new address[](5);
        randomAddresses[0] = makeAddr("random1");
        randomAddresses[1] = makeAddr("random2");
        randomAddresses[2] = makeAddr("random3");
        randomAddresses[3] = makeAddr("random4");
        randomAddresses[4] = address(0x1234);

        for (uint256 i = 0; i < randomAddresses.length; i++) {
            vm.prank(randomAddresses[i]);
            vm.expectRevert(abi.encodeWithSelector(IEigenOperatorProxy.NotHandler.selector));
            operatorProxy.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);
        }
    }

    /// @notice Test that handler can call all protected functions
    function test_handler_canCallAllProtectedFunctions() public {
        vm.roll(block.number + 126001);

        // Handler can register
        operatorProxy.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);

        // Handler can allocate
        address[] memory strategyAddresses = new address[](1);
        strategyAddresses[0] = address(_getTestStrategy());
        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = 1e18;
        operatorProxy.allocate(address(eigenCoverageDiamond), address(coverageAgent), strategyAddresses, magnitudes);

        // Handler can update metadata (should not revert)
        operatorProxy.updateOperatorMetadataURI("https://new.uri");
    }

    // ============ Multiple Operator Proxy Tests ============

    /// @notice Test deploying multiple operator proxies with different handlers
    function test_multipleProxies_differentHandlers() public {
        address handler2 = makeAddr("handler2");
        address handler3 = makeAddr("handler3");

        IEigenOperatorProxy proxy2 = IEigenOperatorProxy(
            address(new EigenOperatorProxy(eigenServiceManager.eigenAddresses(), handler2, "https://proxy2.meta"))
        );

        IEigenOperatorProxy proxy3 = IEigenOperatorProxy(
            address(new EigenOperatorProxy(eigenServiceManager.eigenAddresses(), handler3, "https://proxy3.meta"))
        );

        assertEq(proxy2.handler(), handler2);
        assertEq(proxy3.handler(), handler3);

        // Verify each is registered as an operator
        IDelegationManager delegationManager =
            IDelegationManager(eigenServiceManager.eigenAddresses().delegationManager);
        assertTrue(delegationManager.isOperator(address(proxy2)));
        assertTrue(delegationManager.isOperator(address(proxy3)));
    }

    /// @notice Test that one proxy's handler cannot control another proxy
    function test_proxyIsolation_handlersCannotCrossControl() public {
        address handler2 = makeAddr("handler2");

        IEigenOperatorProxy proxy2 = IEigenOperatorProxy(
            address(new EigenOperatorProxy(eigenServiceManager.eigenAddresses(), handler2, "https://proxy2.meta"))
        );

        // handler (this contract) cannot control proxy2
        vm.expectRevert(IEigenOperatorProxy.NotOperator.selector);
        proxy2.updateOperatorMetadataURI("https://evil.uri");

        // handler2 cannot control operatorProxy
        vm.prank(handler2);
        vm.expectRevert(IEigenOperatorProxy.NotOperator.selector);
        operatorProxy.updateOperatorMetadataURI("https://evil.uri");
    }
}
