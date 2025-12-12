// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestDeployer} from "test/utils/TestDeployer.sol";
import {CoverageAgent} from "src/CoverageAgent.sol";
import {NotCoverageAgentHandler, CoverageProviderNotActive} from "src/Errors.sol";
import {ICoverageAgent, CoverageProviderData} from "src/interfaces/ICoverageAgent.sol";
import {
    ICoverageProvider,
    CoveragePosition,
    CoverageClaim,
    CoverageClaimStatus,
    Refundable
} from "src/interfaces/ICoverageProvider.sol";
import {
    AssetPriceOracleAndSwapper,
    IPriceOracle,
    SwapEngine,
    SwapParams,
    UniswapV4PoolInfo
} from "src/mixins/AssetPriceOracleAndSwapper.sol";
import {UniswapHelper, UniswapAddressbook} from "utils/UniswapHelper.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Mock Price Oracle for testing
contract MockPriceOracle is IPriceOracle {
    function name() external pure returns (string memory) {
        return "MockPriceOracle";
    }

    function getQuote(uint256 amountIn, address, address) external pure returns (uint256) {
        return amountIn;
    }

    function getQuotes(uint256 amountIn, address, address)
        external
        pure
        returns (uint256 bidOutAmount, uint256 askOutAmount)
    {
        return (amountIn, amountIn);
    }
}

/// @notice Mock Coverage Provider for testing
contract MockCoverageProvider is ICoverageProvider {
    bool public isRegistered;
    uint256 public nextPositionId;
    uint256 public nextClaimId;
    mapping(uint256 => CoveragePosition) private _positions;
    mapping(uint256 => CoverageClaim) private _claims;
    mapping(address => uint256) private _totalCoverageByAgent;

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
            _claims[claimIds[i]].status = CoverageClaimStatus.Slashed;
            slashStatuses[i] = CoverageClaimStatus.Slashed;
            emit Slashed(claimIds[i], amounts[i]);
        }
    }

    function totalCoverageByAgent(address coverageAgent) external view override returns (uint256 amount) {
        return _totalCoverageByAgent[coverageAgent];
    }

    function position(uint256 positionId) external view override returns (CoveragePosition memory) {
        return _positions[positionId];
    }

    function claim(uint256 claimId) external view override returns (CoverageClaim memory) {
        return _claims[claimId];
    }
}

/// @notice Extended CoverageAgent with AssetPriceOracleAndSwapper functionality
contract CoverageAgentWithSwapper is CoverageAgent, AssetPriceOracleAndSwapper {
    constructor(address _handler, address _coverageAsset, address universalRouter, address permit2)
        CoverageAgent(_handler, _coverageAsset)
        AssetPriceOracleAndSwapper()
    {
        // Initialize the swapper functionality
        __AssetPriceOracleAndSwapper_init(universalRouter, permit2);
    }
}

