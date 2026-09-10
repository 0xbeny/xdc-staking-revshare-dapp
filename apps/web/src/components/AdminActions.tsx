"use client";

import { abis } from "@vexdc/contracts";
import { useEffect, useMemo, useState } from "react";
import type { Address, Hex } from "viem";
import { isAddress } from "viem";
import {
  useAccount,
  useReadContract,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import { AddressLink } from "@/components/AddressLink";
import { Reveal } from "@/components/Reveal";
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

export function AdminActions() {
  const state = getContractsState();
  const ready = contractsReady(state);
  const d = state.deployment;
  const chainId = state.chainId;
  const { address, isConnected } = useAccount();

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
  const { data: adapters } = useReadContract({
    address: d.revenueRegistry,
    abi: abis.RevenueRegistry,
    functionName: "allAdapters",
    query: { enabled: ready },
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
      const t = setTimeout(() => reset(), 4000);
      return () => clearTimeout(t);
    }
  }, [isSuccess, reset]);

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

  if (!ready) {
    return <p className={styles.banner}>Contracts not live on this chain.</p>;
  }

  const targetAddress = (key: "feeDistributor" | "revenueRegistry") =>
    key === "feeDistributor" ? d.feeDistributor : d.revenueRegistry;

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

        <Reveal delay={0.18}>
          <ActionCard
            title="Adapters"
            description="REGISTRY_ADMIN registers and toggles adapters. Deploy the adapter contract first, then register."
            allowed={Boolean(isRegistryAdmin)}
            need="Need REGISTRY_ADMIN"
          >
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
            <button
              type="button"
              className={styles.primaryBtn}
              disabled={!isAddress(adapterAddr) || !isAddress(adapterDapp)}
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
                {((adapters as Address[] | undefined) ?? []).map((a) => (
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
