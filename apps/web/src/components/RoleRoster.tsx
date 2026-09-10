"use client";

import { abis } from "@vexdc/contracts";
import { useMemo } from "react";
import type { Address } from "viem";
import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { AddressLink } from "@/components/AddressLink";
import { contractsReady, getContractsState } from "@/lib/contracts";
import { ROLE_META, ROLES, type RoleKey, TARGET_LABEL } from "@/lib/roles";
import styles from "./RoleRoster.module.css";

const DISTRIBUTOR_ROLES: RoleKey[] = ["DEFAULT_ADMIN", "UPGRADER", "PAUSER", "KEEPER"];
const REGISTRY_ROLES: RoleKey[] = ["DEFAULT_ADMIN", "UPGRADER", "REGISTRY_ADMIN"];

function TargetRoleMembers({
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
  const contracts = useMemo(
    () =>
      Array.from({ length: memberCount }, (_, i) => ({
        address: systemAccess,
        abi: abis.SystemAccess,
        functionName: "getRoleMember" as const,
        args: [target, role, BigInt(i)] as const,
      })),
    [systemAccess, target, role, memberCount],
  );

  const { data: members, isLoading } = useReadContracts({
    contracts,
    query: { enabled: memberCount > 0 },
  });

  if (memberCount === 0) {
    return <span className={styles.empty}>{isLoading ? "…" : "none"}</span>;
  }

  return (
    <ul className={styles.members}>
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

function HubAdmins({
  systemAccess,
  candidates,
  chainId,
}: {
  systemAccess: Address;
  candidates: Address[];
  chainId: number;
}) {
  const checks = useMemo(
    () =>
      candidates.map((account) => ({
        address: systemAccess,
        abi: abis.SystemAccess,
        functionName: "hasRole" as const,
        // OZ 2-arg hub admin (not per-target).
        args: [ROLES.DEFAULT_ADMIN, account] as const,
      })),
    [systemAccess, candidates],
  );

  const { data, isLoading } = useReadContracts({
    contracts: checks,
    query: { enabled: candidates.length > 0 },
  });

  const holders = candidates.filter((_, i) => Boolean(data?.[i]?.result));

  if (isLoading && holders.length === 0) {
    return <span className={styles.empty}>Loading…</span>;
  }
  if (holders.length === 0) {
    return <span className={styles.empty}>none verified</span>;
  }

  return (
    <ul className={styles.members}>
      {holders.map((addr) => (
        <li key={addr}>
          <AddressLink address={addr} chainId={chainId} />
        </li>
      ))}
    </ul>
  );
}

export function RoleRoster() {
  const state = getContractsState();
  const ready = contractsReady(state);
  const d = state.deployment;
  const chainId = state.chainId;
  const { address } = useAccount();

  const hubCandidates = useMemo(() => {
    const set = new Set<string>();
    for (const a of [d.timelock, d.guardian, d.keeper, d.treasury, address]) {
      if (a && a !== "0x0000000000000000000000000000000000000000") {
        set.add(a.toLowerCase());
      }
    }
    return [...set] as Address[];
  }, [d.timelock, d.guardian, d.keeper, d.treasury, address]);

  if (!ready) return null;

  const targets: Array<{ key: "feeDistributor" | "revenueRegistry"; address: Address; roles: RoleKey[] }> =
    [
      { key: "feeDistributor", address: d.feeDistributor, roles: DISTRIBUTOR_ROLES },
      { key: "revenueRegistry", address: d.revenueRegistry, roles: REGISTRY_ROLES },
    ];

  return (
    <section className={styles.panel} aria-labelledby="role-roster-title">
      <header className={styles.head}>
        <div>
          <h2 id="role-roster-title" className={styles.h2}>
            Roles &amp; assignees
          </h2>
          <p className={styles.hint}>
            Hub <code>DEFAULT_ADMIN</code> is the configured timelock (
            <AddressLink address={d.timelock} chainId={chainId} />
            ). It grants and revokes every target role below.
          </p>
        </div>
      </header>

      <div className={styles.grid}>
        <article className={styles.card}>
          <h3 className={styles.h3}>{TARGET_LABEL.systemAccess}</h3>
          <p className={styles.target}>
            <AddressLink address={d.systemAccess} chainId={chainId} />
          </p>
          <ul className={styles.roleList}>
            <li className={styles.roleRow}>
              <div>
                <div className={styles.roleName}>DEFAULT_ADMIN (hub)</div>
                <div className={styles.desc}>
                  OZ AccessControl on SystemAccess — only this role can grant/revoke target roles.
                </div>
              </div>
              <HubAdmins
                systemAccess={d.systemAccess}
                candidates={hubCandidates}
                chainId={chainId}
              />
            </li>
          </ul>
        </article>

        {targets.map((t) => (
          <article key={t.key} className={styles.card}>
            <h3 className={styles.h3}>{TARGET_LABEL[t.key]}</h3>
            <p className={styles.target}>
              <AddressLink address={t.address} chainId={chainId} />
            </p>
            <ul className={styles.roleList}>
              {t.roles.map((rk) => (
                <li key={rk} className={styles.roleRow}>
                  <div>
                    <div className={styles.roleName}>{ROLE_META[rk].label}</div>
                    <div className={styles.desc}>{ROLE_META[rk].description}</div>
                  </div>
                  <TargetRoleMembers
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
      </div>
    </section>
  );
}
