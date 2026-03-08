// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {EigenHelper} from "../../utils/EigenHelper.sol";
import {IEigenServiceManager} from "../../src/providers/eigenlayer/interfaces/IEigenServiceManager.sol";
import {OperatorSet} from "eigenlayer-contracts/libraries/OperatorSetLib.sol";
import {IAllocationManager, IAllocationManagerTypes} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";
import {ISignatureUtilsMixinTypes} from "eigenlayer-contracts/interfaces/ISignatureUtilsMixin.sol";
import {IERC20} from "@openzeppelin-v5/contracts/token/ERC20/IERC20.sol";
import {ICoverageProvider, CoveragePosition, Refundable} from "../../src/interfaces/ICoverageProvider.sol";

/// @notice Minimal WETH interface for wrapping ETH on-chain (used on Anvil so broadcast txs see the balance).
interface IWETH {
    function deposit() external payable;
}

uint256 constant STAKE_AMOUNT_WETH = 0.2 ether;
uint256 constant POSITION_EXPIRY_ONE_MONTH = 30 days;
uint256 constant MAX_RESERVATION_TIME = 7 days;

/// @title SetupEigenOperator
/// @notice Registers the wallet with EigenCoverageProvider, stakes 0.2 WETH in the WETH strategy,
///         delegates to self, registers for the coverage agent's operator set, allocates to the
///         coverage agent, and creates a position against ExampleCoverageAgent with reservations
///         allowed and 1 month expiry.
/// @dev Coverage agent is read from config/deployments.json (ExampleCoverageAgent) for the current chain,
///      or from env COVERAGE_AGENT. Run DeployTestnet first to populate config.
contract SetupEigenOperator is Script, EigenHelper, StdCheats {
    string constant DEPLOYMENTS_PATH = "config/deployments.json";
    string constant EIGEN_COVERAGE_DIAMOND = "EigenCoverageDiamond";
    string constant EXAMPLE_COVERAGE_AGENT = "ExampleCoverageAgent";

    function run() public {
        console.log("[1/9] Loading addresses...");
        address operator = msg.sender;
        address coverageAgent = _getCoverageAgentAddress();
        address eigenCoverageDiamond = _getEigenCoverageDiamondAddress();
        IStrategy wethStrategy = _getWethStrategy();
        address weth = address(wethStrategy.underlyingToken());
        console.log("      Operator (wallet):", operator);
        console.log("      Coverage agent:", coverageAgent);
        console.log("      EigenCoverageDiamond:", eigenCoverageDiamond);
        console.log("      WETH strategy:", address(wethStrategy));
        console.log("      WETH:", weth);

        vm.startBroadcast();

        console.log("[2/9] Ensuring operator is registered with DelegationManager...");
        IDelegationManager delegationManager = _getDelegationManager();
        if (!delegationManager.isOperator(operator)) {
            string memory metadataURI =
                vm.envOr("OPERATOR_METADATA_URI", string("https://coverage.example.com/operator.json"));
            delegationManager.registerAsOperator(address(0), 0, metadataURI);
            console.log("      Registered as operator.");
        } else {
            console.log("      Already registered as operator.");
        }

        console.log("[3/9] Ensuring 0.2 WETH balance (wrap ETH if needed)...");
        uint256 wethBalance = IERC20(weth).balanceOf(operator);
        if (wethBalance < STAKE_AMOUNT_WETH) {
            require(
                address(operator).balance >= STAKE_AMOUNT_WETH,
                "SetupEigenOperator: not enough ETH balance to wrap 0.2 WETH"
            );
            // Wrap ETH so the operator has WETH on-chain (deal() only affects simulation; broadcast needs real balance).
            IWETH(weth).deposit{value: STAKE_AMOUNT_WETH}();
            console.log("      Wrapped 0.2 ETH to WETH. Balance:", IERC20(weth).balanceOf(operator));
        } else {
            console.log("      Sufficient WETH balance.");
        }
        require(IERC20(weth).balanceOf(operator) >= STAKE_AMOUNT_WETH, "SetupEigenOperator: need 0.2 WETH");

        console.log("[4/9] Staking 0.2 WETH into WETH strategy...");
        IStrategyManager strategyManager = _getStrategyManager();
        IERC20(weth).approve(address(strategyManager), STAKE_AMOUNT_WETH);
        strategyManager.depositIntoStrategy(wethStrategy, wethStrategy.underlyingToken(), STAKE_AMOUNT_WETH);
        console.log("      Staked 0.2 WETH.");

        console.log("[5/9] Delegating to self (operator)...");
        if (delegationManager.isDelegated(operator) && delegationManager.delegatedTo(operator) == operator) {
            console.log("      Already delegated to self.");
        } else {
            ISignatureUtilsMixinTypes.SignatureWithExpiry memory emptySig =
                ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0});
            delegationManager.delegateTo(operator, emptySig, bytes32(0));
            console.log("      Delegated to self.");
        }

        console.log("[6/9] Getting operator set ID for coverage agent...");
        uint32 operatorSetId = IEigenServiceManager(eigenCoverageDiamond).getOperatorSetId(coverageAgent);
        require(operatorSetId != 0, "SetupEigenOperator: coverage agent not registered with provider");
        console.log("      Operator set ID:", operatorSetId);

        console.log("[7/9] Registering for operator set on EigenCoverageDiamond via AllocationManager...");
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = operatorSetId;
        IAllocationManager allocationManager = _getAllocationManager();
        IAllocationManagerTypes.RegisterParams memory params = IAllocationManagerTypes.RegisterParams({
            avs: eigenCoverageDiamond, operatorSetIds: operatorSetIds, data: ""
        });
        allocationManager.registerForOperatorSets(operator, params);
        console.log("      Registration complete.");

        console.log("[8/9] Allocating to coverage agent (modifyAllocations)...");
        _allocateToCoverageAgent(
            allocationManager, delegationManager, operator, eigenCoverageDiamond, operatorSetId, wethStrategy
        );

        console.log("[9/9] Creating position against ExampleCoverageAgent (reservations allowed, 1 month expiry)...");
        uint256 positionId = _createPosition(eigenCoverageDiamond, coverageAgent, operator, weth);
        console.log("      Position created. Position ID:", positionId);

        vm.stopBroadcast();

        console.log("\n=== Setup Eigen Operator Summary ===");
        console.log("Operator:", operator);
        console.log("EigenCoverageDiamond:", eigenCoverageDiamond);
        console.log("Coverage agent:", coverageAgent);
        console.log("Operator set ID:", operatorSetId);
        // console.log("Position ID:", positionId);
        console.log("====================================\n");
    }

    function _createPosition(address provider, address coverageAgent_, address operator_, address weth_)
        internal
        returns (uint256)
    {
        return ICoverageProvider(provider)
            .createPosition(
                CoveragePosition({
                    coverageAgent: coverageAgent_,
                    minRate: 100,
                    maxDuration: 30 days,
                    expiryTimestamp: block.timestamp + POSITION_EXPIRY_ONE_MONTH,
                    asset: weth_,
                    refundable: Refundable.None,
                    slashCoordinator: address(0),
                    maxReservationTime: MAX_RESERVATION_TIME,
                    operatorId: bytes32(uint256(uint160(operator_)))
                }),
                ""
            );
    }

    function _getEigenCoverageDiamondAddress() internal view returns (address) {
        address fromEnv = vm.envOr("EIGEN_COVERAGE_DIAMOND", address(0));
        if (fromEnv != address(0)) return fromEnv;

        try vm.readFile(DEPLOYMENTS_PATH) returns (string memory json) {
            string memory chainId = vm.toString(block.chainid);
            string memory path = string.concat(".", chainId, ".", EIGEN_COVERAGE_DIAMOND);
            return vm.parseJsonAddress(json, path);
        } catch {
            revert("SetupEigenOperator: set EIGEN_COVERAGE_DIAMOND or run DeployTestnet first");
        }
    }

    function _getCoverageAgentAddress() internal view returns (address) {
        address fromEnv = vm.envOr("COVERAGE_AGENT", address(0));
        if (fromEnv != address(0)) return fromEnv;

        try vm.readFile(DEPLOYMENTS_PATH) returns (string memory json) {
            string memory chainId = vm.toString(block.chainid);
            string memory path = string.concat(".", chainId, ".", EXAMPLE_COVERAGE_AGENT);
            return vm.parseJsonAddress(json, path);
        } catch {
            revert("SetupEigenOperator: set COVERAGE_AGENT or run DeployTestnet first (ExampleCoverageAgent in config)");
        }
    }

    function _allocateToCoverageAgent(
        IAllocationManager allocationManager_,
        IDelegationManager delegationManager_,
        address operator_,
        address eigenCoverageDiamond_,
        uint32 operatorSetId_,
        IStrategy wethStrategy_
    ) internal {
        uint256 operatorShares = _getOperatorShares(delegationManager_, operator_, wethStrategy_);
        require(operatorShares > 0, "SetupEigenOperator: no WETH strategy shares to allocate");
        uint64 magnitude = operatorShares > type(uint64).max ? type(uint64).max : uint64(operatorShares);
        OperatorSet memory operatorSet = OperatorSet({avs: eigenCoverageDiamond_, id: operatorSetId_});
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = wethStrategy_;
        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = magnitude;
        IAllocationManagerTypes.AllocateParams[] memory allocations = new IAllocationManagerTypes.AllocateParams[](1);
        allocations[0] = IAllocationManagerTypes.AllocateParams({
            operatorSet: operatorSet, strategies: strategies, newMagnitudes: magnitudes
        });
        allocationManager_.modifyAllocations(operator_, allocations);
        console.log("      Allocated magnitude (WETH strategy shares):", magnitude);
    }

    function _getOperatorShares(IDelegationManager delegationManager_, address operator_, IStrategy strategy_)
        internal
        view
        returns (uint256)
    {
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy_;
        uint256[] memory shares = delegationManager_.getOperatorShares(operator_, strategies);
        return shares[0];
    }
}
