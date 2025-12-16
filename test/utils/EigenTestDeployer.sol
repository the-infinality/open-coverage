// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestDeployer} from "./TestDeployer.sol";
import {EigenAddresses} from "src/providers/eigenlayer/Types.sol";
import {EigenCoverageProvider} from "src/providers/eigenlayer/EigenCoverageProvider.sol";
import {EigenHelper, EigenAddressbook} from "../../utils/EigenHelper.sol";
import {CoverageAgent} from "src/CoverageAgent.sol";
import {ERC1967Proxy} from "@openzeppelin-v5/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UpgradeableBeacon} from "@openzeppelin-v5/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {UniswapHelper, UniswapAddressbook} from "../../utils/UniswapHelper.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";

import {EigenOperatorProxy} from "src/providers/eigenlayer/EigenOperatorProxy.sol";

contract EigenTestDeployer is TestDeployer, EigenHelper, UniswapHelper {
    address public eigenOperatorInstance;
    uint32 public CALCULATION_INTERVAL_SECONDS;
    uint32 public MAX_REWARDS_DURATION;

    // *** Deployed Contracts *** //
    CoverageAgent coverageAgent;
    EigenCoverageProvider eigenCoverageProvider;

    function setUp() public virtual override {
        super.setUp();

        EigenAddressbook memory eigenAddressBook = _getAddressBook();
        UniswapAddressbook memory uniswapAddressBook = _getUniswapAddressBook();

        IRewardsCoordinator rewardsCoordinator = _getRewardsCoordinator();
        CALCULATION_INTERVAL_SECONDS = rewardsCoordinator.CALCULATION_INTERVAL_SECONDS();
        MAX_REWARDS_DURATION = rewardsCoordinator.MAX_REWARDS_DURATION();

        // Deploy EigenCoverageProvider via proxy
        EigenCoverageProvider implementation = new EigenCoverageProvider();
        bytes memory initData = abi.encodeWithSelector(
            EigenCoverageProvider.initialize.selector,
            owner,
            EigenAddresses({
                allocationManager: eigenAddressBook.eigenAddresses.allocationManager,
                delegationManager: eigenAddressBook.eigenAddresses.delegationManager,
                strategyManager: eigenAddressBook.eigenAddresses.strategyManager,
                rewardsCoordinator: eigenAddressBook.eigenAddresses.rewardsCoordinator,
                permissionController: eigenAddressBook.eigenAddresses.permissionController
            }),
            "",
            uniswapAddressBook.uniswapAddresses.universalRouter,
            uniswapAddressBook.uniswapAddresses.permit2
        );
        eigenCoverageProvider = EigenCoverageProvider(address(new ERC1967Proxy(address(implementation), initData)));

        // Deploy coverage agent and allow this address to be the operator
        coverageAgent = new CoverageAgent(address(this), USDC);

        // Deploy a instance for the upgradeable beacon proxies
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(new EigenOperatorProxy()), address(this));
        eigenOperatorInstance = address(beacon);
    }

    function toRewardsInterval(uint256 timestamp) public view returns (uint32) {
        return uint32(timestamp / CALCULATION_INTERVAL_SECONDS * CALCULATION_INTERVAL_SECONDS);
    }
}
