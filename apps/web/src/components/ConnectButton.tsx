"use client";

import { usePrivy, useWallets } from "@privy-io/react-auth";
import { useEffect, useState } from "react";
import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import type { Address } from "viem";
import { shortAddress } from "@/lib/format";
import { getConfiguredChainId, getAppChain } from "@/lib/contracts";
import { privyEnabled } from "@/lib/privy";
import { registerWalletLogin } from "@/lib/walletGate";
import styles from "./ConnectButton.module.css";

export function ConnectButton() {
  return privyEnabled ? <PrivyConnectButton /> : <LegacyConnectButton />;
}

function IdleButton({ label }: { label: string }) {
  return (
    <button type="button" className={`${styles.btn} ${styles.primary}`} disabled>
      {label}
    </button>
  );
}

/** Shared "wrong network" prompt. Returns null when the network is correct. */
function useWrongNetworkButton() {
  const { isConnected, chainId } = useAccount();
  const { switchChain, isPending: switching } = useSwitchChain();
  const expected = getConfiguredChainId();
  const appChain = getAppChain();

  if (!isConnected || chainId === undefined || chainId === expected) return null;

  return (
    <button
      type="button"
      className={`${styles.btn} ${styles.warn}`}
      disabled={switching}
      onClick={() => switchChain({ chainId: expected })}
    >
      Switch to {appChain.name}
    </button>
  );
}

/**
 * Privy path: one modal for email OTP, embedded wallets, browser
 * extensions, and mobile wallets via WalletConnect. Address/chain state
 * still flows through wagmi (via @privy-io/wagmi).
 */
function PrivyConnectButton() {
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);
  const { ready, authenticated, login, logout, connectWallet } = usePrivy();
  const { wallets } = useWallets();
  const { address: wagmiAddress } = useAccount();
  const appChain = getAppChain();
  const wrongNetwork = useWrongNetworkButton();
  const privyAddress = wallets.find((w) => w.address)?.address as Address | undefined;
  const address = wagmiAddress ?? privyAddress;

  useEffect(() => {
    if (!ready) return;
    registerWalletLogin(() => {
      if (authenticated && !address) {
        void connectWallet();
        return;
      }
      void login();
    });
    return () => registerWalletLogin(null);
  }, [ready, login, connectWallet, authenticated, address]);

  // First paint must match SSR (no wallet session on the server).
  if (!mounted) return <IdleButton label="Connect wallet" />;
  if (wrongNetwork) return wrongNetwork;

  if (authenticated && address) {
    return (
      <div className={styles.wrap}>
        <span className={styles.chain}>{appChain.name}</span>
        <button
          type="button"
          className={`${styles.btn} ${styles.secondary}`}
          onClick={() => void logout()}
          title="Log out"
        >
          <span className={styles.addr}>{shortAddress(address)}</span>
        </button>
      </div>
    );
  }

  // Session exists but no wallet yet (embedded create lag, or wallet not linked).
  if (authenticated && !address) {
    return (
      <div className={styles.wrap}>
        <button
          type="button"
          className={`${styles.btn} ${styles.primary}`}
          disabled={!ready}
          onClick={() => void connectWallet()}
        >
          Connect wallet
        </button>
        <button
          type="button"
          className={`${styles.btn} ${styles.secondary}`}
          onClick={() => void logout()}
        >
          Sign out
        </button>
      </div>
    );
  }

  return (
    <button
      type="button"
      className={`${styles.btn} ${styles.primary}`}
      disabled={!ready}
      onClick={() => {
        void login();
      }}
    >
      {ready ? "Connect wallet" : "Loading…"}
    </button>
  );
}

/** Fallback when NEXT_PUBLIC_PRIVY_APP_ID is not set: injected + WalletConnect. */
function LegacyConnectButton() {
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);
  const { address, isConnected } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const expected = getConfiguredChainId();
  const appChain = getAppChain();
  const wrongNetwork = useWrongNetworkButton();
  const injected = connectors[0];

  useEffect(() => {
    if (!injected) return;
    registerWalletLogin(() => connect({ connector: injected, chainId: expected }));
    return () => registerWalletLogin(null);
  }, [injected, connect, expected]);

  if (!mounted) return <IdleButton label="Connect wallet" />;
  if (wrongNetwork) return wrongNetwork;

  if (isConnected && address) {
    return (
      <div className={styles.wrap}>
        <span className={styles.chain}>{appChain.name}</span>
        <button
          type="button"
          className={`${styles.btn} ${styles.secondary}`}
          onClick={() => disconnect()}
          title="Disconnect"
        >
          <span className={styles.addr}>{shortAddress(address)}</span>
        </button>
      </div>
    );
  }

  const connector = injected;

  return (
    <button
      type="button"
      className={`${styles.btn} ${styles.primary}`}
      disabled={isPending || !connector}
      onClick={() => {
        if (connector) connect({ connector, chainId: expected });
      }}
    >
      {isPending ? "Connecting…" : "Connect wallet"}
    </button>
  );
}
