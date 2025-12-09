// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestDeployer} from "./TestDeployer.sol";
import {EigenAddresses} from "src/providers/eigenlayer/Types.sol";
import {EigenCoverageManager} from "src/providers/eigenlayer/EigenCoverageManager.sol";
import {EigenHelper, EigenAddressbook} from "../../utils/EigenHelper.sol";
import {CoveragePool} from "src/CoveragePool.sol";
import {ERC1967Proxy} from "@openzeppelin-v5/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UpgradeableBeacon} from "@openzeppelin-v5/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {EigenOperatorProxy} from "src/providers/eigenlayer/EigenOperatorProxy.sol";


contract EigenTestDeployer is TestDeployer, EigenHelper {
    address public eigenOperatorInstance;

    // *** Deployed Contracts *** //
    CoveragePool coveragePool;
    EigenCoverageManager eigenCoverageManager;


    function setUp() public override virtual {
        super.setUp();

        EigenAddressbook memory eigenAddressBook = _getAddressBook();

        // Deploy EigenCoverageManager via proxy
        EigenCoverageManager implementation = new EigenCoverageManager();
        bytes memory initData = abi.encodeWithSelector(
            EigenCoverageManager.initialize.selector,
            owner,
            EigenAddresses({
                allocationManager: eigenAddressBook.eigenAddresses.allocationManager,
                delegationManager: eigenAddressBook.eigenAddresses.delegationManager,
                strategyManager: eigenAddressBook.eigenAddresses.strategyManager,
                rewardsCoordinator: eigenAddressBook.eigenAddresses.rewardsCoordinator,
                permissionController: eigenAddressBook.eigenAddresses.permissionController
            }),
            ""
        );
        eigenCoverageManager = EigenCoverageManager(address(new ERC1967Proxy(address(implementation), initData)));

        // Deploy coverage pool and allow this address to be the operator
        coveragePool = new CoveragePool(address(this), USDC);

        // Deploy a instance for the upgradeable beacon proxies
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(new EigenOperatorProxy()), address(this));
        eigenOperatorInstance = address(beacon);
    }
}
