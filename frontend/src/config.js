// Public deployment settings come from Vite environment variables.
const env = import.meta.env;

export const CONTRACT_ADDRESS = (env.VITE_CONTRACT_ADDRESS || '').trim();
export const SEPOLIA_CHAIN_ID = BigInt(env.VITE_CHAIN_ID || '11155111');
export const SEPOLIA_HEX_CHAIN_ID = `0x${SEPOLIA_CHAIN_ID.toString(16)}`;
export const SEPOLIA_RPC_URL = env.VITE_SEPOLIA_RPC_URL || 'https://sepolia.drpc.org';
export const SEPOLIA_EXPLORER_URL = env.VITE_SEPOLIA_EXPLORER_URL || 'https://sepolia.etherscan.io';
