declare module "@vexdc/walletconnect" {
  import type { CreateConnectorFn } from "@wagmi/core";

  type WalletConnectParameters = {
    projectId: string;
    showQrModal?: boolean;
    metadata?: {
      name: string;
      description: string;
      url: string;
      icons: string[];
    };
  };

  export function walletConnect(parameters: WalletConnectParameters): CreateConnectorFn;
}
