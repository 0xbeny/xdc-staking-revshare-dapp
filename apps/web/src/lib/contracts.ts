import {
  XDC_APOTHEM,
  XDC_MAINNET,
  deployment50,
  deployment51,
  getDeployment,
  type DeploymentAddresses,
} from "@vexdc/contracts";
import { defineChain, type Address, type Chain } from "viem";

const ZERO = "0x0000000000000000000000000000000000000000" as const satisfies Address;

export const WEEK_SECONDS = 604_800;
export const MIN_LOCK_WEEKS = 1;
export const MAX_LOCK_WEEKS = 104;

export function getConfiguredChainId(): number {
  const raw = process.env.NEXT_PUBLIC_CHAIN_ID ?? "51";
  const id = Number(raw);
  return Number.isFinite(id) ? id : 51;
}

export function getRpcUrl(): string {
  return (
    process.env.NEXT_PUBLIC_RPC_URL ??
    (getConfiguredChainId() === 50
      ? XDC_MAINNET.rpcUrls.default.http[0]!
      : XDC_APOTHEM.rpcUrls.default.http[0]!)
  );
}

export const xdcApothem = defineChain({
  id: XDC_APOTHEM.id,
  name: XDC_APOTHEM.name,
  nativeCurrency: XDC_APOTHEM.nativeCurrency,
  rpcUrls: {
    default: { http: [getRpcUrl()] },
  },
  blockExplorers: XDC_APOTHEM.blockExplorers,
  testnet: true,
});

export const xdcMainnet = defineChain({
  id: XDC_MAINNET.id,
  name: XDC_MAINNET.name,
  nativeCurrency: XDC_MAINNET.nativeCurrency,
  rpcUrls: {
    default: { http: [getRpcUrl()] },
  },
  blockExplorers: XDC_MAINNET.blockExplorers,
});

export function getAppChain(): Chain {
  return getConfiguredChainId() === 50 ? xdcMainnet : xdcApothem;
}

export type ContractsState = {
  chainId: number;
  isLive: boolean;
  deployment: DeploymentAddresses;
};

function fallbackDeployment(chainId: number): DeploymentAddresses {
  return chainId === 50 ? deployment50 : deployment51;
}

export function getContractsState(chainId = getConfiguredChainId()): ContractsState {
  const live = getDeployment(chainId);
  if (live) {
    return { chainId, isLive: true, deployment: live };
  }
  return { chainId, isLive: false, deployment: fallbackDeployment(chainId) };
}

export function isZeroAddress(address: Address | undefined): boolean {
  return !address || address.toLowerCase() === ZERO.toLowerCase();
}

export function contractsReady(state: ContractsState): boolean {
  return (
    state.isLive &&
    !isZeroAddress(state.deployment.zapDepositor) &&
    !isZeroAddress(state.deployment.votingEscrow) &&
    !isZeroAddress(state.deployment.feeDistributor)
  );
}

export function weeksToDuration(weeks: number): bigint {
  const clamped = Math.min(MAX_LOCK_WEEKS, Math.max(MIN_LOCK_WEEKS, Math.floor(weeks)));
  return BigInt(clamped) * BigInt(WEEK_SECONDS);
}

/** Matches `EpochTime.ceilWeek` — unlocks always land on Thursday 00:00 UTC. */
export function ceilWeek(timestampSec: number): number {
  return Math.floor((timestampSec + WEEK_SECONDS - 1) / WEEK_SECONDS) * WEEK_SECONDS;
}

/** Unlock timestamp the escrow will store for a `duration = weeks` lock started now. */
export function unlockAtWeeks(weeks: number, nowSec = Math.floor(Date.now() / 1000)): number {
  const duration = Number(weeksToDuration(weeks));
  return ceilWeek(nowSec + duration);
}

export function explorerAddressUrl(chainId: number, address: string): string {
  const base =
    chainId === 50
      ? XDC_MAINNET.blockExplorers.default.url
      : XDC_APOTHEM.blockExplorers.default.url;
  return `${base}/address/${address}`;
}
