import type { NextConfig } from "next";
import { execSync } from "node:child_process";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const root = path.dirname(fileURLToPath(import.meta.url));

const walletConnectEntry = path.join(
  path.dirname(require.resolve("@wagmi/connectors/package.json")),
  "dist/esm/walletConnect.js",
);

function resolveGitSha(): string {
  const fromEnv = process.env.VERCEL_GIT_COMMIT_SHA || process.env.NEXT_PUBLIC_GIT_SHA;
  if (fromEnv) return fromEnv.trim();
  try {
    return execSync("git rev-parse HEAD", {
      cwd: path.join(root, "../.."),
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return "";
  }
}

const gitSha = resolveGitSha();
process.env.NEXT_PUBLIC_GIT_SHA = gitSha;

const nextConfig: NextConfig = {
  transpilePackages: ["@vexdc/contracts"],
  reactStrictMode: true,
  env: {
    NEXT_PUBLIC_GIT_SHA: gitSha,
  },
  webpack: (config) => {
    config.resolve.alias = {
      ...config.resolve.alias,
      // Avoid connectors barrel → Coinbase CDP / @x402 optional deps
      "@vexdc/walletconnect": walletConnectEntry,
      "@react-native-async-storage/async-storage": false,
      "pino-pretty": false,
      // @privy-io/wagmi imports the wagmi connectors barrel → @base-org/account
      // → Coinbase CDP SDK → optional @x402 packages. None of that is used
      // (Privy drives Coinbase Wallet through its own SDK); stub the chain.
      "@coinbase/cdp-sdk": false,
      "@x402/evm": false,
      "@x402/svm": false,
      "@x402/types": false,
    };
    config.resolve.fallback = {
      ...config.resolve.fallback,
      fs: false,
      net: false,
      tls: false,
    };
    config.resolve.modules = [
      ...(config.resolve.modules ?? ["node_modules"]),
      path.join(root, "../../node_modules"),
    ];
    return config;
  },
};

export default nextConfig;
