// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISlashCoordinator, SlashCoordinationStatus} from "src/interfaces/ISlashCoordinator.sol";

contract MockSlashCoordinator is ISlashCoordinator {
    mapping(uint256 => SlashCoordinationStatus) private _statuses;
    mapping(uint256 => address) private _coverageProviders;

    function initiateSlash(address coverageProvider, uint256 claimId, uint256 amount)
        external
        returns (SlashCoordinationStatus)
    {
        _statuses[claimId] = SlashCoordinationStatus.Pending;
        _coverageProviders[claimId] = coverageProvider;
        emit SlashRequested(coverageProvider, claimId, amount);
        return SlashCoordinationStatus.Pending;
    }

    function status(address, uint256 claimId) external view returns (SlashCoordinationStatus) {
        return _statuses[claimId];
    }

    function setStatus(uint256 claimId, SlashCoordinationStatus _status) external {
        _statuses[claimId] = _status;
        address coverageProvider = _coverageProviders[claimId];
        if (_status == SlashCoordinationStatus.Passed) {
            emit SlashCompleted(coverageProvider, claimId, 0);
        } else if (_status == SlashCoordinationStatus.Failed) {
            emit SlashFailed(coverageProvider, claimId);
        }
    }
}

/// @notice Mock slash coordinator that immediately returns Passed status
contract MockSlashCoordinatorImmediate is ISlashCoordinator {
    mapping(uint256 => SlashCoordinationStatus) private _statuses;

    function initiateSlash(address coverageProvider, uint256 claimId, uint256 amount)
        external
        returns (SlashCoordinationStatus)
    {
        _statuses[claimId] = SlashCoordinationStatus.Passed;
        emit SlashRequested(coverageProvider, claimId, amount);
        emit SlashCompleted(coverageProvider, claimId, amount);
        return SlashCoordinationStatus.Passed;
    }

    function status(address, uint256 claimId) external view returns (SlashCoordinationStatus) {
        return _statuses[claimId];
    }
}
