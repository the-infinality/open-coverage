# EigenLayer Coverage Provider Architecture

This document describes the EIP-2535 Diamond Standard architecture used for the EigenLayer coverage provider integration.

## Overview

The EigenLayer coverage manager uses the **EIP-2535 Diamond Standard** — a modular proxy pattern that enables:

- **Dynamic function routing** — Functions are routed via selector lookup in the `fallback()`
- **Upgradeable facets** — Facets can be added, replaced, or removed via `diamondCut()`
- **Shared storage context** — All facets operate on the diamond's storage via `delegatecall`
- **Standard introspection** — Query facets and their functions via `IDiamondLoupe`
- **EIP-165 support** — Interface detection via `supportsInterface()`

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                             External Callers                                │
│                    (CoverageAgent, Operators, Owner)                        │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│                         EigenCoverageDiamond                                │
│                      (EIP-2535 Diamond Proxy)                               │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                          fallback()                                   │  │
│  │    ┌─────────────────────────────────────────────────────────────┐    │  │
│  │    │  1. Extract msg.sig (function selector)                     │    │  │
│  │    │  2. Lookup facet address from selector registry             │    │  │
│  │    │  3. delegatecall to facet                                   │    │  │
│  │    │  4. Return result or revert                                 │    │  │
│  │    └─────────────────────────────────────────────────────────────┘    │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  Storage:                                                                   │
│  ┌─────────────────────────────┐  ┌─────────────────────────────────────┐   │
│  │   Diamond Storage           │  │   App Storage                       │   │
│  │   (LibDiamond @ fixed slot) │  │   (EigenCoverageStorage)            │   │
│  │   • selectorToFacet mapping │  │   • _eigenAddresses                 │   │
│  │   • facetAddresses[]        │  │   • positions[]                     │   │
│  │   • supportedInterfaces     │  │   • claims[]                        │   │
│  │   • contractOwner           │  │   • operators mapping               │   │
│  └─────────────────────────────┘  └─────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                  │                │                │                     │
                  ▼                ▼                ▼                     ▼
┌─────────────────────┐ ┌─────────────────────┐ ┌─────────────────────┐ ┌─────────────────────┐
│  DiamondCutFacet    │ │  DiamondLoupeFacet  │ │  EigenServiceMgr    │ │  EigenCoverageProv  │
│                     │ │                     │ │      Facet          │ │      Facet          │
│  • diamondCut()     │ │  • facets()         │ │                     │ │                     │
│                     │ │  • facetAddresses() │ │  • eigenAddresses() │ │  • onIsRegistered() │
│                     │ │  • facetAddress()   │ │  • registerOperator │ │  • createPosition() │
│                     │ │  • supportsInterface│ │  • setStrategy...   │ │  • closePosition()  │
│                     │ │                     │ │  • captureRewards() │ │  • claimCoverage()  │
│                     │ │                     │ │  • coverageAlloc... │ │  • position()       │
└─────────────────────┘ └─────────────────────┘ └─────────────────────┘ └─────────────────────┘
```

---

## How It Works

### 1. Function Routing via `fallback()`

When a function is called on `EigenCoverageDiamond`, the `fallback()` function:

1. Extracts the function selector from `msg.sig`
2. Looks up the facet address from the diamond's selector registry
3. Executes `delegatecall` to the facet
4. Returns the result (or reverts with the facet's error)

```solidity
fallback() external payable {
    LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
    address facet = ds.selectorToFacetAndPosition[msg.sig].facetAddress;
    if (facet == address(0)) revert FunctionNotFound(msg.sig);
    
    assembly {
        calldatacopy(0, 0, calldatasize())
        let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
        returndatacopy(0, 0, returndatasize())
        switch result
        case 0 { revert(0, returndatasize()) }
        default { return(0, returndatasize()) }
    }
}
```

### 2. Adding/Replacing/Removing Facets via `diamondCut()`

The `IDiamondCut` interface allows the owner to modify the diamond's facets:

```solidity
interface IDiamondCut {
    enum FacetCutAction { Add, Replace, Remove }
    
    struct FacetCut {
        address facetAddress;
        FacetCutAction action;
        bytes4[] functionSelectors;
    }
    
    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external;
}
```

### 3. Diamond Storage Pattern

Diamond-specific data (facets, selectors, owner) is stored at a fixed slot to prevent collisions with app storage:

```solidity
bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

