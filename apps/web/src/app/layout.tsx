import type { Metadata } from "next";
import { IBM_Plex_Mono, IBM_Plex_Sans, Syne } from "next/font/google";
import { ContractsBanner } from "@/components/ContractsBanner";
import { Header } from "@/components/Header";
import { Providers } from "./providers";
import "./globals.css";

const syne = Syne({
  subsets: ["latin"],
  variable: "--font-syne",
  display: "swap",
  weight: ["600", "700", "800"],
});

const ibmPlex = IBM_Plex_Sans({
  subsets: ["latin"],
  variable: "--font-ibm-plex",
  display: "swap",
  weight: ["400", "500", "600"],
});

const ibmMono = IBM_Plex_Mono({
  subsets: ["latin"],
  variable: "--font-ibm-plex-mono",
  display: "swap",
  weight: ["400", "500"],
});

export const metadata: Metadata = {
  title: "veXDC — Lock XDC. Earn protocol revenue.",
  description: "Vote-escrowed XDC staking and revenue share.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${syne.variable} ${ibmPlex.variable} ${ibmMono.variable}`}>
      <body>
        <Providers>
          <Header />
          <ContractsBanner />
          <main>{children}</main>
        </Providers>
      </body>
    </html>
  );
}
