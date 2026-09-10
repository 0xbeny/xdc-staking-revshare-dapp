"use client";

import { abis } from "@vexdc/contracts";
import { useMemo } from "react";
import { useReadContract, useReadContracts } from "wagmi";
import type { Address } from "viem";
import { formatEther } from "viem";
import { AddressLink } from "@/components/AddressLink";
import { Reveal } from "@/components/Reveal";
import { StatusPill } from "@/components/StatusPill";
import { contractsReady, getContractsState } from "@/lib/contracts";
import { ROLE_META, ROLES, type RoleKey, TARGET_LABEL, type TargetKey } from "@/lib/roles";
import styles from "./SystemStatus.module.css";

const DISTRIBUTOR_ROLES: RoleKey[] = [
  "DEFAULT_ADMIN",
  "UPGRADER",
  "PAUSER",
  "KEEPER",
];
const REGISTRY_ROLES: RoleKey[] = ["DEFAULT_ADMIN", "UPGRADER", "REGISTRY_ADMIN"];

function RoleMembers({
  systemAccess,
  target,
  role,
  chainId,
}: {
  systemAccess: Address;
  target: Address;
  role: `0x${string}`;
  chainId: number;
}) {
  const { data: count } = useReadContract({
    address: systemAccess,
    abi: abis.SystemAccess,
    functionName: "getRoleMemberCount",
    args: [target, role],
  });

  const memberCount = count !== undefined ? Number(count) : 0;
  const contracts = useMemo(() => {
    return Array.from({ length: memberCount }, (_, i) => ({
      address: systemAccess,
      abi: abis.SystemAccess,
      functionName: "getRoleMember" as const,
      args: [target, role, BigInt(i)] as const,
    }));
  }, [systemAccess, target, role, memberCount]);

  const { data: members } = useReadContracts({
    contracts,
    query: { enabled: memberCount > 0 },
  });

  if (memberCount === 0) {
    return <span className={styles.empty}>none</span>;
  }

  return (
    <ul className={styles.memberList}>
      {(members ?? []).map((m, i) => {
        const addr = m.result as Address | undefined;
        if (!addr) return null;
        return (
          <li key={`${addr}-${i}`}>
            <AddressLink address={addr} chainId={chainId} />
          </li>
        );
      })}
    </ul>
  );
}

