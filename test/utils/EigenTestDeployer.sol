// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestDeployer} from "./TestDeployer.sol";
import {EigenAddresses} from "../../src/providers/eigenlayer/Types.sol";
import {EigenCoverageDiamond} from "../../src/providers/eigenlayer/EigenCoverageDiamond.sol";
import {EigenServiceManagerFacet} from "../../src/providers/eigenlayer/facets/EigenServiceManagerFacet.sol";
import {EigenCoverageProviderFacet} from "../../src/providers/eigenlayer/facets/EigenCoverageProviderFacet.sol";
import {AssetPriceOracleAndSwapperFacet} from "../../src/facets/AssetPriceOracleAndSwapperFacet.sol";
import {DiamondCutFacet} from "../../src/diamond/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../../src/diamond/facets/DiamondLoupeFacet.sol";
import {IDiamondCut} from "../../src/diamond/interfaces/IDiamondCut.sol";
import {EigenHelper, EigenAddressbook} from "../../utils/EigenHelper.sol";
import {ExampleCoverageAgent} from "../../src/ExampleCoverageAgent.sol";
import {UniswapHelper, UniswapAddressbook} from "../../utils/UniswapHelper.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IStrategyManager} from "eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {ISignatureUtilsMixinTypes} from "eigenlayer-contracts/interfaces/ISignatureUtilsMixin.sol";
import {IPermissionController} from "eigenlayer-contracts/interfaces/IPermissionController.sol";
import {DiamondFacetsDeployer} from "../../utils/deployments/DiamondFacetsDeployer.sol";
import {EigenFacetsDeployer} from "../../utils/deployments/EigenFacetsDeployer.sol";
import {
    AssetPriceOracleAndSwapperFacetDeployer
} from "../../utils/deployments/AssetPriceOracleAndSwapperFacetDeployer.sol";
import {OwnershipFacet} from "../../src/diamond/facets/OwnershipFacet.sol";
import {IEigenOperatorProxy} from "../../src/providers/eigenlayer/interfaces/IEigenOperatorProxy.sol";
import {EigenOperatorProxy} from "../../src/providers/eigenlayer/EigenOperatorProxy.sol";
import {IEigenServiceManager} from "../../src/providers/eigenlayer/interfaces/IEigenServiceManager.sol";
import {ICoverageProvider} from "../../src/interfaces/ICoverageProvider.sol";
import {ICoverageLiquidatable} from "../../src/interfaces/ICoverageLiquidatable.sol";
import {IAssetPriceOracleAndSwapper} from "../../src/interfaces/IAssetPriceOracleAndSwapper.sol";
import {ISwapperEngine} from "../../src/interfaces/ISwapperEngine.sol";
import {CoveragePosition, CoverageClaimStatus, Refundable} from "../../src/interfaces/ICoverageProvider.sol";
import {PriceStrategy, AssetPair} from "../../src/interfaces/IAssetPriceOracleAndSwapper.sol";
import {MockPriceOracle} from "./MockPriceOracle.sol";
import {UniswapV3SwapperEngine} from "../../src/swapper-engines/UniswapV3SwapperEngine.sol";

