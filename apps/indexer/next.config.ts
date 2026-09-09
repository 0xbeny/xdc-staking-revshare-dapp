import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  transpilePackages: ["@vexdc/contracts"],
};

export default nextConfig;
