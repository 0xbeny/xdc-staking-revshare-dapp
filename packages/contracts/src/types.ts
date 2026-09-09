export type Address = `0x${string}`;

export type DeploymentAddresses = {
  chainId: number;
  deployedAt: number;
  systemAccess: Address;
  votingEscrow: Address;
  feeDistributor: Address;
  feeDistributorImpl: Address;
  revenueRegistry: Address;
  revenueRegistryImpl: Address;
  zapDepositor: Address;
  veVotesAdapter: Address;
  wxdc: Address;
  timelock: Address;
  guardian: Address;
  treasury: Address;
  keeper: Address;
  usdc?: Address;
  feeSplitter?: Address;
  /** First block to index (deploy block). */
  startBlock?: number;
};
