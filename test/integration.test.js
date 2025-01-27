const {expect, assert} = require("chai")

describe("Integration Test", function () {
  async function deployContract(name, ...args) {
    console.log(name, " being deployed");
    let Contract = await ethers.getContractFactory(name);
    console.log(name, " got artifact");
    let contract = await Contract.deploy(...args);
    console.log(name, " deployed at ", contract.address);
    return contract;
  }

  function normalize(val, n = 18) {
    return '' + val + '0'.repeat(n)
  }

  it("should verify that the entire process works", async function () {

    const maxTotalSupply = 10000000000; // 10 billions
    let [owner, user1, user2, user3] = await ethers.getSigners();
    const SSYN = await ethers.getContractFactory("EscrowedSyndicateERC20");
    const ssyn = await SSYN.deploy();
    const SYN = await ethers.getContractFactory("SyndicateERC20");
    const syn = await SYN.deploy(owner.address, maxTotalSupply);

    let features = (await syn.FEATURE_TRANSFERS_ON_BEHALF()) +
        (await syn.FEATURE_TRANSFERS()) +
        (await syn.FEATURE_UNSAFE_TRANSFERS()) +
        (await syn.FEATURE_DELEGATIONS()) +
        (await syn.FEATURE_DELEGATIONS_ON_BEHALF());
    await syn.updateFeatures(features)
    await syn.transfer(user1.address, normalize(20000));
    expect((await syn.balanceOf(user1.address)) / 1e18).equal(20000);

    const PoolFactory = await ethers.getContractFactory("SyndicatePoolFactory");

    // deploy factory
    const poolFactory = await PoolFactory.deploy(syn.address, ssyn.address,
        normalize(5000), // synPerBlock
        100000000, // blockPerUpdate, decrease reward by 3%
        await ethers.provider.getBlockNumber(),
        await ethers.provider.getBlockNumber() + 10000000);


    const createPoolTx = await poolFactory.createPool(syn.address, await ethers.provider.getBlockNumber(), 1);

    const corePoolAddress = await poolFactory.getPoolAddress(syn.address);
    const SyndicateCorePool = await ethers.getContractFactory("SyndicateCorePool");
    const corePool = await SyndicateCorePool.attach(corePoolAddress);
    corePool.setQuickReward(99999);
    await network.provider.send("evm_mine");

    await ssyn.updateRole(corePoolAddress, await syn.ROLE_TOKEN_CREATOR()); // 9
    await syn.connect(user1).approve(corePool.address, normalize(10000));
    expect((await syn.allowance(user1.address, corePool.address))/ 1e18).equal(10000);

    expect(await ssyn.balanceOf(user1.address)).equal(0);
    await corePool.connect(user1).stake(normalize(1000),
        (await ethers.provider.getBlock()).timestamp + 365 * 24 * 3600, true);
    expect((await ssyn.balanceOf(user1.address)) / 1e18).equal(9999.899682905252);

    expect(await corePool.pendingYieldRewards(user1.address)).equal(0);
    await network.provider.send("evm_mine");

    expect((await corePool.pendingYieldRewards(user1.address)) / 1e18).equal(4999.999499998999);
    await network.provider.send("evm_mine"); // 13
    expect((await corePool.pendingYieldRewards(user1.address)) / 1e18).equal(9999.998999997999);

    expect((await syn.balanceOf(user1.address))/ 1e18).equal(19000.000000000004);
    await network.provider.send("evm_increaseTime", [366 * 24 * 3600])
    await network.provider.send("evm_mine")
    await corePool.processRewards(true);

    let unstakeTx = await corePool.connect(user1).unstake(0, normalize(500), true);
    expect((await syn.balanceOf(user1.address)) / 1e18).equal(19500);
    expect((await ssyn.balanceOf(user1.address)) / 1e18).equal(34999.89918289925);
    await corePool.processRewards(true);
    await syn.delegate(owner.address);
    expect((await syn.balanceOf(owner.address))/ 1e18).equal(6999980000);
    expect( (await syn.getVotingPower(owner.address)) / 1e18).equal(6999980000);
    expect( (await syn.getVotingPower(user1.address)) / 1e18).equal(0);
    await corePool.delegate(user1.address);
    await expect( (await syn.getVotingPower(user1.address)) / 1e18).equal(500);

    await expect(ssyn.connect(user1).transfer(user2.address, normalize(10000))).revertedWith("sSYN: Non Allowed Receiver");
    await ssyn.updateRole(user2.address, await ssyn.ROLE_WHITE_LISTED_RECEIVER());
    await ssyn.connect(user1).transfer(user2.address, normalize(10000));
    expect((await ssyn.balanceOf(user2.address))/ 1e18).equal(10000);

    features =
        (await syn.FEATURE_TRANSFERS()) + (await syn.FEATURE_UNSAFE_TRANSFERS() + (await syn.FEATURE_DELEGATIONS())
            + (await syn.FEATURE_DELEGATIONS_ON_BEHALF()));
    await syn.updateFeatures(features)

    await expect(syn.connect(user1).approve(user2.address, normalize(5000))).revertedWith("SYN: spender not allowed");
    await syn.updateRole(user2.address, await syn.ROLE_WHITE_LISTED_SPENDER());
    await syn.connect(user1).approve(user2.address, normalize(5000));
    await syn.connect(user2).transferFrom(user1.address, user3.address, normalize(5000));
    expect((await syn.balanceOf(user3.address))/1e18).equal(5000);
    })
})
