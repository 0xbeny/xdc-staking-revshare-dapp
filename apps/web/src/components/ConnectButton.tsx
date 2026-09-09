"use client";

import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { shortAddress } from "@/lib/format";
import { getConfiguredChainId, getAppChain } from "@/lib/contracts";
import styles from "./ConnectButton.module.css";

export function ConnectButton() {
  const { address, isConnected, chainId } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain, isPending: switching } = useSwitchChain();
  const expected = getConfiguredChainId();
  const appChain = getAppChain();
  const wrongNetwork = isConnected && chainId !== undefined && chainId !== expected;

  if (wrongNetwork) {
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
