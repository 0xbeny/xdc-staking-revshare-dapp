"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { PrivyProvider } from "@privy-io/react-auth";
import { WagmiProvider as PrivyWagmiProvider } from "@privy-io/wagmi";
import { type ReactNode, useState } from "react";
import { WagmiProvider } from "wagmi";
import { privyAppId, privyConfig, privyEnabled } from "@/lib/privy";
import { wagmiConfig } from "@/lib/wagmi";

export function Providers({ children }: { children: ReactNode }) {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            staleTime: 15_000,
            refetchOnWindowFocus: false,
          },
        },
      }),
  );

  if (privyEnabled) {
    return (
      <PrivyProvider appId={privyAppId} config={privyConfig}>
        <QueryClientProvider client={queryClient}>
          <PrivyWagmiProvider config={wagmiConfig}>{children}</PrivyWagmiProvider>
        </QueryClientProvider>
      </PrivyProvider>
    );
  }

  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </WagmiProvider>
  );
}
