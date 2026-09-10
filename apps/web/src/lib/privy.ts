"use client";

import type { PrivyClientConfig } from "@privy-io/react-auth";
import type { Chain } from "viem";
import { getAppChain, xdcApothem, xdcMainnet } from "./contracts";

/**
 * Privy's Chain type (exactOptionalPropertyTypes) rejects viem's looser
 * optionals, so build a minimal, fully-populated chain object explicitly.
 */
function toPrivyChain(chain: Chain) {
  return {
    id: chain.id,
    name: chain.name,
    nativeCurrency: chain.nativeCurrency,
    rpcUrls: { default: { http: [...chain.rpcUrls.default.http] } },
    blockExplorers: {
      default: {
        name: chain.blockExplorers?.default.name ?? chain.name,
        url: chain.blockExplorers?.default.url ?? "",
      },
    },
    testnet: chain.testnet ?? false,
  };
}

/**
 * Privy is enabled when an app id is configured. Without it the app falls
 * back to plain wagmi (injected + WalletConnect) so local dev never breaks.
 * Create an app at https://dashboard.privy.io and set NEXT_PUBLIC_PRIVY_APP_ID.
 */
export const privyAppId = process.env.NEXT_PUBLIC_PRIVY_APP_ID ?? "";
export const privyEnabled = privyAppId.length > 0;

const walletConnectProjectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ?? "";

export const privyConfig: PrivyClientConfig = {
  // Email + socials + external wallets in one modal.
  loginMethods: ["email", "google", "twitter", "discord", "wallet"],
  appearance: {
    theme: "dark",
    accentColor: "#2dd4bf",
    // Wallet picker: detected extensions first, then the majors; WalletConnect
    // covers every mobile wallet via QR / deep link.
    walletList: [
      "detected_wallets",
      "metamask",
      "coinbase_wallet",
      "rainbow",
      "okx_wallet",
      "wallet_connect",
    ],
    showWalletLoginFirst: false,
  },
  // Users signing in with email/social get an embedded wallet automatically.
  embeddedWallets: {
    ethereum: { createOnLogin: "users-without-wallets" },
  },
  defaultChain: toPrivyChain(getAppChain()),
  supportedChains: [toPrivyChain(xdcApothem), toPrivyChain(xdcMainnet)],
  // Enables WalletConnect (QR + mobile deep links) inside Privy's modal.
  ...(walletConnectProjectId ? { walletConnectCloudProjectId: walletConnectProjectId } : {}),
};
