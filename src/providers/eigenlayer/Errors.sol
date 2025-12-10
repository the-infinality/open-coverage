// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CoverageClaimStatus} from "../../interfaces/ICoverageProvider.sol";

error CoverageAgentAlreadyRegistered();
error InvalidRecipient();
error StrategyNotWhitelisted(address strategy);
error InvalidAVS();

error NotOperatorAuthorized(address operator, address handler);
error InvalidAsset(address strategyAsset, address positionAsset);
error NotAllocated();

// Reward distribution errors
error NoRewardsToClaim();
error ClaimNotFound(uint256 claimId);
error InvalidClaimStatus(uint256 claimId, CoverageClaimStatus status);
error ClaimAlreadyLiquidated(uint256 claimId);
error ClaimNotComplete(uint256 claimId);
