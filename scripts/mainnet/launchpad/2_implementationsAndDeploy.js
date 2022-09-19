const { ethers } = require("hardhat")
const { createTx, sendTx } = require('../../../utils/gnosis');

const MANAGER_ADDRESS = "0xb217522e976c6360d3e2F68E2440e070eaae86ea"
const TUT_ADDRESS = "0x930f169A87545a8c6a3e7934d42d1582c03e1b35"
const LP_ADDRESS = "0xfd5447D667eB6960fA326cfa68b7936f52940cA7"
const SAFE = "0x144884904F833cc0D0e62787b6761A46712C28F4"
const DEPLOYER = "0x56a81Eb9d793007D5ee10c24F290b86121A70f59"

async function main() {
    const TutellusLaunchpadDeployer = await ethers.getContractFactory("TutellusLaunchpadDeployer");
    const TutellusEnergy = await ethers.getContractFactory("TutellusEnergy");
    const LaunchpadStaking = await ethers.getContractFactory("TutellusLaunchpadStaking")
    const FactionManager = await ethers.getContractFactory("TutellusFactionManager")
    const TutellusWhitelist = await ethers.getContractFactory("TutellusWhitelist");
    const TutellusEnergyMultiplierManager = await ethers.getContractFactory("TutellusEnergyMultiplierManager");
    const RewardsVaultV2 = await ethers.getContractFactory("TutellusRewardsVaultV2")
    const TutellusIDOFactory = await ethers.getContractFactory("TutellusIDOFactory");

    const vaultBytecode = RewardsVaultV2.bytecode
    const emptyInitializeCalldata = FactionManager.interface.encodeFunctionData("initialize", [])
    const initializeCalldataStaking = LaunchpadStaking.interface.encodeFunctionData("initialize", [TUT_ADDRESS, "100000000000000000", "10000000000000000000", "1296000"])
    const initializeCalldataFarming = LaunchpadStaking.interface.encodeFunctionData("initialize", [LP_ADDRESS, 0, 0, 0])

    const energyImplementation = await TutellusEnergy.deploy()
    await energyImplementation.deployed()
    const whitelistImplementation = await TutellusWhitelist.deploy()
    await whitelistImplementation.deployed()
    const energyMultiplierImplementation = await TutellusEnergyMultiplierManager.deploy()
    await energyMultiplierImplementation.deployed()
    const factionManagerImplementation = await FactionManager.deploy()
    await factionManagerImplementation.deployed()
    const stakingImplementation = await LaunchpadStaking.deploy()
    await stakingImplementation.deployed()
    const idoFactoryImplementation = await TutellusIDOFactory.deploy()
    await idoFactoryImplementation.deployed()

    const deployer = TutellusLaunchpadDeployer.attach(DEPLOYER)

    const wallet = new ethers.Wallet.fromMnemonic(process.env.MNEMONIC);
    const chainId = ethers.provider._network.chainId;

    const calldataDeploy = deployer.interface.encodeFunctionData(
        "deploy",
        [
            MANAGER_ADDRESS,
            vaultBytecode,
            energyImplementation.address,
            whitelistImplementation.address,
            energyMultiplierImplementation.address,
            factionManagerImplementation.address,
            stakingImplementation.address,
            idoFactoryImplementation.address,
            emptyInitializeCalldata,
            initializeCalldataStaking,
            initializeCalldataFarming
        ]
    )

    const dataDeploy = {
        to: deployer.address,
        data: calldataDeploy,
        value: 0,
        operation: 0,
    };

    const txDeploy = await createTx(ethers.provider, chainId, SAFE, dataDeploy, wallet);
    await sendTx(chainId, SAFE, txDeploy);

    console.log("Deployed")
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error)
        process.exit(1)
    })
