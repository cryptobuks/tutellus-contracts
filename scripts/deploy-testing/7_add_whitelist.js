const hre = require('hardhat');
const { downloadJSON, uploadJSON } = require('../../utils/ipfs');
const { parseEther } = require('ethers/lib/utils');
const { concatArrays, getWhitelistTree } = require('../../utils/whitelistTree');

const main = async () => {
    await hre.run('compile');

    const myWhitelist = await ethers.getContractAt('TutellusWhitelist', '0x5F1a679b87222122de92A68C3c7e5A4A92455Deb');
    console.log('Getting current uri...')
    const uri0 = await myWhitelist.uri();

    console.log('Downloading current JSON...')
    const json0 = await downloadJSON(uri0);
    const currentAddresses = json0.addresses ? json0.addresses : [];
    const tree = getWhitelistTree(currentAddresses).toJSON();

    for(let i in currentAddresses) {
        const address = currentAddresses[i]
        const claim = tree.claims[address];
        const isWhitelisted = await myWhitelist.whitelisted(address);
        if (!isWhitelisted) {
            console.log('Adding account:', address);
            const tx = await myWhitelist.add(
                claim.index,
                address,
                claim.proof
            );
            await tx.wait();
        }
    } 
    console.log('Completed.');
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
    console.error(error);
    process.exitCode = 1;
});