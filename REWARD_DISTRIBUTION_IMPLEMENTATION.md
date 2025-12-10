# Eigen Coverage Provider Reward Distribution Implementation

## Overview

This implementation adds comprehensive reward distribution logic to the Eigen Coverage Provider, addressing the requirements in Linear issue SPC-44.

## Implementation Summary

### 1. New Data Structures (`Types.sol`)

Added two new structs for tracking rewards:

- **`ClaimReward`**: Tracks reward information for each claim
  - `totalReward`: Total reward amount allocated to the claim
  - `distributedReward`: Amount already distributed to operators
  - `startTime`: When the claim started
  - `endTime`: When the claim ends
  - `liquidationTime`: When liquidation occurred (0 if not liquidated)

- **`OperatorRewards`**: Tracks operator rewards per coverage agent
  - `pendingRewards`: Rewards available for claiming
  - `claimedRewards`: Total rewards already claimed

### 2. Error Handling (`Errors.sol`)

Added new error types for reward distribution:
- `NoRewardsToClaim()`: When operator tries to claim with no pending rewards
- `ClaimNotFound(uint256 claimId)`: When claim doesn't exist
- `InvalidClaimStatus(uint256 claimId, CoverageClaimStatus status)`: Invalid status for operation
- `ClaimAlreadyLiquidated(uint256 claimId)`: When trying to liquidate already liquidated claim

### 3. Core Implementation (`EigenCoverageProvider.sol`)

#### Storage Variables
- `mapping(uint256 => ClaimReward) public claimRewardData`: Tracks reward data per claim
- `mapping(address => mapping(address => OperatorRewards)) public operatorRewards`: Tracks rewards per operator-agent pair

#### Key Functions

**`claimRewards(address operator, address coverageAgent)`**
- Allows operators to claim their pending rewards
- Includes permission check using Eigen's permission controller
- Emits `RewardsClaimed` event
- Updates reward tracking state

**`getPendingRewards(address operator, address coverageAgent)`**
- View function to check pending rewards for an operator

**`getClaimedRewards(address operator, address coverageAgent)`**
- View function to check total claimed rewards for an operator

### 4. Reward Distribution Logic by Refundable Status

#### `Refundable.None`
- **Behavior**: Rewards distributed immediately when coverage is issued
- **Implementation**: In `issueCoverage()`, rewards are added to `pendingRewards` immediately
- **Use Case**: Non-refundable premiums where operator earns full reward upfront

#### `Refundable.TimeWeighted`
- **Behavior**: Rewards distributed proportionally based on time elapsed
- **On Liquidation**: Only rewards earned up to liquidation point are distributed
  - Formula: `earnedReward = (totalReward × timeElapsed) / totalDuration`
- **On Completion**: Remaining rewards are distributed
- **Use Case**: Fair distribution when coverage may be liquidated mid-term

#### `Refundable.Full`
- **Behavior**: Rewards only distributed when claim completes successfully
- **On Liquidation**: No rewards distributed (full refund scenario)
- **On Completion**: All rewards distributed at once
- **Use Case**: High-assurance coverage where operators only earn if service completes

### 5. Liquidation Tracking

The `liquidateClaim()` function:
1. Validates claim status
2. Records liquidation timestamp
3. Calculates earned rewards up to liquidation point (for TimeWeighted)
4. Distributes appropriate rewards to operators
5. Updates claim status to `Liquidated`

### 6. Claim Completion

The `completeClaims()` function:
1. Validates claim can be completed
2. Handles reward distribution based on refundable status
3. Distributes remaining rewards (for Full and TimeWeighted)
4. Marks claim as `Completed`

### 7. Permission Control

Reward claiming uses Eigen's permission controller to ensure:
- Only authorized handlers can claim rewards on behalf of operators
- Permission check uses `_checkOperatorPermissions()` helper
- Validates against Eigen's rewards coordinator permissions

## Test Coverage

Comprehensive test suite added in `test/providers/Eigen.t.sol`:

1. **`test_rewardDistribution_None_ImmediateDistribution`**: Validates immediate reward distribution
2. **`test_rewardDistribution_TimeWeighted_OnLiquidation`**: Tests time-weighted rewards on liquidation
3. **`test_rewardDistribution_TimeWeighted_OnCompletion`**: Tests time-weighted rewards on completion
4. **`test_rewardDistribution_Full_OnCompletion`**: Tests full refundable completion
5. **`test_rewardDistribution_Full_NoRewardsOnLiquidation`**: Validates no rewards on full refund liquidation
6. **`test_claimRewards_Success`**: Tests successful reward claiming
7. **`test_claimRewards_NoRewardsReverts`**: Tests error handling when no rewards available

## Security Considerations

1. **Permission Checks**: All reward claims require operator authorization
2. **State Tracking**: Prevents double-distribution through careful state management
3. **Time-based Calculations**: Uses block.timestamp for time-weighted rewards
4. **Status Validation**: Prevents invalid state transitions

## Future Enhancements

1. Add actual token transfer logic in `claimRewards()` (currently marked as TODO)
2. Implement multi-asset support for different reward tokens
3. Add reward claiming batching for gas efficiency
4. Consider adding emergency withdrawal mechanisms

## Files Modified

1. `src/providers/eigenlayer/Types.sol` - Added reward tracking structures
2. `src/providers/eigenlayer/Errors.sol` - Added reward-related errors
3. `src/providers/eigenlayer/EigenCoverageProvider.sol` - Core reward distribution logic
4. `test/providers/Eigen.t.sol` - Comprehensive test suite

## Compilation Status

✅ Project compiles successfully with Solidity 0.8.24
✅ No linter errors
⚠️ Minor warnings about shadowing (non-critical)

## Testing Note

Tests require a mainnet RPC endpoint to fork from Ethereum mainnet. Set the `MAINNET_ARCHIVE_RPC` environment variable to run the full test suite.

Example:
```bash
export MAINNET_ARCHIVE_RPC="https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY"
forge test --match-path test/providers/Eigen.t.sol
```
