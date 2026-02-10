// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Init contract that succeeds (no-op) for diamondCut _init delegatecall
contract DiamondInitSuccess {
    function init() external {}
}

/// @notice Init contract that reverts with return data (bubble-up path)
contract DiamondInitRevertWithData {
    error InitFailed(string reason);

    function init() external pure {
        revert InitFailed("init failed");
    }
}

/// @notice Init contract that reverts with no return data (InitializationFunctionReverted path)
contract DiamondInitRevertNoData {
    function init() external pure {
        revert();
    }
}
