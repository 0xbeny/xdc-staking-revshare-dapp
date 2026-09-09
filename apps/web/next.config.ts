import type { NextConfig } from "next";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const root = path.dirname(fileURLToPath(import.meta.url));

const walletConnectEntry = path.join(
  path.dirname(require.resolve("@wagmi/connectors/package.json")),
  "dist/esm/walletConnect.js",
);

const nextConfig: NextConfig = {
  transpilePackages: ["@vexdc/contracts"],
  reactStrictMode: true,
  webpack: (config) => {
    config.resolve.alias = {
      ...config.resolve.alias,
      // Avoid connectors barrel → Coinbase CDP / @x402 optional deps
      "@vexdc/walletconnect": walletConnectEntry,
      "@react-native-async-storage/async-storage": false,
      "pino-pretty": false,
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
