// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;

import "../interfaces/IPool.sol";
import "./SyndicateAware.sol";
import "./SyndicateCorePool.sol";
import "../token/EscrowedSyndicateERC20.sol";
import "../utils/Ownable.sol";

/**
 * @title Syndicate Pool Factory
 *
 * @notice SYN Pool Factory manages Syndicate Yield farming pools, provides a single
 *      public interface to access the pools, provides an interface for the pools
 *      to mint yield rewards, access pool-related info, update weights, etc.
 *
 * @notice The factory is authorized (via its owner) to register new pools, change weights
 *      of the existing pools, removing the pools (by changing their weights to zero)
 *
 * @dev The factory requires ROLE_TOKEN_CREATOR permission on the SYN token to mint yield
 *      (see `mintYieldTo` function)
 *
 */
contract SyndicatePoolFactory is Ownable, SyndicateAware {
  /**
   * @dev Smart contract unique identifier, a random number
   * @dev Should be regenerated each time smart contact source code is changed
   *      and changes smart contract itself is to be redeployed
   * @dev Generated using https://www.random.org/bytes/
   */
  uint256 public constant FACTORY_UID = 0xc5cfd88c6e4d7e5c8a03c0f0f03af23c0918d8e82cac196f57466af3fd4a5ec7;

  /// @dev Auxiliary data structure used only in getPoolData() view function
  struct PoolData {
    // @dev pool token address (like SYN)
    address poolToken;
    // @dev pool address (like deployed core pool instance)
    address poolAddress;
    // @dev pool weight (200 for SYN pools, 800 for SYN/ETH pools - set during deployment)
    uint32 weight;
    // @dev flash pool flag
    bool isFlashPool;
  }

  /**
   * @dev SYN/block determines yield farming reward base
   *      used by the yield pools controlled by the factory
   */
  uint192 public synPerBlock;

  /**
   * @dev The yield is distributed proportionally to pool weights;
   *      total weight is here to help in determining the proportion
   */
  uint32 public totalWeight;

  /**
   * @dev SYN/block decreases by 3% every blocks/update (set to 91252 blocks during deployment);
   *      an update is triggered by executing `updateSYNPerBlock` public function
   */
  uint32 public immutable blocksPerUpdate;

  /**
   * @dev End block is the last block when SYN/block can be decreased;
   *      it is implied that yield farming stops after that block
   */
  uint32 public endBlock;

  /**
   * @dev Each time the SYN/block ratio gets updated, the block number
   *      when the operation has occurred gets recorded into `lastRatioUpdate`
   * @dev This block number is then used to check if blocks/update `blocksPerUpdate`
   *      has passed when decreasing yield reward by 3%
   */
  uint32 public lastRatioUpdate;

  /// @dev sSYN token address is used to create SYN core pool(s)
  address public immutable ssyn;

  /// @dev Maps pool token address (like SYN) -> pool address (like core pool instance)
  mapping(address => address) public pools;

  /// @dev Keeps track of registered pool addresses, maps pool address -> exists flag
  mapping(address => bool) public poolExists;

  /**
   * @dev Fired in createPool() and registerPool()
   *
   * @param _by an address which executed an action
   * @param poolToken pool token address (like SYN)
   * @param poolAddress deployed pool instance address
   * @param weight pool weight
   * @param isFlashPool flag indicating if pool is a flash pool
   */
  event PoolRegistered(
    address indexed _by,
    address indexed poolToken,
    address indexed poolAddress,
    uint32 weight,
    bool isFlashPool
  );

  /**
   * @dev Fired in changePoolWeight()
   *
   * @param _by an address which executed an action
   * @param poolAddress deployed pool instance address
   * @param weight new pool weight
   */
  event WeightUpdated(address indexed _by, address indexed poolAddress, uint32 weight);

  /**
   * @dev Fired in updateSYNPerBlock()
   *
   * @param _by an address which executed an action
   * @param newSynPerBlock new SYN/block value
   */
  event SynRatioUpdated(address indexed _by, uint256 newSynPerBlock);

  /**
   * @dev Creates/deploys a factory instance
   *
   * @param _syn SYN ERC20 token address
   * @param _ssyn sSYN ERC20 token address
   * @param _synPerBlock initial SYN/block value for rewards
   * @param _blocksPerUpdate how frequently the rewards gets updated (decreased by 3%), blocks
   * @param _initBlock block number to measure _blocksPerUpdate from
   * @param _endBlock block number when farming stops and rewards cannot be updated anymore
   */
  constructor(
    address _syn,
    address _ssyn,
    uint192 _synPerBlock,
    uint32 _blocksPerUpdate,
    uint32 _initBlock,
    uint32 _endBlock
  ) SyndicateAware(_syn) {
    // verify the inputs are set
    require(_ssyn != address(0), "sSYN address not set");
    require(_synPerBlock > 0, "SYN/block not set");
    require(_blocksPerUpdate > 0, "blocks/update not set");
    require(_initBlock > 0, "init block not set");
    require(_endBlock > _initBlock, "invalid end block: must be greater than init block");

    // verify sSYN instance supplied
    require(
      EscrowedSyndicateERC20(_ssyn).TOKEN_UID() == 0xac3051b8d4f50966afb632468a4f61483ae6a953b74e387a01ef94316d6b7d62,
      "unexpected sSYN TOKEN_UID"
    );

    // save the inputs into internal state variables
    ssyn = _ssyn;
    synPerBlock = _synPerBlock;
    blocksPerUpdate = _blocksPerUpdate;
    lastRatioUpdate = _initBlock;
    endBlock = _endBlock;
  }

  /**
   * @notice Given a pool token retrieves corresponding pool address
   *
   * @dev A shortcut for `pools` mapping
   *
   * @param poolToken pool token address (like SYN) to query pool address for
   * @return pool address for the token specified
   */
  function getPoolAddress(address poolToken) external view returns (address) {
    // read the mapping and return
    return pools[poolToken];
  }

  /**
   * @notice Reads pool information for the pool defined by its pool token address,
   *      designed to simplify integration with the front ends
   *
   * @param _poolToken pool token address to query pool information for
   * @return pool information packed in a PoolData struct
   */
  function getPoolData(address _poolToken) public view returns (PoolData memory) {
    // get the pool address from the mapping
    address poolAddr = pools[_poolToken];

    // throw if there is no pool registered for the token specified
    require(poolAddr != address(0), "pool not found");

    // read pool information from the pool smart contract
    // via the pool interface (IPool)
    address poolToken = IPool(poolAddr).poolToken();
    bool isFlashPool = IPool(poolAddr).isFlashPool();
    uint32 weight = IPool(poolAddr).weight();

    // create the in-memory structure and return it
    return PoolData({poolToken: poolToken, poolAddress: poolAddr, weight: weight, isFlashPool: isFlashPool});
  }

  /**
   * @dev Verifies if `blocksPerUpdate` has passed since last SYN/block
   *      ratio update and if SYN/block reward can be decreased by 3%
   *
   * @return true if enough time has passed and `updateSYNPerBlock` can be executed
   */
  function shouldUpdateRatio() public view returns (bool) {
    // if yield farming period has ended
    if (blockNumber() > endBlock) {
      // SYN/block reward cannot be updated anymore
      return false;
    }

    // check if blocks/update (91252 blocks) have passed since last update
    return blockNumber() >= lastRatioUpdate + blocksPerUpdate;
  }

  /**
   * @dev Creates a core pool (SyndicateCorePool) and registers it within the factory
   *
   * @dev Can be executed by the pool factory owner only
   *
   * @param poolToken pool token address (like SYN, or SYN/ETH pair)
   * @param initBlock init block to be used for the pool created
   * @param weight weight of the pool to be created
   */
  function createPool(
    address poolToken,
    uint64 initBlock,
    uint32 weight
  ) external virtual onlyOwner {
    // create/deploy new core pool instance
    IPool pool = new SyndicateCorePool(syn, ssyn, this, poolToken, initBlock, weight);

    // register it within a factory
    registerPool(address(pool));
  }

  /**
   * @dev Registers an already deployed pool instance within the factory
   *
   * @dev Can be executed by the pool factory owner only
   *
   * @param poolAddr address of the already deployed pool instance
   */
  function registerPool(address poolAddr) public onlyOwner {
    // read pool information from the pool smart contract
    // via the pool interface (IPool)
    address poolToken = IPool(poolAddr).poolToken();
    bool isFlashPool = IPool(poolAddr).isFlashPool();
    uint32 weight = IPool(poolAddr).weight();

    // ensure that the pool is not already registered within the factory
    require(pools[poolToken] == address(0), "this pool is already registered");

    // create pool structure, register it within the factory
    pools[poolToken] = poolAddr;
    poolExists[poolAddr] = true;
    // update total pool weight of the factory
    totalWeight += weight;

    // emit an event
    emit PoolRegistered(msg.sender, poolToken, poolAddr, weight, isFlashPool);
  }

  /**
   * @notice Decreases SYN/block reward by 3%, can be executed
   *      no more than once per `blocksPerUpdate` blocks
   */
  function updateSYNPerBlock() external {
    // checks if ratio can be updated i.e. if blocks/update (91252 blocks) have passed
    require(shouldUpdateRatio(), "too frequent");

    // decreases SYN/block reward by 3%
    synPerBlock = (synPerBlock * 97) / 100;

    // set current block as the last ratio update block
    lastRatioUpdate = uint32(blockNumber());

    // emit an event
    emit SynRatioUpdated(msg.sender, synPerBlock);
  }

  /**
   * @dev Mints SYN tokens; executed by SYN Pool only
   *
   * @dev Requires factory to have ROLE_TOKEN_CREATOR permission
   *      on the SYN ERC20 token instance
   *
   * @param _to an address to mint tokens to
   * @param _amount amount of SYN tokens to mint
   */
  function mintYieldTo(address _to, uint256 _amount) external {
    // verify that sender is a pool registered withing the factory
    require(poolExists[msg.sender], "access denied");

    // mint SYN tokens as required
    _mintSyn(_to, _amount);
  }

  /**
   * @dev Changes the weight of the pool;
   *      executed by the pool itself or by the factory owner
   *
   * @param poolAddr address of the pool to change weight for
   * @param weight new weight value to set to
   */
  function changePoolWeight(address poolAddr, uint32 weight) external {
    // verify function is executed either by factory owner or by the pool itself
    require(msg.sender == owner() || poolExists[msg.sender]);

    // recalculate total weight
    totalWeight = totalWeight + weight - IPool(poolAddr).weight();

    // set the new pool weight
    IPool(poolAddr).setWeight(weight);

    // emit an event
    emit WeightUpdated(msg.sender, poolAddr, weight);
  }

  /**
   * @dev Testing time-dependent functionality is difficult and the best way of
   *      doing it is to override block number in helper test smart contracts
   *
   * @return `block.number` in mainnet, custom values in testnets (if overridden)
   */
  function blockNumber() public view virtual returns (uint256) {
    // return current block number
    return block.number;
  }
}