contract EigenTestDeployer is TestDeployer, EigenHelper, UniswapHelper {
    address public eigenOperatorInstance;
    uint32 public CALCULATION_INTERVAL_SECONDS;
    uint32 public MAX_REWARDS_DURATION;

    // *** Deployed Contracts *** //
    ExampleCoverageAgent coverageAgent;
    EigenCoverageDiamond eigenCoverageDiamond;

    // Facets
    DiamondCutFacet diamondCutFacet;
    DiamondLoupeFacet diamondLoupeFacet;
    OwnershipFacet ownershipFacet;
    EigenServiceManagerFacet eigenServiceManagerFacet;
    EigenCoverageProviderFacet eigenCoverageProviderFacet;
    AssetPriceOracleAndSwapperFacet assetPriceOracleAndSwapperFacet;

    // *** Test state (shared by eigenlayer test contracts) *** //
    IEigenOperatorProxy public operator;
    MockPriceOracle public mockPriceOracle;
    address public staker;
    IEigenServiceManager eigenServiceManager;
    ICoverageProvider eigenCoverageProvider;
    ICoverageLiquidatable eigenCoverageLiquidatable;
    IAssetPriceOracleAndSwapper eigenPriceOracle;
    ISwapperEngine public uniswapV3SwapperEngine;

    function setUp() public virtual override {
        super.setUp();

        EigenAddressbook memory eigenAddressBook = _getAddressBook();
        UniswapAddressbook memory uniswapAddressBook = _getUniswapAddressBook();

        IRewardsCoordinator rewardsCoordinator = _getRewardsCoordinator();
        CALCULATION_INTERVAL_SECONDS = rewardsCoordinator.CALCULATION_INTERVAL_SECONDS();
        MAX_REWARDS_DURATION = rewardsCoordinator.MAX_REWARDS_DURATION();

        // Deploy facets using deployment helper libraries
        (diamondCutFacet, diamondLoupeFacet, ownershipFacet) = DiamondFacetsDeployer.deployDiamondFacets();
        (eigenServiceManagerFacet, eigenCoverageProviderFacet) = EigenFacetsDeployer.deployEigenFacets();
        assetPriceOracleAndSwapperFacet =
            AssetPriceOracleAndSwapperFacetDeployer.deployAssetPriceOracleAndSwapperFacet();

        // Get facet cuts from deployment helper libraries
        IDiamondCut.FacetCut[] memory diamondCuts =
            DiamondFacetsDeployer.getDiamondFacetCuts(diamondCutFacet, diamondLoupeFacet, ownershipFacet);
        IDiamondCut.FacetCut[] memory eigenCuts =
            EigenFacetsDeployer.getEigenFacetCuts(eigenServiceManagerFacet, eigenCoverageProviderFacet);
        IDiamondCut.FacetCut memory assetPriceOracleAndSwapperCut =
            AssetPriceOracleAndSwapperFacetDeployer.getAssetPriceOracleAndSwapperFacetCut(
                assetPriceOracleAndSwapperFacet
            );

        // Combine all facet cuts (5 facets total)
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](6);
        cuts[0] = diamondCuts[0]; // DiamondCutFacet
        cuts[1] = diamondCuts[1]; // DiamondLoupeFacet
        cuts[2] = diamondCuts[2]; // OwnershipFacet
        cuts[3] = eigenCuts[0]; // EigenServiceManagerFacet
        cuts[4] = eigenCuts[1]; // EigenCoverageProviderFacet
        cuts[5] = assetPriceOracleAndSwapperCut; // AssetPriceOracleAndSwapperFacet

        // Deploy diamond with all facets
        EigenCoverageDiamond.DiamondArgs memory args = EigenCoverageDiamond.DiamondArgs({
            owner: owner,
            eigenAddresses: EigenAddresses({
                allocationManager: eigenAddressBook.eigenAddresses.allocationManager,
                delegationManager: eigenAddressBook.eigenAddresses.delegationManager,
                strategyManager: eigenAddressBook.eigenAddresses.strategyManager,
                rewardsCoordinator: eigenAddressBook.eigenAddresses.rewardsCoordinator,
                permissionController: eigenAddressBook.eigenAddresses.permissionController
            }),
            metadataURI: "https://coverage.example.com/metadata.json",
            universalRouter: uniswapAddressBook.uniswapAddresses.universalRouter,
            permit2: uniswapAddressBook.uniswapAddresses.permit2
        });

        eigenCoverageDiamond = new EigenCoverageDiamond(cuts, args);

        // Deploy coverage agent and allow this address to be the operator
        coverageAgent =
            new ExampleCoverageAgent(address(this), USDC, "https://coverage.example.com/agent-metadata.json");

        // Set eigenOperatorInstance to address(0) since we deploy directly now (no beacon pattern)
        eigenOperatorInstance = address(0);

        // *** Eigen test setup (operator, interfaces, oracle, staker) *** //
        eigenServiceManager = IEigenServiceManager(address(eigenCoverageDiamond));
        eigenCoverageProvider = ICoverageProvider(address(eigenCoverageDiamond));
        eigenCoverageLiquidatable = ICoverageLiquidatable(address(eigenCoverageDiamond));
        eigenPriceOracle = IAssetPriceOracleAndSwapper(address(eigenCoverageDiamond));

        operator = IEigenOperatorProxy(
            address(new EigenOperatorProxy(eigenServiceManager.eigenAddresses(), address(this), ""))
        );
        IPermissionController(eigenServiceManager.eigenAddresses().permissionController).acceptAdmin(address(operator));

        coverageAgent.registerCoverageProvider(address(eigenCoverageDiamond));
        eigenServiceManager.setStrategyWhitelist(address(_getTestStrategy()), true);

        staker = makeAddr("staker");
        deal(rETH, staker, 1000e18);

        mockPriceOracle = new MockPriceOracle(100000e18, rETH, USDC);
        uniswapV3SwapperEngine = new UniswapV3SwapperEngine(
            uniswapAddressBook.uniswapAddresses.universalRouter,
            uniswapAddressBook.uniswapAddresses.permit2,
            uniswapAddressBook.uniswapAddresses.viewQuoterV3
        );
        bytes memory poolInfo = abi.encodePacked(rETH, uint24(100), WETH, uint24(500), USDC);
        eigenPriceOracle.register(
            AssetPair({
                assetA: rETH,
                assetB: USDC,
                swapEngine: address(uniswapV3SwapperEngine),
                poolInfo: poolInfo,
                priceStrategy: PriceStrategy.SwapperOnly,
                swapperAccuracy: 0,
                priceOracle: address(0)
            })
        );
    }

    function toRewardsInterval(uint256 timestamp) public view returns (uint32) {
        // casting to 'uint32' is safe because timestamp is always less than the length of the CALCULATION_INTERVAL_SECONDS
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint32(timestamp / CALCULATION_INTERVAL_SECONDS * CALCULATION_INTERVAL_SECONDS);
    }

    // ============ Shared test helpers ============

    function _setupwithAllocations() internal {
        vm.roll(block.number + 126001);
        operator.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);
        address[] memory strategyAddresses = new address[](1);
        strategyAddresses[0] = address(_getTestStrategy());
        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = 1e18;
        operator.allocate(address(eigenCoverageDiamond), address(coverageAgent), strategyAddresses, magnitudes);
    }

    function _stakeAndDelegateToOperator(uint256 stakeAmount) internal {
        vm.startPrank(staker);
        IStrategyManager strategyManager = _getStrategyManager();
        _getTestStrategy().underlyingToken().approve(address(strategyManager), stakeAmount);
        strategyManager.depositIntoStrategy(_getTestStrategy(), _getTestStrategy().underlyingToken(), stakeAmount);
        ISignatureUtilsMixinTypes.SignatureWithExpiry memory emptySignature =
            ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0});
        _getDelegationManager().delegateTo(address(operator), emptySignature, bytes32(0));
        deal(coverageAgent.asset(), address(coverageAgent), 100e6);
        vm.stopPrank();
    }

    function _setupSlashingPosition(uint256 stakeAmount, address slashCoordinator, Refundable refundable)
        internal
        returns (uint256 positionId)
    {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(stakeAmount);
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: refundable,
            slashCoordinator: slashCoordinator,
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        positionId = eigenCoverageProvider.createPosition(data, "");
    }

    function _setupSlashingPosition(uint256 stakeAmount) internal returns (uint256 positionId) {
        return _setupSlashingPosition(stakeAmount, address(0), Refundable.None);
    }

    function _createAndApproveClaim(
        uint256 positionId,
        uint256 claimAmount,
        uint256 duration,
        uint256 reward,
        uint256 timeOffset
    ) internal returns (uint256 claimId) {
        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), reward);
        claimId = eigenCoverageProvider.issueClaim(positionId, claimAmount, duration, reward);
        if (timeOffset > 0) {
            vm.warp(block.timestamp + timeOffset);
        }
        vm.stopPrank();
        return claimId;
    }

    function _createAndApproveClaim(uint256 positionId, uint256 claimAmount, uint256 reward)
        internal
        returns (uint256 claimId)
    {
        return _createAndApproveClaim(positionId, claimAmount, 30 days, reward, 0);
    }

    function _executeSlash(uint256[] memory claimIds, uint256[] memory amounts, uint256 timeOffset)
        internal
        returns (CoverageClaimStatus[] memory statuses)
    {
        if (timeOffset > 0) {
            vm.warp(block.timestamp + timeOffset);
        }
        vm.startPrank(address(coverageAgent));
        statuses = eigenCoverageProvider.slashClaims(claimIds, amounts, block.timestamp);
        vm.stopPrank();
        return statuses;
    }

    function _executeSlash(uint256[] memory claimIds, uint256[] memory amounts)
        internal
        returns (CoverageClaimStatus[] memory statuses)
    {
        return _executeSlash(claimIds, amounts, 0);
    }

    function _prepareSingleSlash(uint256 claimId, uint256 amount)
        internal
        pure
        returns (uint256[] memory claimIds, uint256[] memory amounts)
    {
        claimIds = new uint256[](1);
        amounts = new uint256[](1);
        claimIds[0] = claimId;
        amounts[0] = amount;
    }

    function _setupPositionWithReservation(uint256 stakeAmount, uint256 maxReservationTime)
        internal
        returns (uint256 positionId)
    {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(stakeAmount);
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: maxReservationTime,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        positionId = eigenCoverageProvider.createPosition(data, "");
    }

    function _setupSlashedClaim(uint256 stakeAmount, uint256 claimAmount, uint256 slashAmount)
        internal
        returns (uint256 positionId, uint256 claimId)
    {
        positionId = _setupSlashingPosition(stakeAmount);
        claimId = _createAndApproveClaim(positionId, claimAmount, 10e6);
        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, slashAmount);
        _executeSlash(claimIds, amounts, 15 days);
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
    }

    // ============ Liquidation test helpers ============

    IEigenOperatorProxy public operator2;
    address public staker2;

    /// @dev Creates a second operator with allocations and staked delegation for cross-operator liquidation tests
    function _setupSecondOperatorWithAllocations(uint256 stakeAmount) internal {
        operator2 = IEigenOperatorProxy(
            address(new EigenOperatorProxy(eigenServiceManager.eigenAddresses(), address(this), ""))
        );
        IPermissionController(eigenServiceManager.eigenAddresses().permissionController).acceptAdmin(address(operator2));

        // Wait for the allocation delay to become effective for the new operator
        vm.roll(block.number + 126001);

        operator2.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);
        address[] memory strategyAddresses = new address[](1);
        strategyAddresses[0] = address(_getTestStrategy());
        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = 1e18;
        operator2.allocate(address(eigenCoverageDiamond), address(coverageAgent), strategyAddresses, magnitudes);

        staker2 = makeAddr("staker2");
        deal(rETH, staker2, stakeAmount);
        vm.startPrank(staker2);
        IStrategyManager strategyManager = _getStrategyManager();
        _getTestStrategy().underlyingToken().approve(address(strategyManager), stakeAmount);
        strategyManager.depositIntoStrategy(_getTestStrategy(), _getTestStrategy().underlyingToken(), stakeAmount);
        ISignatureUtilsMixinTypes.SignatureWithExpiry memory emptySignature =
            ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0});
        _getDelegationManager().delegateTo(address(operator2), emptySignature, bytes32(0));
        vm.stopPrank();
    }

    /// @dev Creates a position for a given operator with the default coverage agent and test strategy
    function _createPositionForOperator(IEigenOperatorProxy op, Refundable refundable, uint256 expiryOffset)
        internal
        returns (uint256 positionId)
    {
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + expiryOffset,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: refundable,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(op))))
        });
        positionId = eigenCoverageProvider.createPosition(data, "");
    }

    /// @dev Sets up a liquidation scenario with two positions and a claim at the specified utilization percentage
    /// @param stakeAmount The amount of rETH to stake for the operator
    /// @param claimBps The claim amount as basis points of max coverage (e.g. 9100 = 91%)
    /// @param refundable The refund policy for the positions
    /// @return oldPositionId The position ID that the claim is issued against
    /// @return newPositionId The position ID to liquidate to
    /// @return claimId The ID of the issued claim
    function _setupLiquidatableScenario(uint256 stakeAmount, uint256 claimBps, Refundable refundable)
        internal
        returns (uint256 oldPositionId, uint256 newPositionId, uint256 claimId)
    {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(stakeAmount);

        // Raise coverage threshold to allow high utilization claims
        eigenCoverageProvider.setCoverageThreshold(bytes32(uint256(uint160(address(operator)))), 9500);

        oldPositionId = _createPositionForOperator(operator, refundable, 365 days);
        newPositionId = _createPositionForOperator(operator, refundable, 365 days);

        uint256 maxCoverage = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );
        uint256 claimAmount = (maxCoverage * claimBps) / 10000;
        uint256 reward = (claimAmount * 100 * 30 days) / (10000 * 365 days);
        if (reward < 1e6) reward = 1e6;

        deal(coverageAgent.asset(), address(coverageAgent), reward * 2);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), reward);
        claimId = eigenCoverageProvider.issueClaim(oldPositionId, claimAmount, 30 days, reward);
        vm.stopPrank();
    }

    /// @dev Computes the storage slot for a field within a CoveragePosition in the positions array.
    /// @param positionIndex The index in the positions array
    /// @param fieldOffset The slot offset of the field within the CoveragePosition struct
    ///   0 = coverageAgent+minRate, 1 = maxDuration, 2 = expiryTimestamp, 3 = asset+refundable,
    ///   4 = slashCoordinator, 5 = maxReservationTime, 6 = operatorId
    function _positionStorageSlot(uint256 positionIndex, uint256 fieldOffset) internal pure returns (bytes32) {
        // positions is at storage slot 6 in EigenCoverageStorage
        // Each CoveragePosition struct occupies 7 storage slots
        uint256 arrayBase = uint256(keccak256(abi.encode(uint256(6))));
        return bytes32(arrayBase + positionIndex * 7 + fieldOffset);
    }
}
