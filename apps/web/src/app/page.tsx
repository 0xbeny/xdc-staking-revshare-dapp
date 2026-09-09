import { ConnectButton } from "@/components/ConnectButton";
import { DepositForm } from "@/components/DepositForm";
import styles from "./page.module.css";

export default function HomePage() {
  return (
    <>
      <section className={styles.hero} aria-labelledby="brand-title">
        <div className={styles.heroGlow} aria-hidden />
        <div className={`shell ${styles.heroInner}`}>
          <h1 id="brand-title" className={styles.brand}>
            veXDC
            <span className={styles.filament} aria-hidden />
          </h1>
          <p className={styles.tagline}>Lock XDC. Earn protocol revenue.</p>
          <div className={styles.ctas}>
            <ConnectButton />
            <a className={styles.lockCta} href="#deposit">
              Lock XDC →
            </a>
          </div>
        </div>
      </section>

      <section className={styles.depositSection}>
        <div className={`shell ${styles.depositWrap}`}>
          <DepositForm />
        </div>
      </section>
    </>
  );
}
