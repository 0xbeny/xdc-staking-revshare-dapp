"use client";

import { http, injected, createConfig as createWagmiConfig } from "wagmi";
// Alias (see next.config.ts) — deep WalletConnect import, not the connectors barrel.
import { walletConnect } from "@vexdc/walletconnect";
import { createConfig as createPrivyWagmiConfig } from "@privy-io/wagmi";
import {
  getAppChain,
  getConfiguredChainId,
  getRpcUrl,
  xdcApothem,
  xdcMainnet,
} from "./contracts";
import { privyEnabled } from "./privy";

const XDC_APOTHEM_FALLBACK = "https://rpc.apothem.network";
const XDC_MAINNET_FALLBACK = "https://rpc.xinfin.network";

const projectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ?? "";

const configuredId = getConfiguredChainId();
const chains =
  configuredId === 50 ? ([xdcMainnet, xdcApothem] as const) : ([xdcApothem, xdcMainnet] as const);

const transports = {
  [xdcApothem.id]: http(configuredId === 51 ? getRpcUrl() : XDC_APOTHEM_FALLBACK),
  [xdcMainnet.id]: http(configuredId === 50 ? getRpcUrl() : XDC_MAINNET_FALLBACK),
};

// Legacy connectors — only used when Privy is not configured. With Privy,
// external wallets (injected, WalletConnect, mobile) are managed by its modal
// and surfaced to wagmi through @privy-io/wagmi.
const legacyConnectors = [
  injected({ shimDisconnect: true }),
  ...(projectId
    ? [
        walletConnect({
          projectId,
          showQrModal: true,
          metadata: {
            name: "veXDC",
            description: "Lock XDC. Earn protocol revenue.",
            url: "https://vexdc.xyz",
            icons: [],
          },
        }),
      ]
    : []),
];

export const wagmiConfig = privyEnabled
  ? createPrivyWagmiConfig({ chains, transports, ssr: true })
  : createWagmiConfig({ chains, connectors: legacyConnectors, transports, ssr: true });

export const chain = getAppChain();
