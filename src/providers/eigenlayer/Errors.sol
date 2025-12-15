// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

error CoverageAgentAlreadyRegistered();
error InvalidRecipient();
error StrategyNotWhitelisted(address strategy);
error InvalidAVS();

error NotOperatorAuthorized(address operator, address handler);
error InvalidAsset(address strategyAsset, address positionAsset);
error NotAllocated();
error NotImplemented();
