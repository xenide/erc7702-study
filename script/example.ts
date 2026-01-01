import { walletClient } from "./client.js";
 
const accountImplementation = "0x4Cd241E8d1510e30b2076397afc7508Ae59C66c9";

async function main() {
    const authorization = await walletClient.signAuthorization({
        contractAddress: accountImplementation,
        executor: "self",
    });
    
    const hash = await walletClient.sendTransaction({
        authorizationList: [authorization],
        data: "0x",
        to: walletClient.account.address,
    });
    console.log(`Delegated at tx ${hash}`);
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});