/// @notice Test suite for CoverageAgent
contract CoverageAgentTest is TestDeployer, UniswapHelper {
    CoverageAgentWithSwapper public coverageAgent;
    MockCoverageProvider public mockProvider;
    MockPriceOracle public mockPriceOracle;

    address public handler;
    address public nonHandler;

    function setUp() public override {
        super.setUp();

        handler = address(this);
        nonHandler = address(0x123);

        UniswapAddressbook memory uniswapAddressBook = _getUniswapAddressBook();

        // Deploy coverage agent with swapper functionality
        coverageAgent = new CoverageAgentWithSwapper(
            handler,
            USDC,
            uniswapAddressBook.uniswapAddresses.universalRouter,
            uniswapAddressBook.uniswapAddresses.permit2
        );

        // Deploy mock provider and price oracle
        mockProvider = new MockCoverageProvider();
        mockPriceOracle = new MockPriceOracle();

        // Setup price oracle and swap params
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(USDC),
            currency1: Currency.wrap(USDT),
            fee: 100,
            tickSpacing: 1,
            hooks: IHooks(address(0))
        });

        UniswapV4PoolInfo memory uniswapV4PoolInfo = UniswapV4PoolInfo({poolKey: poolKey, zeroForOne: true});

        SwapParams memory swapParams =
            SwapParams({swapEngine: SwapEngine.UNISWAP_V4_SINGLE_HOP, poolInfo: abi.encode(uniswapV4PoolInfo)});

        coverageAgent.registerPriceAdaptor(address(mockPriceOracle), USDC, USDT, swapParams);
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
        vm.expectRevert(NotCoverageAgentHandler.selector);
        coverageAgent.registerCoverageProvider(address(0x999));
    }

    function test_RevertWhen_constructor_zeroHandler() public {
        UniswapAddressbook memory uniswapAddressBook = _getUniswapAddressBook();

        vm.expectRevert(NotCoverageAgentHandler.selector);
        new CoverageAgentWithSwapper(
            address(0),
            USDC,
            uniswapAddressBook.uniswapAddresses.universalRouter,
            uniswapAddressBook.uniswapAddresses.permit2
        );
    }

    /// ============ Coverage Provider Registration Tests ============

    function test_registerCoverageProvider() public {
        vm.expectEmit(true, false, false, false);
        emit ICoverageAgent.CoverageProviderRegistered(address(mockProvider));

        coverageAgent.registerCoverageProvider(address(mockProvider));

        // Verify provider is registered
        CoverageProviderData memory data = coverageAgent.coverageProviderData(address(mockProvider));
        assertEq(data.active, true);

        // Verify provider was notified
        assertTrue(mockProvider.isRegistered());

        // Verify provider is in the list
        address[] memory providers = coverageAgent.registeredCoverageProviders();
        assertEq(providers.length, 1);
        assertEq(providers[0], address(mockProvider));
    }

    function test_RevertWhen_registerCoverageProvider_notHandler() public {
        vm.prank(nonHandler);
        vm.expectRevert(NotCoverageAgentHandler.selector);
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

    /// ============ Coverage Provider Data Tests ============

    function test_coverageProviderData_inactive() public view {
        CoverageProviderData memory data = coverageAgent.coverageProviderData(address(0x999));
        assertEq(data.active, false);
    }

    function test_coverageProviderData_active() public {
        coverageAgent.registerCoverageProvider(address(mockProvider));

        CoverageProviderData memory data = coverageAgent.coverageProviderData(address(mockProvider));
        assertEq(data.active, true);
    }

    /// ============ AssetPriceOracleAndSwapper Tests ============

    function test_assetPriceOracleRegistered() public view {
        assertEq(coverageAgent.assetPair(USDC, USDT).priceOracle, address(mockPriceOracle));
    }

    function test_quote() public view {
        uint256 amountIn = 1000e6;
        uint256 quote = coverageAgent.quote(amountIn, USDC, USDT);
        assertEq(quote, amountIn);
    }

    function test_quote_reverseDirection() public view {
        uint256 amountIn = 1000e6;
        uint256 quote = coverageAgent.quote(amountIn, USDT, USDC);
        assertEq(quote, amountIn);
    }

    function test_swap_uniswapV4() public {
        uint128 amountOut = 1000e6;
        deal(USDC, address(coverageAgent), amountOut * 2);

        coverageAgent.swap(amountOut, USDC, USDT);

        assertEq(IERC20(USDT).balanceOf(address(coverageAgent)), amountOut);
    }

    function test_swap_uniswapV3() public {
        uint128 amountOut = 1000e6;
        deal(USDC, address(coverageAgent), amountOut * 2);

        // Setup V3 pool
        bytes memory poolInfo = abi.encodePacked(
            USDT, // 20 bytes - output token first for exact output
            uint24(100), // 3 bytes - 0.01% fee for stablecoin pairs
            USDC // 20 bytes - input token last for exact output
        );

        SwapParams memory swapParams = SwapParams({swapEngine: SwapEngine.UNISWAP_V3, poolInfo: poolInfo});
        coverageAgent.registerPriceAdaptor(address(mockPriceOracle), USDC, USDT, swapParams);

        coverageAgent.swap(amountOut, USDC, USDT);

        assertEq(IERC20(USDT).balanceOf(address(coverageAgent)), amountOut);
    }

    function test_RevertWhen_swap_assetPairNotRegistered() public {
        uint128 amountOut = 1000e6;
        deal(USDC, address(coverageAgent), amountOut * 2);

        vm.expectRevert(AssetPriceOracleAndSwapper.AssetPairNotRegistered.selector);
        coverageAgent.swap(amountOut, USDC, address(0x999));
    }

    function test_RevertWhen_quote_assetPairNotRegistered() public {
        uint256 amountIn = 1000e6;
        vm.expectRevert(AssetPriceOracleAndSwapper.AssetPairNotRegistered.selector);
        coverageAgent.quote(amountIn, USDC, address(0x999));
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
}

