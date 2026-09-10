"use client";

import type { Address } from "viem";
import { explorerAddressUrl } from "@/lib/contracts";
import { shortAddress } from "@/lib/roles";
import styles from "./AddressLink.module.css";

type Props = {
  address: Address | string;
  chainId: number;
  label?: string;
  mono?: boolean;
};

export function AddressLink({ address, chainId, label, mono = true }: Props) {
  const href = explorerAddressUrl(chainId, address);
  return (
    <a
      className={`${styles.link} ${mono ? styles.mono : ""}`}
      href={href}
      target="_blank"
      rel="noreferrer"
      title={address}
    >
      {label ?? shortAddress(address)}
      <span className={styles.ext} aria-hidden>
        ↗
      </span>
    </a>
  );
}
