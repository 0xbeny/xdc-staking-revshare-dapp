"use client";

import { abis, FeeSplitterBytecode, PushAdapterBytecode } from "@vexdc/contracts";
import { useEffect, useMemo, useState } from "react";
import type { Address, Hex } from "viem";
import { getAddress, isAddress } from "viem";
import {
  useAccount,
  useDeployContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { AddressLink } from "@/components/AddressLink";
import { Reveal } from "@/components/Reveal";
import { StatusPill } from "@/components/StatusPill";
import { contractsReady, getContractsState } from "@/lib/contracts";
import { useCorrectChain } from "@/lib/useCorrectChain";
import styles from "./IntegrateForm.module.css";

type AdapterKind = "FeeSplitter" | "PushAdapter";

function TxStatus({
  hash,
  isPending,
  isConfirming,
  isSuccess,
  error,
}: {
  hash?: Hex | undefined;
  isPending: boolean;
  isConfirming: boolean;
  isSuccess: boolean;
  error: Error | null;
}) {
  if (error) return <p className={styles.err}>{error.message.slice(0, 180)}</p>;
  if (isPending) return <p className={styles.muted}>Confirm in wallet…</p>;
  if (isConfirming) return <p className={styles.muted}>Confirming {hash?.slice(0, 10)}…</p>;
  if (isSuccess) return <p className={styles.ok}>Adapter deployed.</p>;
  return null;
}

export function IntegrateForm() {
  const state = getContractsState();
  const ready = contractsReady(state);
  const d = state.deployment;
  const chainId = state.chainId;
  const { address, isConnected } = useAccount();
  const { onExpectedChain } = useCorrectChain();

  const [kind, setKind] = useState<AdapterKind>("FeeSplitter");
  const [committedBps, setCommittedBps] = useState("3000");
  const [dappTreasury, setDappTreasury] = useState("");
  const [source, setSource] = useState("");
  const [tokenWxdc, setTokenWxdc] = useState(true);
  const [tokenUsdc, setTokenUsdc] = useState(!!d.usdc);
  const [extraTokens, setExtraTokens] = useState("");
  const [copied, setCopied] = useState(false);
  const [prefilled, setPrefilled] = useState(false);

  useEffect(() => {
    if (!address || prefilled) return;
    setDappTreasury((prev) => prev || address);
    setSource((prev) => prev || address);
    setPrefilled(true);
  }, [address, prefilled]);

  const rewardTokens = useMemo(() => {
    const list: Address[] = [];
    if (tokenWxdc && isAddress(d.wxdc)) list.push(getAddress(d.wxdc));
    if (tokenUsdc && d.usdc && isAddress(d.usdc)) list.push(getAddress(d.usdc));
    for (const part of extraTokens.split(/[\s,]+/)) {
      if (isAddress(part)) list.push(getAddress(part));
    }
    return [...new Set(list.map((a) => a.toLowerCase()))].map((a) => getAddress(a));
  }, [tokenWxdc, tokenUsdc, extraTokens, d.wxdc, d.usdc]);

  const bpsNum = Number(committedBps);
  const bpsOk = Number.isInteger(bpsNum) && bpsNum > 0 && bpsNum <= 10_000;
  const treasuryOk = isAddress(dappTreasury);
  const sourceOk = kind === "FeeSplitter" || isAddress(source);
  const canDeploy =
    ready &&
    isConnected &&
    onExpectedChain &&
    treasuryOk &&
    sourceOk &&
    bpsOk &&
    rewardTokens.length > 0;

  const { deployContract, data: hash, isPending, error, reset } = useDeployContract();
  const {
    data: receipt,
    isLoading: isConfirming,
    isSuccess,
  } = useWaitForTransactionReceipt({ hash });

  const deployedAddress = receipt?.contractAddress as Address | undefined;

  useEffect(() => {
    if (isSuccess) {
      const t = setTimeout(() => reset(), 12_000);
      return () => clearTimeout(t);
    }
  }, [isSuccess, reset]);

  async function copyAddress() {
    if (!deployedAddress) return;
    await navigator.clipboard.writeText(deployedAddress);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  function onDeploy() {
    if (!canDeploy || !treasuryOk) return;
    const distributor = d.feeDistributor;
    const treasury = getAddress(dappTreasury);
    // FeeSplitter SOURCE is unused at skim-time; use treasury as the dApp identity.
    const sourceAddr =
      kind === "PushAdapter" && isAddress(source) ? getAddress(source) : treasury;
    const args = [
      sourceAddr,
      distributor,
      treasury,
      bpsNum,
      rewardTokens,
    ] as const;

    if (kind === "FeeSplitter") {
      deployContract({
        abi: abis.FeeSplitter,
        bytecode: FeeSplitterBytecode as Hex,
        args,
      });
    } else {
      deployContract({
        abi: abis.PushAdapter,
        bytecode: PushAdapterBytecode as Hex,
        args,
      });
    }
  }

  if (!ready) {
    return <p className={styles.banner}>Contracts not live on this chain.</p>;
  }

  return (
    <div className={styles.wrap}>
      <Reveal className={styles.intro} delay={0.02}>
        <div>
          <h2 className={styles.h2}>Deploy an approved adapter</h2>
          <p className={styles.hint}>
            Deploys immutable Mode B FeeSplitter (default) or Mode A PushAdapter from your wallet.
            Distributor is fixed to this deployment. After deploy, send the address to the veXDC
            registry admin for whitelist — registration is not automatic.
          </p>
        </div>
        <StatusPill tone="muted">
          Distributor <AddressLink address={d.feeDistributor} chainId={chainId} />
        </StatusPill>
      </Reveal>

      <Reveal delay={0.06}>
        <article className={styles.card}>
          <fieldset className={styles.fieldset} disabled={!isConnected || !onExpectedChain}>
            {!isConnected ? (
              <p className={styles.muted}>Connect a wallet to deploy.</p>
            ) : !onExpectedChain ? (
              <p className={styles.err}>Switch to the configured chain before deploying.</p>
            ) : null}

            <label className={styles.label}>
              Model
              <select
                className={styles.input}
                value={kind}
                onChange={(e) => setKind(e.target.value as AdapterKind)}
              >
                <option value="FeeSplitter">B — FeeSplitter (default)</option>
                <option value="PushAdapter">A — PushAdapter</option>
              </select>
            </label>

            <label className={styles.label}>
              Committed bps
              <input
                className={styles.input}
                value={committedBps}
                onChange={(e) => setCommittedBps(e.target.value)}
                inputMode="numeric"
              />
            </label>
            <p className={styles.hint}>
              Share of skimmed revenue sent to lockers (1–10000). Example: 3000 = 30%.
            </p>

            <label className={styles.label}>
              dApp treasury
              <input
                className={styles.input}
                value={dappTreasury}
                onChange={(e) => setDappTreasury(e.target.value)}
                placeholder="0x…"
              />
            </label>
            <p className={styles.hint}>Receives the uncommitted remainder on each skim.</p>

            {kind === "PushAdapter" ? (
              <>
                <label className={styles.label}>
                  Source (may call commitRevenue)
                  <input
                    className={styles.input}
                    value={source}
                    onChange={(e) => setSource(e.target.value)}
                    placeholder="0x…"
                  />
                </label>
                <p className={styles.hint}>Only this address can push committed revenue.</p>
              </>
            ) : null}

            <div className={styles.tokenBlock}>
              <span className={styles.tokenTitle}>Reward tokens</span>
              <label className={styles.check}>
                <input
                  type="checkbox"
                  checked={tokenWxdc}
                  onChange={(e) => setTokenWxdc(e.target.checked)}
                />
                WXDC <span className={styles.mono}>{d.wxdc}</span>
              </label>
              {d.usdc ? (
                <label className={styles.check}>
                  <input
                    type="checkbox"
                    checked={tokenUsdc}
                    onChange={(e) => setTokenUsdc(e.target.checked)}
                  />
                  USDC <span className={styles.mono}>{d.usdc}</span>
                </label>
              ) : (
                <p className={styles.muted}>No USDC in deployment — add via extra tokens if needed.</p>
              )}
              <label className={styles.label}>
                Extra tokens (comma-separated)
                <input
                  className={styles.input}
                  value={extraTokens}
                  onChange={(e) => setExtraTokens(e.target.value)}
                  placeholder="0x…"
                />
              </label>
            </div>

            <button
              type="button"
              className={styles.primaryBtn}
              disabled={!canDeploy || isPending || isConfirming}
              onClick={onDeploy}
            >
              Deploy {kind}
            </button>

            <TxStatus
              hash={hash}
              isPending={isPending}
              isConfirming={isConfirming}
              isSuccess={isSuccess}
              error={error as Error | null}
            />
          </fieldset>
        </article>
      </Reveal>

      {deployedAddress ? (
        <Reveal delay={0.1}>
          <article className={styles.success}>
            <h3 className={styles.h3}>Adapter ready</h3>
            <div className={styles.successRow}>
              <AddressLink address={deployedAddress} chainId={chainId} />
              <button type="button" className={styles.secondaryBtn} onClick={copyAddress}>
                {copied ? "Copied" : "Copy address"}
              </button>
            </div>
            <ol className={styles.checklist}>
              <li>Point your dApp fee receiver (or push flow) at this adapter.</li>
              <li>Send the address to the veXDC registry admin and wait for whitelist.</li>
              <li>
                After registration, {kind === "FeeSplitter" ? "call skim(token)" : "call commitRevenue"}{" "}
                — until then notifyRevenue reverts with NotAnActiveAdapter.
              </li>
            </ol>
            <p className={styles.hint}>
              Mode {kind === "FeeSplitter" ? "B (SPLITTER)" : "A (PUSH)"} · {committedBps} bps.
            </p>
          </article>
        </Reveal>
      ) : null}
    </div>
  );
}
