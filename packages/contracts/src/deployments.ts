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

/** Live Apothem deployment (2026-09-09). */
export const deployment51: DeploymentAddresses = {
  chainId: 51,
  deployedAt: 1788966270,
  startBlock: 86550059,
  systemAccess: "0xD56B1D909c98122aD5A11F94017a7cbc7246aEAB",
  votingEscrow: "0x4255B31A1Fcb7F5Db498c0FdBfeCE7736bc09C06",
  feeDistributor: "0x25951a03E06348EeD4bF20CfeFcaE67135B6C0E1",
  feeDistributorImpl: "0x9C34946BC18Cf3dAbd7125a504A9Afa7e87FbEC8",
  revenueRegistry: "0x9b8993Afe26B19b3a33774Bd708BA8E637fBF2ED",
  revenueRegistryImpl: "0x423A0905262d42413a24d810C2e681458ed8db7a",
  zapDepositor: "0x5C1cb9BCA16C35E5b6C82e13891D11130b698CF1",
  veVotesAdapter: "0x1d19269D30e945Ed9e1ED9A0BC5706aa4CDd6d3c",
  wxdc: APOTHEM_WXDC,
  usdc: "0x0A9f7e55493058f69DB3Fc2a0E27CFA13C8dAC1F",
  feeSplitter: "0x71dE2A8004650b18F726204bc64b2AA59794f668",
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
