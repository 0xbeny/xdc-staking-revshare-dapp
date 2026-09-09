import type { ReactNode } from "react";

export const metadata = {
  title: "veXDC Indexer",
  description: "Event indexer and read API for veXDC staking / revenue share",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
