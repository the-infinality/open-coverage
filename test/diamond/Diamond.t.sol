// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TestDiamond} from "./TestDiamond.sol";
import {MockFacet} from "./MockFacet.sol";
import {DiamondCutFacet} from "src/diamond/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "src/diamond/facets/DiamondLoupeFacet.sol";
import {IDiamondCut} from "src/diamond/interfaces/IDiamondCut.sol";
import {IDiamond} from "src/diamond/interfaces/IDiamond.sol";
import {IDiamondLoupe} from "src/diamond/interfaces/IDiamondLoupe.sol";
import {IDiamondOwner} from "src/diamond/interfaces/IDiamondOwner.sol";
import {IERC165} from "src/diamond/interfaces/IERC165.sol";
import {LibDiamond} from "src/diamond/libraries/LibDiamond.sol";
import {Diamond} from "src/diamond/Diamond.sol";
import {DiamondFacetsDeployer} from "utils/deployments/DiamondFacetsDeployer.sol";
import {DiamondInitSuccess} from "./DiamondInit.sol";
import {DiamondInitRevertWithData} from "./DiamondInit.sol";
import {DiamondInitRevertNoData} from "./DiamondInit.sol";

contract DiamondTest is Test {
    TestDiamond diamond;
    DiamondCutFacet diamondCutFacet;
    DiamondLoupeFacet diamondLoupeFacet;
    MockFacet mockFacet;
    MockFacet mockFacetReplacement;

    address owner;
    address nonOwner;

    function setUp() public {
        owner = address(this);
        nonOwner = makeAddr("nonOwner");

        (diamondCutFacet, diamondLoupeFacet) = DiamondFacetsDeployer.deployDiamondFacets();
        mockFacet = new MockFacet();
        mockFacetReplacement = new MockFacet();

        IDiamondCut.FacetCut[] memory cuts =
            DiamondFacetsDeployer.getDiamondFacetCuts(diamondCutFacet, diamondLoupeFacet);
        diamond = new TestDiamond(cuts, owner);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function test_Deployment_setsOwner() public view {
        assertEq(IDiamondOwner(address(diamond)).owner(), owner);
    }

    function test_Deployment_hasCutAndLoupeFacets() public view {
        address[] memory addresses = IDiamondLoupe(address(diamond)).facetAddresses();
        assertEq(addresses.length, 2);
        assertTrue(
            addresses[0] == address(diamondCutFacet) || addresses[1] == address(diamondCutFacet)
        );
        assertTrue(
            addresses[0] == address(diamondLoupeFacet) || addresses[1] == address(diamondLoupeFacet)
        );
    }

    /*//////////////////////////////////////////////////////////////
                            DIAMOND LOUPE
    //////////////////////////////////////////////////////////////*/

    function test_Loupe_facets_returnsAllFacetsWithSelectors() public view {
        IDiamondLoupe.Facet[] memory facets = IDiamondLoupe(address(diamond)).facets();
        assertEq(facets.length, 2);

        for (uint256 i = 0; i < facets.length; i++) {
            assertTrue(
                facets[i].facetAddress == address(diamondCutFacet)
                    || facets[i].facetAddress == address(diamondLoupeFacet)
            );
            assertTrue(facets[i].functionSelectors.length > 0);
        }
    }

    function test_Loupe_facetAddresses_returnsAllAddresses() public view {
        address[] memory addresses = IDiamondLoupe(address(diamond)).facetAddresses();
        assertEq(addresses.length, 2);
    }

    function test_Loupe_facetFunctionSelectors_returnsSelectorsForCutFacet() public view {
        bytes4[] memory selectors =
            IDiamondLoupe(address(diamond)).facetFunctionSelectors(address(diamondCutFacet));
        assertEq(selectors.length, 3); // diamondCut, owner, setOwner
        assertTrue(selectors[0] == IDiamondCut.diamondCut.selector || selectors[1] == IDiamondCut.diamondCut.selector
            || selectors[2] == IDiamondCut.diamondCut.selector);
    }

    function test_Loupe_facetFunctionSelectors_returnsSelectorsForLoupeFacet() public view {
        bytes4[] memory selectors =
            IDiamondLoupe(address(diamond)).facetFunctionSelectors(address(diamondLoupeFacet));
        assertEq(selectors.length, 5); // facets, facetFunctionSelectors, facetAddresses, facetAddress, supportsInterface
    }

    function test_Loupe_facetAddress_returnsCorrectFacetForSelector() public view {
        assertEq(
            IDiamondLoupe(address(diamond)).facetAddress(IDiamondOwner.owner.selector),
            address(diamondCutFacet)
        );
        assertEq(
            IDiamondLoupe(address(diamond)).facetAddress(IDiamondLoupe.facets.selector),
            address(diamondLoupeFacet)
        );
    }

    function test_Loupe_facetAddress_returnsZeroForUnknownSelector() public view {
        assertEq(IDiamondLoupe(address(diamond)).facetAddress(bytes4(0xdeadbeef)), address(0));
    }

    function test_Loupe_supportsInterface_returnsTrueForSupported() public view {
        assertTrue(IERC165(address(diamond)).supportsInterface(type(IDiamondCut).interfaceId));
        assertTrue(IERC165(address(diamond)).supportsInterface(type(IDiamondLoupe).interfaceId));
        assertTrue(IERC165(address(diamond)).supportsInterface(type(IDiamondOwner).interfaceId));
        assertTrue(IERC165(address(diamond)).supportsInterface(type(IERC165).interfaceId));
    }

    function test_Loupe_supportsInterface_returnsFalseForUnsupported() public view {
        assertFalse(IERC165(address(diamond)).supportsInterface(bytes4(0xffffffff)));
    }

    /*//////////////////////////////////////////////////////////////
                            OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function test_Owner_owner_returnsDeployer() public view {
        assertEq(IDiamondOwner(address(diamond)).owner(), owner);
    }

    function test_Owner_setOwner_succeedsAsOwner() public {
        address newOwner = makeAddr("newOwner");
        IDiamondOwner(address(diamond)).setOwner(newOwner);
        assertEq(IDiamondOwner(address(diamond)).owner(), newOwner);
    }

    function test_Owner_setOwner_emitsOwnershipTransferred() public {
        address newOwner = makeAddr("newOwner");
        vm.expectEmit(true, true, false, true);
        emit LibDiamond.OwnershipTransferred(owner, newOwner);
        IDiamondOwner(address(diamond)).setOwner(newOwner);
    }

    function test_Owner_setOwner_revertsWhenNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(LibDiamond.NotContractOwner.selector, nonOwner, owner)
        );
        IDiamondOwner(address(diamond)).setOwner(nonOwner);
    }

    /*//////////////////////////////////////////////////////////////
                            DIAMOND CUT - ADD
    //////////////////////////////////////////////////////////////*/

    function test_Cut_diamondCut_addFacet_succeeds() public {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = MockFacet.getValue.selector;
        selectors[1] = MockFacet.getOtherValue.selector;

        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: selectors
        });

        vm.expectEmit(false, false, false, true);
        emit LibDiamond.DiamondCut(cuts, address(0), "");
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");

        assertEq(IDiamondLoupe(address(diamond)).facetAddress(MockFacet.getValue.selector), address(mockFacet));
        assertEq(MockFacet(address(diamond)).getValue(), 42);
        assertEq(MockFacet(address(diamond)).getOtherValue(), 100);
    }

    function test_Cut_diamondCut_addFacet_revertsWhenNotOwner() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: selectors
        });

        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(LibDiamond.NotContractOwner.selector, nonOwner, owner)
        );
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
    }

    function test_Cut_diamondCut_addFacet_revertsWhenSelectorAlreadyExists() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: selectors
        });
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");

        vm.expectRevert(
            abi.encodeWithSelector(
                LibDiamond.CannotAddFunctionToDiamondThatAlreadyExists.selector,
                MockFacet.getValue.selector
            )
        );
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
    }

    function test_Cut_diamondCut_addFacet_revertsWhenZeroAddress() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut({
            facetAddress: address(0),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: selectors
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                LibDiamond.CannotAddSelectorsToZeroAddress.selector,
                selectors
            )
        );
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
    }

    function test_Cut_diamondCut_addFacet_revertsWhenFacetHasNoCode() public {
        address eoa = makeAddr("eoa");
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut({
            facetAddress: eoa,
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: selectors
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                LibDiamond.NoBytecodeAtAddress.selector,
                eoa,
                "LibDiamond: New facet has no code"
            )
        );
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
    }

    function test_Cut_diamondCut_addFacet_revertsWhenEmptySelectors() public {
        bytes4[] memory selectors;
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: selectors
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                LibDiamond.NoSelectorsProvidedForFacetForCut.selector,
                address(mockFacet)
            )
        );
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
    }

    /*//////////////////////////////////////////////////////////////
                            DIAMOND CUT - REPLACE
    //////////////////////////////////////////////////////////////*/

    function test_Cut_diamondCut_replaceFacet_succeeds() public {
        bytes4[] memory addSelectors = new bytes4[](1);
        addSelectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory addCuts = new IDiamondCut.FacetCut[](1);
        addCuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: addSelectors
        });
        IDiamondCut(address(diamond)).diamondCut(addCuts, address(0), "");
        assertEq(MockFacet(address(diamond)).getValue(), 42);

        bytes4[] memory replaceSelectors = new bytes4[](1);
        replaceSelectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory replaceCuts = new IDiamondCut.FacetCut[](1);
        replaceCuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacetReplacement),
            action: IDiamond.FacetCutAction.Replace,
            functionSelectors: replaceSelectors
        });
        IDiamondCut(address(diamond)).diamondCut(replaceCuts, address(0), "");

        assertEq(IDiamondLoupe(address(diamond)).facetAddress(MockFacet.getValue.selector), address(mockFacetReplacement));
        assertEq(MockFacet(address(diamond)).getValue(), 42);
    }

    function test_Cut_diamondCut_replaceFacet_revertsWhenNotOwner() public {
        bytes4[] memory addSelectors = new bytes4[](1);
        addSelectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory addCuts = new IDiamondCut.FacetCut[](1);
        addCuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: addSelectors
        });
        IDiamondCut(address(diamond)).diamondCut(addCuts, address(0), "");

        bytes4[] memory replaceSelectors = new bytes4[](1);
        replaceSelectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory replaceCuts = new IDiamondCut.FacetCut[](1);
        replaceCuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacetReplacement),
            action: IDiamond.FacetCutAction.Replace,
            functionSelectors: replaceSelectors
        });

        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(LibDiamond.NotContractOwner.selector, nonOwner, owner)
        );
        IDiamondCut(address(diamond)).diamondCut(replaceCuts, address(0), "");
    }

    function test_Cut_diamondCut_replaceFacet_revertsWhenSelectorDoesNotExist() public {
        bytes4[] memory replaceSelectors = new bytes4[](1);
        replaceSelectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory replaceCuts = new IDiamondCut.FacetCut[](1);
        replaceCuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacetReplacement),
            action: IDiamond.FacetCutAction.Replace,
            functionSelectors: replaceSelectors
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                LibDiamond.CannotReplaceFunctionThatDoesNotExist.selector,
                MockFacet.getValue.selector
            )
        );
        IDiamondCut(address(diamond)).diamondCut(replaceCuts, address(0), "");
    }

    function test_Cut_diamondCut_replaceFacet_revertsWhenSameFacet() public {
        bytes4[] memory addSelectors = new bytes4[](1);
        addSelectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory addCuts = new IDiamondCut.FacetCut[](1);
        addCuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: addSelectors
        });
        IDiamondCut(address(diamond)).diamondCut(addCuts, address(0), "");

        bytes4[] memory replaceSelectors = new bytes4[](1);
        replaceSelectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory replaceCuts = new IDiamondCut.FacetCut[](1);
        replaceCuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacet),
            action: IDiamond.FacetCutAction.Replace,
            functionSelectors: replaceSelectors
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                LibDiamond.CannotReplaceFunctionWithTheSameFunctionFromTheSameFacet.selector,
                MockFacet.getValue.selector
            )
        );
        IDiamondCut(address(diamond)).diamondCut(replaceCuts, address(0), "");
    }

    function test_Cut_diamondCut_replaceFacet_revertsWhenEmptySelectors() public {
        bytes4[] memory replaceSelectors;
        IDiamondCut.FacetCut[] memory replaceCuts = new IDiamondCut.FacetCut[](1);
        replaceCuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacetReplacement),
            action: IDiamond.FacetCutAction.Replace,
            functionSelectors: replaceSelectors
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                LibDiamond.NoSelectorsProvidedForFacetForCut.selector,
                address(mockFacetReplacement)
            )
        );
        IDiamondCut(address(diamond)).diamondCut(replaceCuts, address(0), "");
    }

    function test_Cut_diamondCut_replaceFacet_revertsWhenZeroAddress() public {
        bytes4[] memory addSelectors = new bytes4[](1);
        addSelectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory addCuts = new IDiamondCut.FacetCut[](1);
        addCuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: addSelectors
        });
        IDiamondCut(address(diamond)).diamondCut(addCuts, address(0), "");

        bytes4[] memory replaceSelectors = new bytes4[](1);
        replaceSelectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory replaceCuts = new IDiamondCut.FacetCut[](1);
        replaceCuts[0] = IDiamond.FacetCut({
            facetAddress: address(0),
            action: IDiamond.FacetCutAction.Replace,
            functionSelectors: replaceSelectors
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                LibDiamond.CannotAddSelectorsToZeroAddress.selector,
                replaceSelectors
            )
        );
        IDiamondCut(address(diamond)).diamondCut(replaceCuts, address(0), "");
    }

    /*//////////////////////////////////////////////////////////////
                            DIAMOND CUT - REMOVE
    //////////////////////////////////////////////////////////////*/

    function test_Cut_diamondCut_removeFacet_succeeds() public {
        bytes4[] memory addSelectors = new bytes4[](1);
        addSelectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory addCuts = new IDiamondCut.FacetCut[](1);
        addCuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: addSelectors
        });
        IDiamondCut(address(diamond)).diamondCut(addCuts, address(0), "");

        bytes4[] memory removeSelectors = new bytes4[](1);
        removeSelectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory removeCuts = new IDiamondCut.FacetCut[](1);
        removeCuts[0] = IDiamond.FacetCut({
            facetAddress: address(0),
            action: IDiamond.FacetCutAction.Remove,
            functionSelectors: removeSelectors
        });
        IDiamondCut(address(diamond)).diamondCut(removeCuts, address(0), "");

        assertEq(IDiamondLoupe(address(diamond)).facetAddress(MockFacet.getValue.selector), address(0));
        vm.expectRevert(abi.encodeWithSelector(Diamond.FunctionNotFound.selector, MockFacet.getValue.selector));
        MockFacet(address(diamond)).getValue();
    }

    function test_Cut_diamondCut_removeFacet_revertsWhenNotOwner() public {
        bytes4[] memory addSelectors = new bytes4[](1);
        addSelectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory addCuts = new IDiamondCut.FacetCut[](1);
        addCuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: addSelectors
        });
        IDiamondCut(address(diamond)).diamondCut(addCuts, address(0), "");

        bytes4[] memory removeSelectors = new bytes4[](1);
        removeSelectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory removeCuts = new IDiamondCut.FacetCut[](1);
        removeCuts[0] = IDiamond.FacetCut({
            facetAddress: address(0),
            action: IDiamond.FacetCutAction.Remove,
            functionSelectors: removeSelectors
        });

        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(LibDiamond.NotContractOwner.selector, nonOwner, owner)
        );
        IDiamondCut(address(diamond)).diamondCut(removeCuts, address(0), "");
    }

    function test_Cut_diamondCut_removeFacet_revertsWhenSelectorDoesNotExist() public {
        bytes4[] memory removeSelectors = new bytes4[](1);
        removeSelectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory removeCuts = new IDiamondCut.FacetCut[](1);
        removeCuts[0] = IDiamond.FacetCut({
            facetAddress: address(0),
            action: IDiamond.FacetCutAction.Remove,
            functionSelectors: removeSelectors
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                LibDiamond.CannotRemoveFunctionThatDoesNotExist.selector,
                MockFacet.getValue.selector
            )
        );
        IDiamondCut(address(diamond)).diamondCut(removeCuts, address(0), "");
    }

    function test_Cut_diamondCut_removeFacet_revertsWhenFacetAddressNotZero() public {
        bytes4[] memory addSelectors = new bytes4[](1);
        addSelectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory addCuts = new IDiamondCut.FacetCut[](1);
        addCuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: addSelectors
        });
        IDiamondCut(address(diamond)).diamondCut(addCuts, address(0), "");

        bytes4[] memory removeSelectors = new bytes4[](1);
        removeSelectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory removeCuts = new IDiamondCut.FacetCut[](1);
        removeCuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacet),
            action: IDiamond.FacetCutAction.Remove,
            functionSelectors: removeSelectors
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                LibDiamond.RemoveFacetAddressMustBeZeroAddress.selector,
                address(mockFacet)
            )
        );
        IDiamondCut(address(diamond)).diamondCut(removeCuts, address(0), "");
    }

    function test_Cut_diamondCut_removeFacet_revertsWhenEmptySelectors() public {
        bytes4[] memory removeSelectors;
        IDiamondCut.FacetCut[] memory removeCuts = new IDiamondCut.FacetCut[](1);
        removeCuts[0] = IDiamond.FacetCut({
            facetAddress: address(0),
            action: IDiamond.FacetCutAction.Remove,
            functionSelectors: removeSelectors
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                LibDiamond.NoSelectorsProvidedForFacetForCut.selector,
                address(0)
            )
        );
        IDiamondCut(address(diamond)).diamondCut(removeCuts, address(0), "");
    }

    function test_Cut_diamondCut_removeFacet_removeOneOfTwoSelectors_hitsSwapPath() public {
        bytes4[] memory addSelectors = new bytes4[](2);
        addSelectors[0] = MockFacet.getValue.selector;
        addSelectors[1] = MockFacet.getOtherValue.selector;
        IDiamondCut.FacetCut[] memory addCuts = new IDiamondCut.FacetCut[](1);
        addCuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: addSelectors
        });
        IDiamondCut(address(diamond)).diamondCut(addCuts, address(0), "");

        bytes4[] memory removeSelectors = new bytes4[](1);
        removeSelectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory removeCuts = new IDiamondCut.FacetCut[](1);
        removeCuts[0] = IDiamond.FacetCut({
            facetAddress: address(0),
            action: IDiamond.FacetCutAction.Remove,
            functionSelectors: removeSelectors
        });
        IDiamondCut(address(diamond)).diamondCut(removeCuts, address(0), "");

        assertEq(IDiamondLoupe(address(diamond)).facetAddress(MockFacet.getValue.selector), address(0));
        assertEq(IDiamondLoupe(address(diamond)).facetAddress(MockFacet.getOtherValue.selector), address(mockFacet));
        assertEq(MockFacet(address(diamond)).getOtherValue(), 100);
    }

    function test_Cut_diamondCut_removeFacet_removingMiddleFacet_hitsFacetSwapPath() public {
        bytes4[] memory add1 = new bytes4[](1);
        add1[0] = MockFacet.getValue.selector;
        bytes4[] memory add2 = new bytes4[](1);
        add2[0] = MockFacet.getOtherValue.selector;
        IDiamondCut.FacetCut[] memory addCuts = new IDiamondCut.FacetCut[](2);
        addCuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: add1
        });
        addCuts[1] = IDiamond.FacetCut({
            facetAddress: address(mockFacetReplacement),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: add2
        });
        IDiamondCut(address(diamond)).diamondCut(addCuts, address(0), "");

        bytes4[] memory removeSelectors = new bytes4[](1);
        removeSelectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory removeCuts = new IDiamondCut.FacetCut[](1);
        removeCuts[0] = IDiamond.FacetCut({
            facetAddress: address(0),
            action: IDiamond.FacetCutAction.Remove,
            functionSelectors: removeSelectors
        });
        IDiamondCut(address(diamond)).diamondCut(removeCuts, address(0), "");

        assertEq(IDiamondLoupe(address(diamond)).facetAddress(MockFacet.getValue.selector), address(0));
        assertEq(IDiamondLoupe(address(diamond)).facetAddress(MockFacet.getOtherValue.selector), address(mockFacetReplacement));
    }

    function test_Cut_diamondCut_revertsWhenReplaceImmutableFunction() public {
        bytes4[] memory addSelectors = new bytes4[](1);
        addSelectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory addCuts = new IDiamondCut.FacetCut[](1);
        addCuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: addSelectors
        });
        IDiamondCut(address(diamond)).diamondCut(addCuts, address(0), "");

        bytes4[] memory replaceSelectors = new bytes4[](1);
        replaceSelectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory replaceToDiamond = new IDiamondCut.FacetCut[](1);
        replaceToDiamond[0] = IDiamond.FacetCut({
            facetAddress: address(diamond),
            action: IDiamond.FacetCutAction.Replace,
            functionSelectors: replaceSelectors
        });
        IDiamondCut(address(diamond)).diamondCut(replaceToDiamond, address(0), "");

        vm.expectRevert(
            abi.encodeWithSelector(
                LibDiamond.CannotReplaceImmutableFunction.selector,
                MockFacet.getValue.selector
            )
        );
        IDiamondCut.FacetCut[] memory replaceAway = new IDiamondCut.FacetCut[](1);
        replaceAway[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacetReplacement),
            action: IDiamond.FacetCutAction.Replace,
            functionSelectors: replaceSelectors
        });
        IDiamondCut(address(diamond)).diamondCut(replaceAway, address(0), "");
    }

    function test_Cut_diamondCut_revertsWhenRemoveImmutableFunction() public {
        bytes4[] memory addSelectors = new bytes4[](1);
        addSelectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory addCuts = new IDiamondCut.FacetCut[](1);
        addCuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: addSelectors
        });
        IDiamondCut(address(diamond)).diamondCut(addCuts, address(0), "");

        IDiamondCut.FacetCut[] memory replaceToDiamond = new IDiamondCut.FacetCut[](1);
        replaceToDiamond[0] = IDiamond.FacetCut({
            facetAddress: address(diamond),
            action: IDiamond.FacetCutAction.Replace,
            functionSelectors: addSelectors
        });
        IDiamondCut(address(diamond)).diamondCut(replaceToDiamond, address(0), "");

        bytes4[] memory removeSelectors = new bytes4[](1);
        removeSelectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory removeCuts = new IDiamondCut.FacetCut[](1);
        removeCuts[0] = IDiamond.FacetCut({
            facetAddress: address(0),
            action: IDiamond.FacetCutAction.Remove,
            functionSelectors: removeSelectors
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                LibDiamond.CannotRemoveImmutableFunction.selector,
                MockFacet.getValue.selector
            )
        );
        IDiamondCut(address(diamond)).diamondCut(removeCuts, address(0), "");
    }

    /*//////////////////////////////////////////////////////////////
                            DIAMOND CUT - INIT
    //////////////////////////////////////////////////////////////*/

    function test_Cut_diamondCut_init_succeeds() public {
        DiamondInitSuccess initContract = new DiamondInitSuccess();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: selectors
        });
        IDiamondCut(address(diamond)).diamondCut(
            cuts,
            address(initContract),
            abi.encodeWithSelector(DiamondInitSuccess.init.selector)
        );
        assertEq(MockFacet(address(diamond)).getValue(), 42);
    }

    function test_Cut_diamondCut_init_revertsWhenInitHasNoCode() public {
        address eoa = makeAddr("eoa");
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: selectors
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                LibDiamond.NoBytecodeAtAddress.selector,
                eoa,
                "LibDiamond: _init address has no code"
            )
        );
        IDiamondCut(address(diamond)).diamondCut(
            cuts,
            eoa,
            abi.encodeWithSelector(DiamondInitSuccess.init.selector)
        );
    }

    function test_Cut_diamondCut_init_revertsWithDataBubblesUp() public {
        DiamondInitRevertWithData initContract = new DiamondInitRevertWithData();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: selectors
        });
        vm.expectRevert(
            abi.encodeWithSelector(DiamondInitRevertWithData.InitFailed.selector, "init failed")
        );
        IDiamondCut(address(diamond)).diamondCut(
            cuts,
            address(initContract),
            abi.encodeWithSelector(DiamondInitRevertWithData.init.selector)
        );
    }

    function test_Cut_diamondCut_init_revertsWithNoData_returnsInitializationFunctionReverted() public {
        DiamondInitRevertNoData initContract = new DiamondInitRevertNoData();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: selectors
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                LibDiamond.InitializationFunctionReverted.selector,
                address(initContract),
                abi.encodeWithSelector(DiamondInitRevertNoData.init.selector)
            )
        );
        IDiamondCut(address(diamond)).diamondCut(
            cuts,
            address(initContract),
            abi.encodeWithSelector(DiamondInitRevertNoData.init.selector)
        );
    }

    /*//////////////////////////////////////////////////////////////
                            FALLBACK ROUTING
    //////////////////////////////////////////////////////////////*/

    function test_Fallback_routesToFacetAndReturnsValue() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MockFacet.getValue.selector;
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut({
            facetAddress: address(mockFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: selectors
        });
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");

        uint256 value = MockFacet(address(diamond)).getValue();
        assertEq(value, 42);
    }

    function test_Fallback_revertsFunctionNotFoundForUnknownSelector() public {
        bytes4 unknownSelector = bytes4(keccak256("nonexistent()"));
        (bool success, bytes memory returnData) =
            address(diamond).call(abi.encodeWithSelector(unknownSelector));
        assertFalse(success);
        assertEq(
            bytes4(returnData),
            Diamond.FunctionNotFound.selector,
            "revert should be FunctionNotFound"
        );
    }

    function test_Fallback_preservesMsgSender() public view {
        assertEq(IDiamondOwner(address(diamond)).owner(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                            RECEIVE
    //////////////////////////////////////////////////////////////*/

    function test_Receive_acceptsEth() public {
        vm.deal(nonOwner, 1 ether);
        vm.prank(nonOwner);
        (bool success,) = address(diamond).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(diamond).balance, 1 ether);
    }
}
