// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;

import "./ILinkedToSYN.sol";

/**
 * @title Syndicate Pool
 *
 * @notice An abstraction representing a pool, see SyndicatePoolBase for details
 *
 */
interface IPool is ILinkedToSYN {
  /**
   * @dev Deposit is a key data structure used in staking,
   *      it represents a unit of stake with its amount, weight and term (time interval)
   */
  struct Deposit {
    // @dev token amount staked
    uint256 tokenAmount;
    // @dev stake weight
    uint256 weight;
    // @dev locking period - from
    uint64 lockedFrom;
    // @dev locking period - until
    uint64 lockedUntil;
    // @dev indicates if the stake was created as a yield reward
    bool isYield;
  }

  // for the rest of the functions see Soldoc in SyndicatePoolBase

  function ssyn() external view returns (address);

  function poolToken() external view returns (address);

  function isFlashPool() external view returns (bool);

  function weight() external view returns (uint32);

  function lastYieldDistribution() external view returns (uint64);

  function yieldRewardsPerWeight() external view returns (uint256);

  function usersLockingWeight() external view returns (uint256);

  function pendingYieldRewards(address _user) external view returns (uint256);

  function balanceOf(address _user) external view returns (uint256);

  function getDeposit(address _user, uint256 _depositId) external view returns (Deposit memory);

  function getDepositsLength(address _user) external view returns (uint256);

  function stake(
    uint256 _amount,
    uint64 _lockedUntil,
    bool useSSYN
  ) external;

  function unstake(
    uint256 _depositId,
    uint256 _amount,
    bool useSSYN
  ) external;

  function sync() external;

  function processRewards(bool useSSYN) external;

  function setWeight(uint32 _weight) external;
}
