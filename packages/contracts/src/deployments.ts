import type { Address, DeploymentAddresses } from "./types.js";

export const XDC_MAINNET = {
  id: 50,
  name: "XDC Network",
  nativeCurrency: { name: "XDC", symbol: "XDC", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://rpc.xinfin.network"] },
  },
  blockExplorers: {
    default: { name: "XDCScan", url: "https://xdcscan.com" },
  },
} as const;

export const XDC_APOTHEM = {
  id: 51,
  name: "XDC Apothem",
  nativeCurrency: { name: "TXDC", symbol: "TXDC", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://rpc.apothem.network", "https://erpc.apothem.network"] },
  },
  blockExplorers: {
    default: { name: "XDCScan Apothem", url: "https://testnet.xdcscan.com" },
  },
  testnet: true,
} as const;

/** Canonical Apothem WXDC (deposit/withdraw). */
export const APOTHEM_WXDC =
  "0x56408DC41E35d3E8E92A16bc94787438df9387a1" as const satisfies Address;

/** Canonical mainnet WXDC — verify before mainnet launch. */
export const MAINNET_WXDC =
  "0x951857744785E80e2De051c32EE7b25f9c458C42" as const satisfies Address;

const ZERO = "0x0000000000000000000000000000000000000000" as const satisfies Address;

/** Live Apothem deployment (2026-09-10).
 * After a full Apothem redeploy (e.g. stakingCap escrow), replace this object from
 * `deployments/51.json` produced by `make deploy-apothem` — do not invent addresses.
 */
export const deployment51: DeploymentAddresses = {
  chainId: 51,
  deployedAt: 1789035576,
  startBlock: 86585078,
  systemAccess: "0x5F16a238a3ACCFAD02Dd3C51BCd2696397256222",
  votingEscrow: "0x159444CFDB6CEbb5d6924833A0F56Cc5231Dae50",
  feeDistributor: "0x5BD90bFc4943e12Df81A9a1F03B344689481237E",
  feeDistributorImpl: "0x116FE1C8c938072f6Eac77297CBFE0AAa4615acf",
  revenueRegistry: "0xc34bD940313529E1239694F4E6290049F99322eA",
  revenueRegistryImpl: "0x83C5fed1eCCBb4981b735Dbf79e191BF16c65dA9",
  zapDepositor: "0x589173ed591aDcb3Ed373032b03CC7580e4cE7eD",
  veVotesAdapter: "0xB83F2fc7b784681654Aed11A7195bbe00663Ba5C",
  wxdc: APOTHEM_WXDC,
  usdc: "0x0A9f7e55493058f69DB3Fc2a0E27CFA13C8dAC1F",
  feeSplitter: "0xeeeb530EBaBB698386fDaf21449CFdCBC56215b5",
  timelock: "0x2B940B045DF358557f04Ecb176da796d412cC1ED",
  guardian: "0x2B940B045DF358557f04Ecb176da796d412cC1ED",
  treasury: "0x0cc6b0c5b944a28D817Ef0D3f3183c25582A62b5",
  keeper: "0x2B940B045DF358557f04Ecb176da796d412cC1ED",
};

export const deployment50: DeploymentAddresses = {
  chainId: 50,
  deployedAt: 0,
  systemAccess: ZERO,
  votingEscrow: ZERO,
  feeDistributor: ZERO,
  feeDistributorImpl: ZERO,
  revenueRegistry: ZERO,
  revenueRegistryImpl: ZERO,
  zapDepositor: ZERO,
  veVotesAdapter: ZERO,
  wxdc: MAINNET_WXDC,
  timelock: ZERO,
  guardian: ZERO,
  treasury: ZERO,
  keeper: ZERO,
  startBlock: 0,
};

function isLive(d: DeploymentAddresses): boolean {
  return d.votingEscrow !== ZERO && d.deployedAt > 0;
}

export function getDeployment(chainId: number): DeploymentAddresses | null {
  if (chainId === 51) return isLive(deployment51) ? deployment51 : null;
  if (chainId === 50) return isLive(deployment50) ? deployment50 : null;
  return null;
}

export function requireDeployment(chainId: number): DeploymentAddresses {
  const d = getDeployment(chainId);
  if (!d) {
    throw new Error(
      `No live deployment for chain ${chainId}. Run make deploy-apothem and update packages/contracts/src/deployments.ts (and deployments/${chainId}.json).`,
    );
  }
  return d;
}
