"use client";

import { abis, committedFromSkim } from "@vexdc/contracts";
import { useEffect, useMemo, useState } from "react";
import type { Address, Hex } from "viem";
import { formatUnits, isAddress, parseUnits } from "viem";
import {
  useAccount,
  usePublicClient,
  useReadContract,
  useReadContracts,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import { AddressLink } from "@/components/AddressLink";
import { Reveal } from "@/components/Reveal";
import { RoleRoster } from "@/components/RoleRoster";
import { StatusPill } from "@/components/StatusPill";
import { contractsReady, getContractsState } from "@/lib/contracts";
import {
  ADAPTER_MODES,
  ROLE_META,
  ROLES,
  TIER_OPTIONS,
  type RoleKey,
  ZERO_BYTES32,
} from "@/lib/roles";
import styles from "./AdminActions.module.css";

/** Minimal MockERC20 surface used on Apothem for mint+skim rehearsals. */
const mockErc20Abi = [
  {
    type: "function",
    name: "mint",
    stateMutability: "nonpayable",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "decimals",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint8" }],
  },
] as const;

const adapterViewAbi = [
  {
    type: "function",
    name: "DISTRIBUTOR",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "address" }],
  },
  {
    type: "function",
    name: "COMMITTED_BPS",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint16" }],
  },
  {
    type: "function",
    name: "DAPP_TREASURY",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "address" }],
  },
  {
    type: "function",
    name: "SOURCE",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "address" }],
  },
] as const;

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
  if (isSuccess) return <p className={styles.ok}>Transaction confirmed.</p>;
  return null;
}

function ActionCard({
  title,
  description,
  allowed,
  need,
  children,
}: {
  title: string;
  description: string;
  allowed: boolean;
  need: string;
  children: React.ReactNode;
}) {
  return (
    <article className={`${styles.card} ${allowed ? "" : styles.cardLocked}`}>
      <header className={styles.cardHead}>
        <div>
          <h3 className={styles.h3}>{title}</h3>
          <p className={styles.desc}>{description}</p>
        </div>
        <StatusPill tone={allowed ? "ok" : "muted"}>{allowed ? "Authorized" : need}</StatusPill>
      </header>
      <fieldset disabled={!allowed} className={styles.fieldset}>
        {children}
      </fieldset>
    </article>
  );
}

function modeLabel(mode: number): string {
  return ADAPTER_MODES.find((m) => m.value === mode)?.label ?? `Mode ${mode}`;
}

type AdapterInfoRow = {
  dapp: Address;
  mode: number;
  committedBps: number;
  version: number;
  active: boolean;
  termsHash: Hex;
  registeredAt: bigint;
};

