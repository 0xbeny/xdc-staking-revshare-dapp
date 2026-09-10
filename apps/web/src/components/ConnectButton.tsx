"use client";

import { usePrivy } from "@privy-io/react-auth";
import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { shortAddress } from "@/lib/format";
import { getConfiguredChainId, getAppChain } from "@/lib/contracts";
import { privyEnabled } from "@/lib/privy";
import styles from "./ConnectButton.module.css";

export function ConnectButton() {
  return privyEnabled ? <PrivyConnectButton /> : <LegacyConnectButton />;
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
 * Privy path: one modal for email, socials, embedded wallets, browser
 * extensions, and mobile wallets via WalletConnect. Address/chain state
 * still flows through wagmi (via @privy-io/wagmi).
 */
function PrivyConnectButton() {
  const { ready, authenticated, login, logout } = usePrivy();
  const { address } = useAccount();
  const appChain = getAppChain();

  const wrongNetwork = useWrongNetworkButton();
  if (wrongNetwork) return wrongNetwork;

  if (authenticated && address) {
    return (
      <div className={styles.wrap}>
        <span className={styles.chain}>{appChain.name}</span>
        <button
          type="button"
          className={`${styles.btn} ${styles.secondary}`}
          onClick={() => logout()}
          title="Log out"
        >
          <span className={styles.addr}>{shortAddress(address)}</span>
        </button>
      </div>
    );
  }

  if (authenticated && !address) {
    // Logged in; embedded/external wallet still attaching to wagmi.
    return (
      <button type="button" className={`${styles.btn} ${styles.primary}`} disabled>
        Connecting…
      </button>
    );
  }

  return (
    <button
      type="button"
      className={`${styles.btn} ${styles.primary}`}
      disabled={!ready}
      onClick={() => login()}
    >
      {ready ? "Sign in" : "Loading…"}
    </button>
  );
}

/** Fallback when NEXT_PUBLIC_PRIVY_APP_ID is not set: injected + WalletConnect. */
function LegacyConnectButton() {
  const { address, isConnected } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const expected = getConfiguredChainId();
  const appChain = getAppChain();

  const wrongNetwork = useWrongNetworkButton();
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

  const connector = connectors[0];

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
