import { keccak256, stringToHex, type Address, type Hex } from "viem";

export const ZERO_BYTES32 =
  "0x0000000000000000000000000000000000000000000000000000000000000000" as const satisfies Hex;

export const ROLES = {
  DEFAULT_ADMIN: ZERO_BYTES32,
  UPGRADER: keccak256(stringToHex("UPGRADER_ROLE")),
  PAUSER: keccak256(stringToHex("PAUSER_ROLE")),
  KEEPER: keccak256(stringToHex("KEEPER_ROLE")),
  REGISTRY_ADMIN: keccak256(stringToHex("REGISTRY_ADMIN_ROLE")),
  REPORTER: keccak256(stringToHex("REPORTER_ROLE")),
} as const satisfies Record<string, Hex>;

export type RoleKey = keyof typeof ROLES;

export const ROLE_META: Record<
  RoleKey,
  { label: string; description: string; typicalTargets: string[] }
> = {
  DEFAULT_ADMIN: {
    label: "Default admin",
    description: "Unpause, add reward tokens, one-shot wiring.",
    typicalTargets: ["FeeDistributor", "RevenueRegistry"],
  },
  UPGRADER: {
    label: "Upgrader",
    description: "Authorise UUPS upgrades on periphery proxies.",
    typicalTargets: ["FeeDistributor", "RevenueRegistry"],
  },
  PAUSER: {
    label: "Pauser",
    description: "Emergency pause on the distributor (not the escrow).",
    typicalTargets: ["FeeDistributor"],
  },
  KEEPER: {
    label: "Keeper",
    description: "batchKeepAtMaxLock and batchCompound windows.",
    typicalTargets: ["FeeDistributor"],
  },
  REGISTRY_ADMIN: {
    label: "Registry admin",
    description: "Register, deactivate, reactivate adapters; update terms.",
    typicalTargets: ["RevenueRegistry"],
  },
  REPORTER: {
    label: "Reporter",
    description: "Mode C Attestor revenue posts.",
    typicalTargets: ["Attestor"],
  },
};

export const ADAPTER_MODES = [
  { value: 1, label: "PUSH" },
  { value: 2, label: "SPLITTER" },
  { value: 3, label: "PULL_SAFE" },
  { value: 4, label: "ZODIAC_SAFE" },
  { value: 5, label: "ATTESTATION" },
] as const;

export const TIER_OPTIONS = [
  { value: 0, label: "NONE" },
  { value: 1, label: "CUSTODIAN" },
  { value: 2, label: "WRAPPER" },
] as const;

export function shortAddress(address: Address | string, size = 4): string {
  if (!address || address.length < 10) return address;
  return `${address.slice(0, 2 + size)}…${address.slice(-size)}`;
}

export type TargetKey = "feeDistributor" | "revenueRegistry" | "systemAccess";

export const TARGET_LABEL: Record<TargetKey, string> = {
  feeDistributor: "FeeDistributor",
  revenueRegistry: "RevenueRegistry",
  systemAccess: "SystemAccess (hub)",
};