export function AdminActions() {
  const state = getContractsState();
  const ready = contractsReady(state);
  const d = state.deployment;
  const chainId = state.chainId;
  const { address, isConnected } = useAccount();
  const publicClient = usePublicClient();

  const { data: isPauser } = useReadContract({
    address: d.systemAccess,
    abi: abis.SystemAccess,
    functionName: "hasRole",
    args: [d.feeDistributor, ROLES.PAUSER, address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: ready && !!address },
  });
  const { data: isDistAdmin } = useReadContract({
    address: d.systemAccess,
    abi: abis.SystemAccess,
    functionName: "hasRole",
    args: [d.feeDistributor, ROLES.DEFAULT_ADMIN, address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: ready && !!address },
  });
  const { data: isRegistryAdmin } = useReadContract({
    address: d.systemAccess,
    abi: abis.SystemAccess,
    functionName: "hasRole",
    args: [d.revenueRegistry, ROLES.REGISTRY_ADMIN, address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: ready && !!address },
  });
  const { data: isHubAdmin } = useReadContract({
    address: d.systemAccess,
    abi: abis.SystemAccess,
    functionName: "hasRole",
    // OZ AccessControl hub admin (2-arg), not the per-target mapping.
    args: [ROLES.DEFAULT_ADMIN, address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: ready && !!address },
  });
  const { data: escrowTimelock } = useReadContract({
    address: d.votingEscrow,
    abi: abis.VotingEscrow,
    functionName: "timelock",
    query: { enabled: ready },
  });
  const { data: paused } = useReadContract({
    address: d.feeDistributor,
    abi: abis.FeeDistributor,
    functionName: "paused",
    query: { enabled: ready },
  });
  const { data: adapters, refetch: refetchAdapters } = useReadContract({
    address: d.revenueRegistry,
    abi: abis.RevenueRegistry,
    functionName: "allAdapters",
    query: { enabled: ready },
  });

  const adapterList = useMemo(
    () => ((adapters as Address[] | undefined) ?? []) as Address[],
    [adapters],
  );

  const adapterInfoContracts = useMemo(
    () =>
      adapterList.map((adapter) => ({
        address: d.revenueRegistry,
        abi: abis.RevenueRegistry,
        functionName: "adapterInfo" as const,
        args: [adapter] as const,
      })),
    [adapterList, d.revenueRegistry],
  );

  const { data: adapterInfos, refetch: refetchInfos } = useReadContracts({
    contracts: adapterInfoContracts,
    query: { enabled: ready && adapterList.length > 0 },
  });

  const isEscrowTimelock =
    !!address &&
    !!escrowTimelock &&
    address.toLowerCase() === (escrowTimelock as Address).toLowerCase();

  const yourRoles = useMemo(() => {
    const list: string[] = [];
    if (isPauser) list.push("Pauser");
    if (isDistAdmin) list.push("Distributor admin");
    if (isRegistryAdmin) list.push("Registry admin");
    if (isHubAdmin) list.push("Hub admin");
    if (isEscrowTimelock) list.push("Escrow timelock");
    return list;
  }, [isPauser, isDistAdmin, isRegistryAdmin, isHubAdmin, isEscrowTimelock]);

  const { writeContract, data: hash, isPending, error, reset } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  useEffect(() => {
    if (isSuccess) {
      void refetchAdapters();
      void refetchInfos();
      const t = setTimeout(() => reset(), 4000);
      return () => clearTimeout(t);
    }
  }, [isSuccess, reset, refetchAdapters, refetchInfos]);

  // Form state
  const [rewardToken, setRewardToken] = useState("");
  const [acceptToken, setAcceptToken] = useState<string>(d.wxdc);
  const [accepting, setAccepting] = useState(true);
  const [maxPenalty, setMaxPenalty] = useState("5000");
  const [splitBps, setSplitBps] = useState("2000");
  const [cooldownHrs, setCooldownHrs] = useState("24");
  const [tierAccount, setTierAccount] = useState("");
  const [tier, setTier] = useState(1);
  const [adapterAddr, setAdapterAddr] = useState("");
  const [adapterDapp, setAdapterDapp] = useState("");
  const [adapterMode, setAdapterMode] = useState(2);
  const [committedBps, setCommittedBps] = useState("2000");
  const [toggleAdapter, setToggleAdapter] = useState("");
  const [grantTarget, setGrantTarget] = useState<"feeDistributor" | "revenueRegistry">("feeDistributor");
  const [grantRole, setGrantRole] = useState<RoleKey>("KEEPER");
  const [grantAccount, setGrantAccount] = useState("");
  const [revokeTarget, setRevokeTarget] = useState<"feeDistributor" | "revenueRegistry">("feeDistributor");
  const [revokeRole, setRevokeRole] = useState<RoleKey>("KEEPER");
  const [revokeAccount, setRevokeAccount] = useState("");
  const [registerHint, setRegisterHint] = useState<string | null>(null);
  const [registerBlocking, setRegisterBlocking] = useState<string | null>(null);

  // Simulate revenue (Apothem / mock USDC)
  const [simAdapter, setSimAdapter] = useState("");
  const [simAmount, setSimAmount] = useState("1000");
  const [simStep, setSimStep] = useState<"idle" | "minted">("idle");
  const usdc = d.usdc;
  const showSimulate = chainId === 51 && !!usdc && isAddress(usdc);

  const splitterCandidates = useMemo(() => {
    if (!adapterInfos) return [] as Address[];
    return adapterList.filter((_, i) => {
      const row = adapterInfos[i]?.result as AdapterInfoRow | undefined;
      return row && Number(row.mode) === 2 && row.active;
    });
  }, [adapterList, adapterInfos]);

  const { data: simInfo } = useReadContract({
    address: d.revenueRegistry,
    abi: abis.RevenueRegistry,
    functionName: "adapterInfo",
    args: [isAddress(simAdapter) ? (simAdapter as Address) : "0x0000000000000000000000000000000000000000"],
    query: { enabled: ready && isAddress(simAdapter) },
  });

  const { data: usdcDecimals } = useReadContract({
    address: usdc,
    abi: mockErc20Abi,
    functionName: "decimals",
    query: { enabled: showSimulate && !!usdc },
  });

  const simBps = simInfo ? Number((simInfo as AdapterInfoRow).committedBps) : 0;
  const simAmountWei = useMemo(() => {
    try {
      return parseUnits(simAmount || "0", Number(usdcDecimals ?? 6));
    } catch {
      return 0n;
    }
  }, [simAmount, usdcDecimals]);
  const expectedCommitted =
    simBps > 0 && simAmountWei > 0n ? committedFromSkim(simAmountWei, simBps) : 0n;

  useEffect(() => {
    let cancelled = false;
    async function check() {
      setRegisterHint(null);
      setRegisterBlocking(null);
      if (!isAddress(adapterAddr) || !publicClient) return;
      const code = await publicClient.getBytecode({ address: adapterAddr as Address });
      if (cancelled) return;
      if (!code || code === "0x") {
        setRegisterBlocking("No contract code at adapter address.");
        return;
      }
      try {
        const [distributor, bps, treasury] = await Promise.all([
          publicClient.readContract({
            address: adapterAddr as Address,
            abi: adapterViewAbi,
            functionName: "DISTRIBUTOR",
          }),
          publicClient.readContract({
            address: adapterAddr as Address,
            abi: adapterViewAbi,
            functionName: "COMMITTED_BPS",
          }),
          publicClient.readContract({
            address: adapterAddr as Address,
            abi: adapterViewAbi,
            functionName: "DAPP_TREASURY",
          }),
        ]);
        if (cancelled) return;
        if ((distributor as Address).toLowerCase() !== d.feeDistributor.toLowerCase()) {
          setRegisterBlocking(
            `DISTRIBUTOR mismatch: adapter=${distributor}, expected=${d.feeDistributor}`,
          );
          return;
        }
        const formBps = Number(committedBps || "0");
        if (Number(bps) !== formBps) {
          setRegisterBlocking(
            `Committed bps mismatch: adapter immutable=${bps}, form=${formBps}`,
          );
          return;
        }
        setAdapterDapp((prev) => (prev || !isAddress(treasury as string) ? prev : (treasury as string)));
        const modeName = modeLabel(adapterMode);
        setRegisterHint(
          `On-chain checks OK (code, DISTRIBUTOR, COMMITTED_BPS=${bps}). Confirm mode ${modeName} matches the deployed adapter type.`,
        );
      } catch {
        if (!cancelled) {
          setRegisterHint(
            "Contract code present, but DISTRIBUTOR/COMMITTED_BPS not readable — verify mode/bps manually.",
          );
        }
      }
    }
    void check();
    return () => {
      cancelled = true;
    };
  }, [adapterAddr, adapterMode, committedBps, publicClient, d.feeDistributor]);

  if (!ready) {
    return <p className={styles.banner}>Contracts not live on this chain.</p>;
  }

  const targetAddress = (key: "feeDistributor" | "revenueRegistry") =>
    key === "feeDistributor" ? d.feeDistributor : d.revenueRegistry;

  const canRegister =
    isAddress(adapterAddr) &&
    isAddress(adapterDapp) &&
    !registerBlocking &&
    Number(committedBps || "0") > 0;

  return (
    <div className={styles.wrap}>
      <Reveal className={styles.identity} delay={0.02}>
        <div>
          <h2 className={styles.h2}>Connected authority</h2>
          <p className={styles.hint}>
            Actions unlock only when your wallet holds the required role. Wrong role → tx reverts.
          </p>
        </div>
        <div className={styles.identityMeta}>
          {!isConnected || !address ? (
            <StatusPill tone="warn">Connect wallet</StatusPill>
          ) : (
            <>
              <AddressLink address={address} chainId={chainId} />
              <div className={styles.pills}>
                {yourRoles.length === 0 ? (
                  <StatusPill tone="muted">No admin roles</StatusPill>
                ) : (
                  yourRoles.map((r) => (
                    <StatusPill key={r} tone="ok">
                      {r}
                    </StatusPill>
                  ))
                )}
              </div>
            </>
          )}
        </div>
        <StatusPill tone={paused ? "danger" : "ok"}>
          {paused ? "Paused" : "Live"}
        </StatusPill>
      </Reveal>

      <Reveal delay={0.04}>
        <RoleRoster />
      </Reveal>

      <div className={styles.grid}>
        <Reveal delay={0.06}>
          <ActionCard
            title="Pause / unpause"
            description="Guardian pauses the distributor. Timelock (DEFAULT_ADMIN) unpauses. Escrow exits stay available while paused."
            allowed={Boolean(isPauser || isDistAdmin)}
            need="Need PAUSER or DEFAULT_ADMIN"
          >
            <div className={styles.row}>
              <button
                type="button"
                className={styles.dangerBtn}
                disabled={!isPauser || !!paused}
                onClick={() =>
                  writeContract({
                    address: d.feeDistributor,
                    abi: abis.FeeDistributor,
                    functionName: "pause",
                  })
                }
              >
                Pause distributor
              </button>
              <button
                type="button"
                className={styles.primaryBtn}
                disabled={!isDistAdmin || !paused}
                onClick={() =>
                  writeContract({
                    address: d.feeDistributor,
                    abi: abis.FeeDistributor,
                    functionName: "unpause",
                  })
                }
              >
                Unpause
              </button>
            </div>
          </ActionCard>
        </Reveal>

        <Reveal delay={0.1}>
          <ActionCard
            title="Reward tokens"
            description="DEFAULT_ADMIN on FeeDistributor can add tokens and toggle acceptingRevenue."
            allowed={Boolean(isDistAdmin)}
            need="Need distributor DEFAULT_ADMIN"
          >
            <label className={styles.label}>
              Add reward token
              <input
                className={styles.input}
                placeholder="0x…"
                value={rewardToken}
                onChange={(e) => setRewardToken(e.target.value)}
              />
            </label>
            <button
              type="button"
              className={styles.primaryBtn}
              disabled={!isAddress(rewardToken)}
              onClick={() =>
                writeContract({
                  address: d.feeDistributor,
                  abi: abis.FeeDistributor,
                  functionName: "addRewardToken",
                  args: [rewardToken as Address],
                })
              }
            >
              Add token
            </button>
            <label className={styles.label}>
              Set accepting revenue
              <input
                className={styles.input}
                value={acceptToken}
                onChange={(e) => setAcceptToken(e.target.value)}
              />
            </label>
            <label className={styles.check}>
              <input
                type="checkbox"
                checked={accepting}
                onChange={(e) => setAccepting(e.target.checked)}
              />
              Accepting
            </label>
            <button
              type="button"
              className={styles.secondaryBtn}
              disabled={!isAddress(acceptToken)}
              onClick={() =>
                writeContract({
                  address: d.feeDistributor,
                  abi: abis.FeeDistributor,
                  functionName: "setAcceptingRevenue",
                  args: [acceptToken as Address, accepting],
                })
              }
            >
              Update accepting
            </button>
          </ActionCard>
        </Reveal>

        <Reveal delay={0.14}>
          <ActionCard
            title="Escrow parameters"
            description="Only the VotingEscrow timelock can tune penalty caps, split, cooldown, and custodian tiers."
            allowed={isEscrowTimelock}
            need="Need escrow timelock"
          >
            <div className={styles.row}>
              <label className={styles.label}>
                Max penalty bps
                <input
                  className={styles.input}
                  value={maxPenalty}
                  onChange={(e) => setMaxPenalty(e.target.value)}
                />
              </label>
              <button
                type="button"
                className={styles.secondaryBtn}
                onClick={() =>
                  writeContract({
                    address: d.votingEscrow,
                    abi: abis.VotingEscrow,
                    functionName: "setMaxPenaltyBps",
                    args: [BigInt(maxPenalty || "0")],
                  })
                }
              >
                Set max penalty
              </button>
            </div>
            <div className={styles.row}>
              <label className={styles.label}>
                Treasury split bps
                <input
                  className={styles.input}
                  value={splitBps}
                  onChange={(e) => setSplitBps(e.target.value)}
                />
              </label>
              <button
                type="button"
                className={styles.secondaryBtn}
                onClick={() =>
                  writeContract({
                    address: d.votingEscrow,
                    abi: abis.VotingEscrow,
                    functionName: "setPenaltySplitBps",
                    args: [BigInt(splitBps || "0")],
                  })
                }
              >
                Set split
              </button>
            </div>
            <div className={styles.row}>
              <label className={styles.label}>
                Cooldown (hours)
                <input
                  className={styles.input}
                  value={cooldownHrs}
                  onChange={(e) => setCooldownHrs(e.target.value)}
                />
              </label>
              <button
                type="button"
                className={styles.secondaryBtn}
                onClick={() =>
                  writeContract({
                    address: d.votingEscrow,
                    abi: abis.VotingEscrow,
                    functionName: "setWithdrawalCooldown",
                    args: [BigInt(Math.floor(Number(cooldownHrs || "0") * 3600))],
                  })
                }
              >
                Set cooldown
              </button>
            </div>
            <label className={styles.label}>
              Set tier for account
              <input
                className={styles.input}
                placeholder="0x…"
                value={tierAccount}
                onChange={(e) => setTierAccount(e.target.value)}
              />
            </label>
            <label className={styles.label}>
              Tier
              <select
                className={styles.input}
                value={tier}
                onChange={(e) => setTier(Number(e.target.value))}
              >
                {TIER_OPTIONS.map((t) => (
                  <option key={t.value} value={t.value}>
                    {t.label}
                  </option>
                ))}
              </select>
            </label>
            <button
              type="button"
              className={styles.primaryBtn}
              disabled={!isAddress(tierAccount)}
              onClick={() =>
                writeContract({
                  address: d.votingEscrow,
                  abi: abis.VotingEscrow,
                  functionName: "setTier",
                  args: [tierAccount as Address, tier],
                })
              }
            >
              Set tier
            </button>
          </ActionCard>
        </Reveal>

        <Reveal className={styles.span2} delay={0.18}>
          <ActionCard
            title="Adapters"
            description="REGISTRY_ADMIN registers and toggles adapters. Partners deploy from /integrate; you whitelist here."
            allowed={Boolean(isRegistryAdmin)}
            need="Need REGISTRY_ADMIN"
          >
            <h4 className={styles.h4}>Listed dApps</h4>
            {adapterList.length === 0 ? (
              <p className={styles.muted}>No adapters registered yet.</p>
            ) : (
              <div className={styles.tableWrap}>
                <table className={styles.table}>
                  <thead>
                    <tr>
                      <th>Adapter</th>
                      <th>dApp</th>
                      <th>Mode</th>
                      <th>bps</th>
                      <th>Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {adapterList.map((adapter, i) => {
                      const info = adapterInfos?.[i]?.result as AdapterInfoRow | undefined;
                      const dapp = info?.dapp;
                      const mode = info ? Number(info.mode) : undefined;
                      const bps = info ? Number(info.committedBps) : undefined;
                      const active = info?.active;
                      return (
                        <tr key={adapter}>
                          <td>
                            <AddressLink address={adapter} chainId={chainId} />
                          </td>
                          <td>
                            {dapp ? (
                              <AddressLink address={dapp} chainId={chainId} />
                            ) : (
                              "…"
                            )}
                          </td>
                          <td>{mode !== undefined ? modeLabel(mode) : "…"}</td>
                          <td>{bps !== undefined ? bps : "…"}</td>
                          <td>
                            {active === undefined ? (
                              "…"
                            ) : (
                              <StatusPill tone={active ? "ok" : "muted"}>
                                {active ? "Active" : "Inactive"}
                              </StatusPill>
                            )}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}

            <hr className={styles.hr} />
            <h4 className={styles.h4}>Register</h4>
            <label className={styles.label}>
              Adapter address
              <input
                className={styles.input}
                value={adapterAddr}
                onChange={(e) => setAdapterAddr(e.target.value)}
              />
            </label>
            <label className={styles.label}>
              dApp address
              <input
                className={styles.input}
                value={adapterDapp}
                onChange={(e) => setAdapterDapp(e.target.value)}
              />
            </label>
            <div className={styles.row}>
              <label className={styles.label}>
                Mode
                <select
                  className={styles.input}
                  value={adapterMode}
                  onChange={(e) => setAdapterMode(Number(e.target.value))}
                >
                  {ADAPTER_MODES.map((m) => (
                    <option key={m.value} value={m.value}>
                      {m.label}
                    </option>
                  ))}
                </select>
              </label>
              <label className={styles.label}>
                Committed bps
                <input
                  className={styles.input}
                  value={committedBps}
                  onChange={(e) => setCommittedBps(e.target.value)}
                />
              </label>
            </div>
            {registerBlocking ? <p className={styles.err}>{registerBlocking}</p> : null}
            {registerHint && !registerBlocking ? <p className={styles.ok}>{registerHint}</p> : null}
            <button
              type="button"
              className={styles.primaryBtn}
              disabled={!canRegister}
              onClick={() =>
                writeContract({
                  address: d.revenueRegistry,
                  abi: abis.RevenueRegistry,
                  functionName: "registerAdapter",
                  args: [
                    adapterAddr as Address,
                    adapterDapp as Address,
                    adapterMode,
                    Number(committedBps || "0"),
                    1,
                    ZERO_BYTES32,
                  ],
                })
              }
            >
              Register adapter
            </button>
            <hr className={styles.hr} />
            <label className={styles.label}>
              Deactivate / reactivate
              <select
                className={styles.input}
                value={toggleAdapter}
                onChange={(e) => setToggleAdapter(e.target.value)}
              >
                <option value="">Select adapter…</option>
                {adapterList.map((a) => (
                  <option key={a} value={a}>
                    {a}
                  </option>
                ))}
              </select>
            </label>
            <div className={styles.row}>
              <button
                type="button"
                className={styles.dangerBtn}
                disabled={!isAddress(toggleAdapter)}
                onClick={() =>
                  writeContract({
                    address: d.revenueRegistry,
                    abi: abis.RevenueRegistry,
                    functionName: "deactivateAdapter",
                    args: [toggleAdapter as Address],
                  })
                }
              >
                Deactivate
              </button>
              <button
                type="button"
                className={styles.secondaryBtn}
                disabled={!isAddress(toggleAdapter)}
                onClick={() =>
                  writeContract({
                    address: d.revenueRegistry,
                    abi: abis.RevenueRegistry,
                    functionName: "reactivateAdapter",
                    args: [toggleAdapter as Address],
                  })
                }
              >
                Reactivate
              </button>
            </div>
          </ActionCard>
        </Reveal>

        {showSimulate ? (
          <Reveal className={styles.span2} delay={0.2}>
            <ActionCard
              title="Simulate revenue (Apothem)"
              description="Mint mock USDC to a registered FeeSplitter, then skim. Expected committed = amount × bps / 10000."
              allowed={isConnected}
              need="Connect wallet"
            >
              <label className={styles.label}>
                FeeSplitter
                <select
                  className={styles.input}
                  value={simAdapter}
                  onChange={(e) => {
                    setSimAdapter(e.target.value);
                    setSimStep("idle");
                  }}
                >
                  <option value="">Select registered SPLITTER…</option>
                  {splitterCandidates.map((a) => (
                    <option key={a} value={a}>
                      {a}
                    </option>
                  ))}
                </select>
              </label>
              <label className={styles.label}>
                Amount (USDC)
                <input
                  className={styles.input}
                  value={simAmount}
                  onChange={(e) => setSimAmount(e.target.value)}
                  inputMode="decimal"
                />
              </label>
              <p className={styles.hint}>
                Token:{" "}
                {usdc ? <AddressLink address={usdc} chainId={chainId} /> : "—"} · bps {simBps || "—"} ·
                expected committed{" "}
                {simBps
                  ? `${formatUnits(expectedCommitted, Number(usdcDecimals ?? 6))} USDC`
                  : "—"}
              </p>
              <div className={styles.row}>
                <button
                  type="button"
                  className={styles.secondaryBtn}
                  disabled={!isAddress(simAdapter) || simAmountWei <= 0n || !usdc}
                  onClick={() => {
                    writeContract({
                      address: usdc as Address,
                      abi: mockErc20Abi,
                      functionName: "mint",
                      args: [simAdapter as Address, simAmountWei],
                    });
                    setSimStep("minted");
                  }}
                >
                  1. Mint to splitter
                </button>
                <button
                  type="button"
                  className={styles.primaryBtn}
                  disabled={!isAddress(simAdapter) || !usdc}
                  onClick={() =>
                    writeContract({
                      address: simAdapter as Address,
                      abi: abis.FeeSplitter,
                      functionName: "skim",
                      args: [usdc as Address],
                    })
                  }
                >
                  2. Skim USDC
                </button>
              </div>
              {simStep === "minted" ? (
                <p className={styles.muted}>
                  After mint confirms, skim. Then settle the epoch and check claims / indexer.
                </p>
              ) : null}
            </ActionCard>
          </Reveal>
        ) : null}

        <Reveal className={styles.span2} delay={0.22}>
          <ActionCard
            title="Grant / revoke roles"
            description="Hub DEFAULT_ADMIN on SystemAccess assigns target roles (keeper, pauser, registry admin, …)."
            allowed={Boolean(isHubAdmin)}
            need="Need SystemAccess hub admin"
          >
            <div className={styles.split}>
              <div>
                <h4 className={styles.h4}>Grant</h4>
                <label className={styles.label}>
                  Target
                  <select
                    className={styles.input}
                    value={grantTarget}
                    onChange={(e) =>
                      setGrantTarget(e.target.value as "feeDistributor" | "revenueRegistry")
                    }
                  >
                    <option value="feeDistributor">FeeDistributor</option>
                    <option value="revenueRegistry">RevenueRegistry</option>
                  </select>
                </label>
                <label className={styles.label}>
                  Role
                  <select
                    className={styles.input}
                    value={grantRole}
                    onChange={(e) => setGrantRole(e.target.value as RoleKey)}
                  >
                    {(Object.keys(ROLES) as RoleKey[]).map((rk) => (
                      <option key={rk} value={rk}>
                        {ROLE_META[rk].label}
                      </option>
                    ))}
                  </select>
                </label>
                <label className={styles.label}>
                  Account
                  <input
                    className={styles.input}
                    placeholder="0x…"
                    value={grantAccount}
                    onChange={(e) => setGrantAccount(e.target.value)}
                  />
                </label>
                <button
                  type="button"
                  className={styles.primaryBtn}
                  disabled={!isAddress(grantAccount)}
                  onClick={() =>
                    writeContract({
                      address: d.systemAccess,
                      abi: abis.SystemAccess,
                      functionName: "grantRole",
                      args: [targetAddress(grantTarget), ROLES[grantRole], grantAccount as Address],
                    })
                  }
                >
                  Grant role
                </button>
              </div>
              <div>
                <h4 className={styles.h4}>Revoke</h4>
                <label className={styles.label}>
                  Target
                  <select
                    className={styles.input}
                    value={revokeTarget}
                    onChange={(e) =>
                      setRevokeTarget(e.target.value as "feeDistributor" | "revenueRegistry")
                    }
                  >
                    <option value="feeDistributor">FeeDistributor</option>
                    <option value="revenueRegistry">RevenueRegistry</option>
                  </select>
                </label>
                <label className={styles.label}>
                  Role
                  <select
                    className={styles.input}
                    value={revokeRole}
                    onChange={(e) => setRevokeRole(e.target.value as RoleKey)}
                  >
                    {(Object.keys(ROLES) as RoleKey[]).map((rk) => (
                      <option key={rk} value={rk}>
                        {ROLE_META[rk].label}
                      </option>
                    ))}
                  </select>
                </label>
                <label className={styles.label}>
                  Account
                  <input
                    className={styles.input}
                    placeholder="0x…"
                    value={revokeAccount}
                    onChange={(e) => setRevokeAccount(e.target.value)}
                  />
                </label>
                <button
                  type="button"
                  className={styles.dangerBtn}
                  disabled={!isAddress(revokeAccount)}
                  onClick={() =>
                    writeContract({
                      address: d.systemAccess,
                      abi: abis.SystemAccess,
                      functionName: "revokeRole",
                      args: [
                        targetAddress(revokeTarget),
                        ROLES[revokeRole],
                        revokeAccount as Address,
                      ],
                    })
                  }
                >
                  Revoke role
                </button>
              </div>
            </div>
          </ActionCard>
        </Reveal>
      </div>

      <TxStatus
        hash={hash}
        isPending={isPending}
        isConfirming={isConfirming}
        isSuccess={isSuccess}
        error={error as Error | null}
      />
    </div>
  );
}
