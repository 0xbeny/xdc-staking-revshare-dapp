import { XDC_APOTHEM, XDC_MAINNET } from "@vexdc/contracts";

export const GITHUB_REPO = "https://github.com/0xbeny/xdc-staking-revshare-dapp";

export function gitSha(): string {
  return (process.env.NEXT_PUBLIC_GIT_SHA ?? process.env.VERCEL_GIT_COMMIT_SHA ?? "").trim();
}

export function shortSha(sha: string, length = 7): string {
  if (!sha) return "";
  const hex = sha.startsWith("0x") ? sha.slice(2) : sha;
  return hex.slice(0, length);
}

export function commitUrl(sha: string): string {
  return `${GITHUB_REPO}/commit/${sha}`;
}

export function chainLabel(chainId: number): string {
  if (chainId === XDC_MAINNET.id) return XDC_MAINNET.name;
  if (chainId === XDC_APOTHEM.id) return "Apothem";
  return `Chain ${chainId}`;
}