struct DiamondStorage {
    mapping(bytes4 => FacetAddressAndPosition) selectorToFacetAndPosition;
    mapping(address => FacetFunctionSelectors) facetFunctionSelectors;
    address[] facetAddresses;
    mapping(bytes4 => bool) supportedInterfaces;
    address contractOwner;
}
```

---

## File Structure

```
src/
├── diamond/                                   # Reusable EIP-2535 infrastructure
│   ├── interfaces/
│   │   ├── IDiamondCut.sol                    # Add/replace/remove facets
│   │   ├── IDiamondLoupe.sol                  # Introspection interface
│   │   └── IERC165.sol                        # Interface detection
│   ├── libraries/
│   │   └── LibDiamond.sol                     # Diamond storage & cut logic
│   └── facets/
│       ├── DiamondCutFacet.sol                # Implements IDiamondCut
│       └── DiamondLoupeFacet.sol              # Implements IDiamondLoupe + IERC165
│
├── providers/
│   └── eigenlayer/
│       ├── EigenCoverageDiamond.sol           # Main diamond proxy
│       ├── EigenCoverageStorage.sol           # App-specific storage
│       ├── Types.sol                          # EigenAddresses struct
│       ├── Errors.sol                         # Custom errors
│       ├── interfaces/
│       │   └── IEigenServiceManager.sol       # Service manager interface
│       ├── facets/
│       │   ├── EigenServiceManagerFacet.sol   # IEigenServiceManager implementation
│       │   └── EigenCoverageProviderFacet.sol # ICoverageProvider implementation
│       └── README.md                          # This file
│
└── interfaces/
    └── ICoverageProvider.sol                  # Coverage provider interface
```

---

## Deployment

The diamond is deployed with all facets registered in the constructor:

```solidity
// 1. Deploy all facets
DiamondCutFacet diamondCutFacet = new DiamondCutFacet();
DiamondLoupeFacet diamondLoupeFacet = new DiamondLoupeFacet();
EigenServiceManagerFacet serviceManagerFacet = new EigenServiceManagerFacet();
EigenCoverageProviderFacet coverageProviderFacet = new EigenCoverageProviderFacet();

// 2. Prepare diamond cuts
IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](4);
cuts[0] = IDiamondCut.FacetCut({
    facetAddress: address(diamondCutFacet),
    action: IDiamondCut.FacetCutAction.Add,
    functionSelectors: getDiamondCutSelectors()
});
// ... repeat for other facets

// 3. Deploy diamond with cuts and initialization args
EigenCoverageDiamond diamond = new EigenCoverageDiamond(cuts, args);
```

---

## Upgrading Facets

After deployment, the owner can upgrade facets via `diamondCut()`:

```solidity
// Deploy new facet version
EigenServiceManagerFacetV2 newFacet = new EigenServiceManagerFacetV2();

// Replace existing functions
IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
cuts[0] = IDiamondCut.FacetCut({
    facetAddress: address(newFacet),
    action: IDiamondCut.FacetCutAction.Replace,
    functionSelectors: getEigenServiceManagerSelectors()
});

// Execute upgrade
IDiamondCut(diamond).diamondCut(cuts, address(0), "");
```

---

## Introspection

Query the diamond's structure using `IDiamondLoupe`:

```solidity
IDiamondLoupe loupe = IDiamondLoupe(diamond);

// Get all facets
IDiamondLoupe.Facet[] memory facets = loupe.facets();

// Get functions for a specific facet
bytes4[] memory selectors = loupe.facetFunctionSelectors(facetAddress);

// Get facet for a specific function
address facet = loupe.facetAddress(selector);

// Check interface support
bool supported = IERC165(diamond).supportsInterface(interfaceId);
```

---

## Key Benefits of EIP-2535

| Benefit | Description |
|---------|-------------|
| **Modularity** | Logic is separated into focused facets |
| **Dynamic Upgrades** | Add/replace/remove functions without redeployment |
| **No Size Limit** | Bypass the 24KB contract size limit |
| **Gas Efficiency** | Only deploy changed facets |
| **Standard Introspection** | Query facets via IDiamondLoupe |
| **Shared Storage** | All facets operate on consistent storage |

---

## Storage Considerations

1. **Diamond Storage**: Uses a fixed slot (`keccak256("diamond.standard.diamond.storage")`) for facet registry
2. **App Storage**: `EigenCoverageStorage` is inherited by the diamond and all facets
3. **No Collisions**: The fixed slot approach prevents storage slot collisions
4. **Upgradeable**: App storage includes a `__gap` for future extensions

---

## Related Standards

- [EIP-2535: Diamonds, Multi-Facet Proxy](https://eips.ethereum.org/EIPS/eip-2535)
- [EIP-165: Standard Interface Detection](https://eips.ethereum.org/EIPS/eip-165)
- [Diamond Reference Implementation](https://github.com/mudgen/diamond-3)
