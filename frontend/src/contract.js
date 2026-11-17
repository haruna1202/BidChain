import { BrowserProvider, Contract, formatEther, parseEther, keccak256, toUtf8Bytes } from 'ethers';
import artifact from './PokemonAuction.abi.json';
import { CONTRACT_ADDRESS, SEPOLIA_CHAIN_ID, SEPOLIA_HEX_CHAIN_ID, SEPOLIA_RPC_URL, SEPOLIA_EXPLORER_URL } from './config.js';

export async function connectWallet() {
  if (!window.ethereum) throw new Error('Chưa tìm thấy MetaMask. Hãy cài MetaMask rồi tải lại trang.');
  let provider = new BrowserProvider(window.ethereum);
  await provider.send('eth_requestAccounts', []);
  let network = await provider.getNetwork();
  if (network.chainId !== SEPOLIA_CHAIN_ID) {
    try { await window.ethereum.request({method:'wallet_switchEthereumChain',params:[{chainId:SEPOLIA_HEX_CHAIN_ID}]}); }
    catch (e) {
      if (e.code === 4902) await window.ethereum.request({method:'wallet_addEthereumChain',params:[{chainId:SEPOLIA_HEX_CHAIN_ID,chainName:'Sepolia',nativeCurrency:{name:'Sepolia ETH',symbol:'ETH',decimals:18},rpcUrls:[SEPOLIA_RPC_URL],blockExplorerUrls:[SEPOLIA_EXPLORER_URL]}]});
      else throw e;
    }
    // Tạo provider mới sau khi MetaMask đổi mạng để ethers cập nhật chainId.
    provider = new BrowserProvider(window.ethereum);
    network = await provider.getNetwork();
    if (network.chainId !== SEPOLIA_CHAIN_ID) throw new Error('Hãy chuyển MetaMask sang Sepolia rồi thử lại.');
  }
  const signer = await provider.getSigner();
  return { provider, signer, address: await signer.getAddress() };
}
export function getContract(signerOrProvider) {
  if (!CONTRACT_ADDRESS || !/^0x[\da-fA-F]{40}$/.test(CONTRACT_ADDRESS)) throw new Error('Bạn cần cấu hình VITE_CONTRACT_ADDRESS trong file .env.local.');
  return new Contract(CONTRACT_ADDRESS, artifact.abi, signerOrProvider);
}
export const toWei = (eth) => parseEther(String(eth));
export const fromWei = (wei) => Number(formatEther(wei));
export const hashText = (text) => keccak256(toUtf8Bytes(text.trim()));
export async function loadAuctions(contract) {
  const count = Number(await contract.auctionCount());
  const rows = [];
  for (let id = count; id >= 1; id--) {
    const a = await contract.getAuction(id);
    const c = await contract.cards(a.cardId);
    rows.push({id, auction:a, card:c});
  }
  return rows;
}
