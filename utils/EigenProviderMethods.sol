// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BeaconProxy} from "@openzeppelin-v5/contracts/proxy/beacon/BeaconProxy.sol";
import {EigenAddresses} from "src/providers/eigenlayer/Types.sol";
import {EigenOperatorProxy} from "src/providers/eigenlayer/EigenOperatorProxy.sol";


library EigenProviderMethods {

    function createOperatorProxy(
        address eigenOperatorInstance_,
        EigenAddresses memory eigenAddresses_,
        address handler_,
        string calldata operatorMetadata_
    )
        external
        returns (address operator)
    {
        // Best practice initialize on deployment
        bytes memory initdata = abi.encodeWithSelector(
            EigenOperatorProxy.initialize.selector,
            eigenAddresses_,
            handler_,
            operatorMetadata_
        );
        operator = address(new BeaconProxy(eigenOperatorInstance_, initdata));
    }

}