"use client";

import { useAccount } from "wagmi";
import { getConfiguredChainId } from "@/lib/contracts";

/** True when the wallet is on the app's configured chain (hard gate for writes). */
export function useCorrectChain(): {
  expectedChainId: number;
  chainId: number | undefined;
  onExpectedChain: boolean;
} {
  const expectedChainId = getConfiguredChainId();
  const { chainId } = useAccount();
  return {
    expectedChainId,
    chainId,
    onExpectedChain: chainId === expectedChainId,
  };
}
