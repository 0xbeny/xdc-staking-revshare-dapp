import { contractsReady, getContractsState } from "@/lib/contracts";
import styles from "./ContractsBanner.module.css";

export function ContractsBanner() {
  const state = getContractsState();
  if (contractsReady(state)) return null;

  return (
    <div className={styles.banner} role="status">
      <div className={`shell ${styles.inner}`}>
        <p className={styles.title}>Contracts not deployed on this network</p>
        <p className={styles.sub}>
          Chain {state.chainId} has no live deployment yet. The shell stays available; deposits
          and claims are disabled until addresses are published in{" "}
          <code>@vexdc/contracts</code>.
        </p>
      </div>
    </div>
  );
}
