// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDiamondCut} from "../interfaces/IDiamondCut.sol";
import {IDiamond} from "../interfaces/IDiamond.sol";

/// @title LibDiamond
/// @author EIP-2535 Diamonds
/// @notice Library for diamond storage and diamond cut operations
/// @dev See https://eips.ethereum.org/EIPS/eip-2535
library LibDiamond {
    /// @notice Storage position for diamond storage (EIP-2535 standard)
    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

    /// @notice Diamond storage structure
    /// @dev Uses the diamond storage pattern to avoid storage collisions
    struct DiamondStorage {
        /// @notice Maps function selector to the facet address and
        ///         the position of the selector in the facetFunctionSelectors.selectors array
        mapping(bytes4 => FacetAddressAndPosition) selectorToFacetAndPosition;
        /// @notice Maps facet addresses to function selectors
        mapping(address => FacetFunctionSelectors) facetFunctionSelectors;
        /// @notice Array of facet addresses
        address[] facetAddresses;
        /// @notice Used to query if a contract implements an interface (ERC-165)
        mapping(bytes4 => bool) supportedInterfaces;
        /// @notice Owner of the contract
        address contractOwner;
    }

    /// @notice Facet address and position in selectors array
    struct FacetAddressAndPosition {
        address facetAddress;
        uint96 functionSelectorPosition; // position in facetFunctionSelectors.functionSelectors array
    }

    /// @notice Function selectors for a facet
    struct FacetFunctionSelectors {
        bytes4[] functionSelectors;
        uint256 facetAddressPosition; // position in facetAddresses array
    }

    /// @notice Emitted when ownership is transferred
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Emitted when facets are modified
    /// @dev This event is part of the EIP-2535 standard and enables transparency.
    ///      It records all functions that are added, replaced, or removed on a diamond.
    ///      This allows tracking the complete history of diamond upgrades.
    event DiamondCut(IDiamond.FacetCut[] _diamondCut, address _init, bytes _calldata);

    /// @notice Error when caller is not the owner
    error NotContractOwner(address _user, address _contractOwner);

    /// @notice Error when adding a function that already exists
    error CannotAddFunctionToDiamondThatAlreadyExists(bytes4 _selector);

    /// @notice Error when replacing a function with the same function
    error CannotReplaceFunctionWithTheSameFunctionFromTheSameFacet(bytes4 _selector);

    /// @notice Error when replacing a function that doesn't exist
    error CannotReplaceFunctionThatDoesNotExist(bytes4 _selector);

    /// @notice Error when removing a function that doesn't exist
    error CannotRemoveFunctionThatDoesNotExist(bytes4 _selector);

    /// @notice Error when removing an immutable function
    error CannotRemoveImmutableFunction(bytes4 _selector);

    /// @notice Error when replacing an immutable function
    error CannotReplaceImmutableFunction(bytes4 _selector);

    /// @notice Error when facet address has no code
    error NoBytecodeAtAddress(address _contractAddress, string _message);

    /// @notice Error when facet address is zero for add action
    error CannotAddSelectorsToZeroAddress(bytes4[] _selectors);

    /// @notice Error when facet address is not zero for remove action
    error RemoveFacetAddressMustBeZeroAddress(address _facetAddress);

    /// @notice Error when no selectors in facet to cut
    error NoSelectorsProvidedForFacetForCut(address _facetAddress);

    /// @notice Error when init address is zero but calldata is not empty
    error InitializationFunctionReverted(address _initializationContractAddress, bytes _calldata);

    /// @notice Get diamond storage
    /// @return ds Diamond storage pointer
    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    /// @notice Set the contract owner
    /// @param _newOwner The address of the new owner
    function setContractOwner(address _newOwner) internal {
        DiamondStorage storage ds = diamondStorage();
        address previousOwner = ds.contractOwner;
        ds.contractOwner = _newOwner;
        emit OwnershipTransferred(previousOwner, _newOwner);
    }

    /// @notice Get the contract owner
    /// @return contractOwner_ The address of the contract owner
    function contractOwner() internal view returns (address contractOwner_) {
        contractOwner_ = diamondStorage().contractOwner;
    }

    /// @notice Enforce that the caller is the contract owner
    function enforceIsContractOwner() internal view {
        DiamondStorage storage ds = diamondStorage();
        if (msg.sender != ds.contractOwner) {
            revert NotContractOwner(msg.sender, ds.contractOwner);
        }
    }

    /// @notice Execute a diamond cut
    /// @dev As specified in EIP-2535, this function:
    ///      1. Adds, replaces, or removes functions atomically
    ///      2. Emits a DiamondCut event for transparency
    ///      3. Optionally executes an initialization function via delegatecall
    ///      This function allows arbitrary execution via delegatecall, so access must be restricted.
    /// @param _diamondCut The facet cuts to execute atomically
    /// @param _init The address to delegatecall with _calldata (can be address(0))
    /// @param _calldata The calldata for the delegatecall (can be empty if _init is address(0))
    function diamondCut(IDiamondCut.FacetCut[] memory _diamondCut, address _init, bytes memory _calldata) internal {
        for (uint256 facetIndex; facetIndex < _diamondCut.length; facetIndex++) {
            IDiamond.FacetCutAction action = _diamondCut[facetIndex].action;
            if (action == IDiamond.FacetCutAction.Add) {
                addFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);
            } else if (action == IDiamond.FacetCutAction.Replace) {
                replaceFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);
            } else if (action == IDiamond.FacetCutAction.Remove) {
                removeFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);
            }
        }
        emit DiamondCut(_diamondCut, _init, _calldata);
        initializeDiamondCut(_init, _calldata);
    }

    /// @notice Add functions to the diamond
    /// @param _facetAddress The address of the facet
    /// @param _functionSelectors The function selectors to add
    function addFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        if (_functionSelectors.length == 0) {
            revert NoSelectorsProvidedForFacetForCut(_facetAddress);
        }
        DiamondStorage storage ds = diamondStorage();
        if (_facetAddress == address(0)) {
            revert CannotAddSelectorsToZeroAddress(_functionSelectors);
        }
        uint96 selectorPosition = uint96(ds.facetFunctionSelectors[_facetAddress].functionSelectors.length);
        // add new facet address if it does not exist
        if (selectorPosition == 0) {
            addFacet(ds, _facetAddress);
        }
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            if (oldFacetAddress != address(0)) {
                revert CannotAddFunctionToDiamondThatAlreadyExists(selector);
            }
            addFunction(ds, selector, selectorPosition, _facetAddress);
            selectorPosition++;
        }
    }

    /// @notice Replace functions in the diamond
    /// @param _facetAddress The address of the facet
    /// @param _functionSelectors The function selectors to replace
    function replaceFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        if (_functionSelectors.length == 0) {
            revert NoSelectorsProvidedForFacetForCut(_facetAddress);
        }
        DiamondStorage storage ds = diamondStorage();
        if (_facetAddress == address(0)) {
            revert CannotAddSelectorsToZeroAddress(_functionSelectors);
        }
        uint96 selectorPosition = uint96(ds.facetFunctionSelectors[_facetAddress].functionSelectors.length);
        // add new facet address if it does not exist
        if (selectorPosition == 0) {
            addFacet(ds, _facetAddress);
        }
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            if (oldFacetAddress == address(0)) {
                revert CannotReplaceFunctionThatDoesNotExist(selector);
            }
            if (oldFacetAddress == address(this)) {
                revert CannotReplaceImmutableFunction(selector);
            }
            if (oldFacetAddress == _facetAddress) {
                revert CannotReplaceFunctionWithTheSameFunctionFromTheSameFacet(selector);
            }
            removeFunction(ds, oldFacetAddress, selector);
            addFunction(ds, selector, selectorPosition, _facetAddress);
            selectorPosition++;
        }
    }

    /// @notice Remove functions from the diamond
    /// @param _facetAddress The address of the facet (must be address(0))
    /// @param _functionSelectors The function selectors to remove
    function removeFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        if (_functionSelectors.length == 0) {
            revert NoSelectorsProvidedForFacetForCut(_facetAddress);
        }
        DiamondStorage storage ds = diamondStorage();
        if (_facetAddress != address(0)) {
            revert RemoveFacetAddressMustBeZeroAddress(_facetAddress);
        }
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            if (oldFacetAddress == address(0)) {
                revert CannotRemoveFunctionThatDoesNotExist(selector);
            }
            if (oldFacetAddress == address(this)) {
                revert CannotRemoveImmutableFunction(selector);
            }
            removeFunction(ds, oldFacetAddress, selector);
        }
    }

    /// @notice Add a facet to the diamond
    /// @param ds Diamond storage
    /// @param _facetAddress The address of the facet
    function addFacet(DiamondStorage storage ds, address _facetAddress) internal {
        enforceHasContractCode(_facetAddress, "LibDiamond: New facet has no code");
        ds.facetFunctionSelectors[_facetAddress].facetAddressPosition = ds.facetAddresses.length;
        ds.facetAddresses.push(_facetAddress);
    }

    /// @notice Add a function to the diamond
    /// @param ds Diamond storage
    /// @param _selector The function selector
    /// @param _selectorPosition The position of the selector in the facet's selectors array
    /// @param _facetAddress The address of the facet
    function addFunction(DiamondStorage storage ds, bytes4 _selector, uint96 _selectorPosition, address _facetAddress)
        internal
    {
        ds.selectorToFacetAndPosition[_selector].functionSelectorPosition = _selectorPosition;
        ds.selectorToFacetAndPosition[_selector].facetAddress = _facetAddress;
        ds.facetFunctionSelectors[_facetAddress].functionSelectors.push(_selector);
    }

    /// @notice Remove a function from the diamond
    /// @param ds Diamond storage
    /// @param _facetAddress The address of the facet
    /// @param _selector The function selector
    function removeFunction(DiamondStorage storage ds, address _facetAddress, bytes4 _selector) internal {
        // replace selector with last selector, then delete last selector
        uint256 selectorPosition = ds.selectorToFacetAndPosition[_selector].functionSelectorPosition;
        uint256 lastSelectorPosition = ds.facetFunctionSelectors[_facetAddress].functionSelectors.length - 1;
        // if not the same then replace _selector with lastSelector
        if (selectorPosition != lastSelectorPosition) {
            bytes4 lastSelector = ds.facetFunctionSelectors[_facetAddress].functionSelectors[lastSelectorPosition];
            ds.facetFunctionSelectors[_facetAddress].functionSelectors[selectorPosition] = lastSelector;
            // casting to 'uint96' is safe because selectorPosition is always less than the length of the function selectors array
            // forge-lint: disable-next-line(unsafe-typecast)
            ds.selectorToFacetAndPosition[lastSelector].functionSelectorPosition = uint96(selectorPosition);
        }
        // delete the last selector
        ds.facetFunctionSelectors[_facetAddress].functionSelectors.pop();
        delete ds.selectorToFacetAndPosition[_selector];

        // if no more selectors for facet address then delete the facet address
        if (lastSelectorPosition == 0) {
            // replace facet address with last facet address and delete last facet address
            uint256 lastFacetAddressPosition = ds.facetAddresses.length - 1;
            uint256 facetAddressPosition = ds.facetFunctionSelectors[_facetAddress].facetAddressPosition;
            if (facetAddressPosition != lastFacetAddressPosition) {
                address lastFacetAddress = ds.facetAddresses[lastFacetAddressPosition];
                ds.facetAddresses[facetAddressPosition] = lastFacetAddress;
                ds.facetFunctionSelectors[lastFacetAddress].facetAddressPosition = facetAddressPosition;
            }
            ds.facetAddresses.pop();
            delete ds.facetFunctionSelectors[_facetAddress].facetAddressPosition;
        }
    }

    /// @notice Initialize the diamond cut
    /// @param _init The address to delegatecall
    /// @param _calldata The calldata for the delegatecall
    function initializeDiamondCut(address _init, bytes memory _calldata) internal {
        if (_init == address(0)) {
            return;
        }
        enforceHasContractCode(_init, "LibDiamond: _init address has no code");
        (bool success, bytes memory error) = _init.delegatecall(_calldata);
        if (!success) {
            if (error.length > 0) {
                // bubble up error
                assembly {
                    let returndata_size := mload(error)
                    revert(add(32, error), returndata_size)
                }
            } else {
                revert InitializationFunctionReverted(_init, _calldata);
            }
        }
    }

    /// @notice Enforce that an address has contract code
    /// @param _contract The address to check
    /// @param _errorMessage The error message if no code
    function enforceHasContractCode(address _contract, string memory _errorMessage) internal view {
        uint256 contractSize;
        assembly {
            contractSize := extcodesize(_contract)
        }
        if (contractSize == 0) {
            revert NoBytecodeAtAddress(_contract, _errorMessage);
        }
    }
}

