// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title DeploymentUtils
/// @notice Utilities for deployment scripts (e.g. bytecode comparison)
library DeploymentUtils {
    /// @notice Returns true if the on-chain runtime bytecode at an address matches the compiled runtime bytecode.
    /// @param onChainBytecode Runtime bytecode fetched from the chain (e.g. address(deployed).code)
    /// @param compiledBytecode Compiled runtime bytecode (e.g. vm.getDeployedCode("path/to/Contract.sol:ContractName"))
    /// @return True if both bytecodes are identical
    function bytecodeMatches(bytes memory onChainBytecode, bytes memory compiledBytecode)
        internal
        pure
        returns (bool)
    {
        if (onChainBytecode.length != compiledBytecode.length) return false;
        return keccak256(onChainBytecode) == keccak256(compiledBytecode);
    }
}
