"use client";

import { createConfig, http, injected } from "wagmi";
// Alias (see next.config.ts) — deep WalletConnect import, not the connectors barrel.
import { walletConnect } from "@vexdc/walletconnect";
import {
  getAppChain,
  getConfiguredChainId,
  getRpcUrl,
  xdcApothem,
  xdcMainnet,
} from "./contracts";

const XDC_APOTHEM_FALLBACK = "https://rpc.apothem.network";
const XDC_MAINNET_FALLBACK = "https://rpc.xinfin.network";

const projectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ?? "";

const connectors = [
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

const configuredId = getConfiguredChainId();
const chains =
  configuredId === 50 ? ([xdcMainnet, xdcApothem] as const) : ([xdcApothem, xdcMainnet] as const);

export const wagmiConfig = createConfig({
  chains,
  connectors,
  transports: {
    [xdcApothem.id]: http(configuredId === 51 ? getRpcUrl() : XDC_APOTHEM_FALLBACK),
    [xdcMainnet.id]: http(configuredId === 50 ? getRpcUrl() : XDC_MAINNET_FALLBACK),
  },
  ssr: true,
});

export const chain = getAppChain();
