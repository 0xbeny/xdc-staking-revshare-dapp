import { contractsReady, explorerAddressUrl, getContractsState } from "@/lib/contracts";
import { chainLabel, commitUrl, gitSha, shortSha } from "@/lib/buildInfo";
import { formatDate, shortAddress } from "@/lib/format";
import styles from "./SiteFooter.module.css";

export function SiteFooter() {
  const state = getContractsState();
  const sha = gitSha();
  const short = shortSha(sha);
  const live = contractsReady(state);
  const escrow = state.deployment.votingEscrow;
  const deployed = state.deployment.deployedAt;

  return (
    <footer className={styles.footer}>
      <p className={styles.row}>
        <span>{chainLabel(state.chainId)}</span>
        {live ? (
          <>
            <span className={styles.dot} aria-hidden>
              ·
            </span>
            <a
              className={styles.link}
              href={explorerAddressUrl(state.chainId, escrow)}
              target="_blank"
              rel="noreferrer"
              title={escrow}
            >
              escrow {shortAddress(escrow)}
            </a>
            {deployed > 0 ? (
              <>
                <span className={styles.dot} aria-hidden>
                  ·
                </span>
                <span title="Contract deploy date (UTC)">{formatDate(deployed)}</span>
              </>
            ) : null}
          </>
        ) : (
          <>
            <span className={styles.dot} aria-hidden>
              ·
            </span>
            <span>contracts not live</span>
          </>
        )}
        {short ? (
          <>
            <span className={styles.dot} aria-hidden>
              ·
            </span>
            <a className={styles.link} href={commitUrl(sha)} target="_blank" rel="noreferrer" title={sha}>
              ui {short}
            </a>
          </>
        ) : null}
      </p>
    </footer>
  );
}
