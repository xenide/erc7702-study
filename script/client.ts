import {
	http,
	type Account,
	type Chain,
	type Transport,
	type WalletClient,
	createWalletClient,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { sepolia } from "viem/chains";

const privateKey = "0x...";
const account = privateKeyToAccount(privateKey);
console.log(`Account address = ${account.address}`);
export const walletClient = createWalletClient({
	account,
	chain: sepolia,
	transport: http(),
}) as WalletClient<Transport, Chain, Account>;

