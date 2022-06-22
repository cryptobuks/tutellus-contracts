const bre = require("hardhat");
const ethers = bre.ethers;

const LAUNCHPAD_IDO_FACTORY = ethers.utils.id("LAUNCHPAD_IDO_FACTORY");
const IDO_USDT = ethers.utils.id("IDO_USDT");
const MANAGER_ADDR = "0xF182F7576867D6516C280aacbE99c8230250C153";
const FUNDING_AMOUNT = ethers.utils.parseEther("100000");
const MIN_PREFUND = ethers.utils.parseEther("1000");
const TIME_OFFSET = 864000
const START_DATE = parseInt(Date.now()/1000) + TIME_OFFSET
const END_DATE = START_DATE + 86400000 + TIME_OFFSET

async function main() {
    bre.run("compile");
    const Manager = await ethers.getContractFactory("TutellusManager");
    const TutellusIDOFactory = await ethers.getContractFactory(
        "TutellusIDOFactory"
    );
    const TutellusIDO = await ethers.getContractFactory("TutellusIDO");
    const Token = await ethers.getContractFactory("Token");

    const myIdoToken = await Token.deploy("Tutellus IDO 1", "IDO1")
    await myIdoToken.deployed()
    const myManager = Manager.attach(MANAGER_ADDR);
    const idoFactoryAddr = await myManager.get(LAUNCHPAD_IDO_FACTORY);
    const idoUsdtAddr = await myManager.get(IDO_USDT);
    const myIdoFactory = TutellusIDOFactory.attach(idoFactoryAddr);
    const initializeCalldata = TutellusIDO.interface.encodeFunctionData(
        "initialize",
        [MANAGER_ADDR, FUNDING_AMOUNT, MIN_PREFUND, myIdoToken.address, idoUsdtAddr, START_DATE, END_DATE, 0]
    );
    const response = await myIdoFactory.createProxy(initializeCalldata);
    const receipt = await response.wait()

    console.log(
        "IDO: ",
        receipt.events[1].args.proxy
    );
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
