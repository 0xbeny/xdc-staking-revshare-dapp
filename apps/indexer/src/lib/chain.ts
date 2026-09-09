import {
  XDC_APOTHEM,
  XDC_MAINNET,
  type Address,
} from "@vexdc/contracts";
import { createPublicClient, createWalletClient, http, type Chain, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { getRpcUrl } from "./env";

export function xdcChain(chainId: number): Chain {
  if (chainId === 50) {
    return {
      id: XDC_MAINNET.id,
      name: XDC_MAINNET.name,
      nativeCurrency: XDC_MAINNET.nativeCurrency,
      rpcUrls: {
        default: { http: [...XDC_MAINNET.rpcUrls.default.http] },
      },
      blockExplorers: {
        default: {
          name: XDC_MAINNET.blockExplorers.default.name,
          url: XDC_MAINNET.blockExplorers.default.url,
        },
      },
    };
  }
  return {
    id: XDC_APOTHEM.id,
    name: XDC_APOTHEM.name,
    nativeCurrency: XDC_APOTHEM.nativeCurrency,
    rpcUrls: {
      default: { http: [...XDC_APOTHEM.rpcUrls.default.http] },
    },
    blockExplorers: {
      default: {
        name: XDC_APOTHEM.blockExplorers.default.name,
        url: XDC_APOTHEM.blockExplorers.default.url,
      },
    },
    testnet: true,
  };
}

export function makePublicClient(chainId: number) {
  return createPublicClient({
    chain: xdcChain(chainId),
    transport: http(getRpcUrl()),
  });
}

export function makeWalletClient(chainId: number, privateKey: Hex) {
  const account = privateKeyToAccount(privateKey);
  return createWalletClient({
    account,
    chain: xdcChain(chainId),
    transport: http(getRpcUrl()),
  });
}

export function isAddress(value: string): value is Address {
  return /^0x[0-9a-fA-F]{40}$/.test(value);
}

export function normalizeAddress(value: string): Address {
  return value.toLowerCase() as Address;
}