export function SystemStatus() {
  const state = getContractsState();
  const ready = contractsReady(state);
  const d = state.deployment;
  const chainId = state.chainId;

  const { data: paused } = useReadContract({
    address: d.feeDistributor,
    abi: abis.FeeDistributor,
    functionName: "paused",
    query: { enabled: ready },
  });

  const { data: escrowParams } = useReadContracts({
    contracts: [
      {
        address: d.votingEscrow,
        abi: abis.VotingEscrow,
        functionName: "timelock",
      },
      {
        address: d.votingEscrow,
        abi: abis.VotingEscrow,
        functionName: "treasury",
      },
      {
        address: d.votingEscrow,
        abi: abis.VotingEscrow,
        functionName: "pendingTimelock",
      },
      {
        address: d.votingEscrow,
        abi: abis.VotingEscrow,
        functionName: "maxPenaltyBps",
      },
      {
        address: d.votingEscrow,
        abi: abis.VotingEscrow,
        functionName: "penaltySplitBps",
      },
      {
        address: d.votingEscrow,
        abi: abis.VotingEscrow,
        functionName: "withdrawalCooldown",
      },
      {
        address: d.votingEscrow,
        abi: abis.VotingEscrow,
        functionName: "totalLocked",
      },
      {
        address: d.votingEscrow,
        abi: abis.VotingEscrow,
        functionName: "depositor",
      },
    ],
    query: { enabled: ready },
  });

  const { data: distMeta } = useReadContracts({
    contracts: [
      {
        address: d.feeDistributor,
        abi: abis.FeeDistributor,
        functionName: "authority",
      },
      {
        address: d.revenueRegistry,
        abi: abis.RevenueRegistry,
        functionName: "authority",
      },
      {
        address: d.revenueRegistry,
        abi: abis.RevenueRegistry,
        functionName: "allAdapters",
      },
    ],
    query: { enabled: ready },
  });

  const targets: { key: TargetKey; address: Address }[] = [
    { key: "feeDistributor", address: d.feeDistributor },
    { key: "revenueRegistry", address: d.revenueRegistry },
  ];

  const contractRows: { label: string; address: Address; note?: string }[] = [
    { label: "SystemAccess", address: d.systemAccess, note: "Role hub" },
    { label: "VotingEscrow", address: d.votingEscrow, note: "Immutable principal" },
    { label: "FeeDistributor", address: d.feeDistributor, note: "UUPS proxy" },
    { label: "FeeDistributor impl", address: d.feeDistributorImpl },
    { label: "RevenueRegistry", address: d.revenueRegistry, note: "UUPS proxy" },
    { label: "RevenueRegistry impl", address: d.revenueRegistryImpl },
    { label: "ZapDepositor", address: d.zapDepositor, note: "Sole mint path" },
    { label: "VeVotesAdapter", address: d.veVotesAdapter },
    { label: "WXDC", address: d.wxdc },
    ...(d.usdc ? [{ label: "USDC (mock)", address: d.usdc }] : []),
    ...(d.feeSplitter ? [{ label: "FeeSplitter", address: d.feeSplitter, note: "Mode B" }] : []),
    { label: "Configured timelock", address: d.timelock },
    { label: "Configured guardian", address: d.guardian },
    { label: "Configured keeper", address: d.keeper },
    { label: "Configured treasury", address: d.treasury },
  ];

  const timelock = escrowParams?.[0]?.result as Address | undefined;
  const treasury = escrowParams?.[1]?.result as Address | undefined;
  const pendingTimelock = escrowParams?.[2]?.result as Address | undefined;
  const maxPenaltyBps = escrowParams?.[3]?.result as bigint | undefined;
  const penaltySplitBps = escrowParams?.[4]?.result as bigint | undefined;
  const withdrawalCooldown = escrowParams?.[5]?.result as bigint | undefined;
  const totalLocked = escrowParams?.[6]?.result as bigint | undefined;
  const depositor = escrowParams?.[7]?.result as Address | undefined;
  const adapters = (distMeta?.[2]?.result as Address[] | undefined) ?? [];

  if (!ready) {
    return (
      <p className={styles.banner}>
        Contracts are not live on this chain. Deploy Apothem first, then refresh.
      </p>
    );
  }

  return (
    <div className={styles.grid}>
      <Reveal className={styles.panel} delay={0.02}>
        <header className={styles.panelHead}>
          <h2 className={styles.h2}>Protocol health</h2>
          <StatusPill tone={paused ? "danger" : "ok"}>
            {paused ? "Distributor paused" : "Distributor live"}
          </StatusPill>
        </header>
        <dl className={styles.kpiGrid}>
          <div>
            <dt>Total locked</dt>
            <dd>{totalLocked !== undefined ? `${Number(formatEther(totalLocked)).toLocaleString()} WXDC` : "—"}</dd>
          </div>
          <div>
            <dt>Max penalty</dt>
            <dd>{maxPenaltyBps !== undefined ? `${Number(maxPenaltyBps) / 100}%` : "—"}</dd>
          </div>
          <div>
            <dt>Treasury split</dt>
            <dd>{penaltySplitBps !== undefined ? `${Number(penaltySplitBps) / 100}%` : "—"}</dd>
          </div>
          <div>
            <dt>Exit cooldown</dt>
            <dd>
              {withdrawalCooldown !== undefined
                ? `${Number(withdrawalCooldown) / 3600}h`
                : "—"}
            </dd>
          </div>
        </dl>
      </Reveal>

      <Reveal className={styles.panel} delay={0.08}>
        <header className={styles.panelHead}>
          <h2 className={styles.h2}>Escrow governance</h2>
          <p className={styles.hint}>VotingEscrow uses a single timelock — not SystemAccess roles.</p>
        </header>
        <table className={styles.table}>
          <tbody>
            <tr>
              <th scope="row">Timelock</th>
              <td>{timelock ? <AddressLink address={timelock} chainId={chainId} /> : "—"}</td>
            </tr>
            <tr>
              <th scope="row">Pending timelock</th>
              <td>
                {pendingTimelock && pendingTimelock !== "0x0000000000000000000000000000000000000000" ? (
                  <AddressLink address={pendingTimelock} chainId={chainId} />
                ) : (
                  <span className={styles.empty}>none</span>
                )}
              </td>
            </tr>
            <tr>
              <th scope="row">Treasury</th>
              <td>{treasury ? <AddressLink address={treasury} chainId={chainId} /> : "—"}</td>
            </tr>
            <tr>
              <th scope="row">Depositor (Zap)</th>
              <td>{depositor ? <AddressLink address={depositor} chainId={chainId} /> : "—"}</td>
            </tr>
          </tbody>
        </table>
      </Reveal>

      <Reveal className={`${styles.panel} ${styles.span2}`} delay={0.12}>
        <header className={styles.panelHead}>
          <h2 className={styles.h2}>Contract registry</h2>
          <StatusPill tone="info">Chain {chainId}</StatusPill>
        </header>
        <div className={styles.tableScroll}>
          <table className={styles.table}>
            <thead>
              <tr>
                <th>Contract</th>
                <th>Address</th>
                <th>Note</th>
              </tr>
            </thead>
            <tbody>
              {contractRows.map((row) => (
                <tr key={row.label}>
                  <td className={styles.name}>{row.label}</td>
                  <td>
                    <AddressLink address={row.address} chainId={chainId} />
                  </td>
                  <td className={styles.muted}>{row.note ?? "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Reveal>

      <Reveal className={`${styles.panel} ${styles.span2}`} delay={0.18}>
        <header className={styles.panelHead}>
          <h2 className={styles.h2}>SystemAccess role matrix</h2>
          <p className={styles.hint}>
            Hub admin on SystemAccess grants/revokes every target role below.
          </p>
        </header>
        <div className={styles.roleGrid}>
          {targets.map((t) => (
            <article key={t.key} className={styles.roleCard}>
              <h3 className={styles.h3}>{TARGET_LABEL[t.key]}</h3>
              <p className={styles.addr}>
                <AddressLink address={t.address} chainId={chainId} />
              </p>
              <ul className={styles.roleList}>
                {(t.key === "feeDistributor" ? DISTRIBUTOR_ROLES : REGISTRY_ROLES).map((rk) => (
                  <li key={rk} className={styles.roleRow}>
                    <div>
                      <div className={styles.roleName}>{ROLE_META[rk].label}</div>
                      <div className={styles.muted}>{ROLE_META[rk].description}</div>
                    </div>
                    <RoleMembers
                      systemAccess={d.systemAccess}
                      target={t.address}
                      role={ROLES[rk]}
                      chainId={chainId}
                    />
                  </li>
                ))}
              </ul>
            </article>
          ))}

          <article className={styles.roleCard}>
            <h3 className={styles.h3}>SystemAccess hub</h3>
            <p className={styles.addr}>
              <AddressLink address={d.systemAccess} chainId={chainId} />
            </p>
            <ul className={styles.roleList}>
              <li className={styles.roleRow}>
                <div>
                  <div className={styles.roleName}>Hub DEFAULT_ADMIN</div>
                  <div className={styles.muted}>
                    OZ AccessControl on the hub itself — grants/revokes every target role. Expected:
                    configured timelock.
                  </div>
                </div>
                <AddressLink address={d.timelock} chainId={chainId} />
              </li>
            </ul>
          </article>
        </div>
      </Reveal>

      <Reveal className={`${styles.panel} ${styles.span2}`} delay={0.22}>
        <header className={styles.panelHead}>
          <h2 className={styles.h2}>Registered adapters</h2>
          <StatusPill tone="muted">{adapters.length} active listings</StatusPill>
        </header>
        {adapters.length === 0 ? (
          <p className={styles.empty}>No adapters registered yet.</p>
        ) : (
          <ul className={styles.adapterList}>
            {adapters.map((a) => (
              <li key={a}>
                <AddressLink address={a} chainId={chainId} />
              </li>
            ))}
          </ul>
        )}
      </Reveal>
    </div>
  );
}
