import { z } from "zod";

const addressSchema = z
  .string()
  .regex(/^0x[0-9a-fA-F]{40}$/)
  .optional()
  .or(z.literal("").transform(() => undefined));

const envSchema = z.object({
  DATABASE_URL: z.string().min(1).optional(),
  DEPLOYMENT_CHAIN_ID: z.coerce.number().int().positive().default(51),
  INDEXER_RPC_URL: z.string().url().optional(),
  CRON_SECRET: z.string().min(1).optional(),
  KEEPER_PRIVATE_KEY: z
    .string()
    .regex(/^0x[0-9a-fA-F]{64}$/)
    .optional()
    .or(z.literal("").transform(() => undefined)),
  KEEPER_BATCH_SIZE: z.coerce.number().int().positive().optional(),
  SYNC_CONFIRMATIONS: z.coerce.number().int().nonnegative().optional(),
  FEE_SPLITTER: addressSchema,
  REWARD_TOKENS: z.string().optional(),
  CORS_ORIGIN: z.string().optional(),
});

export type IndexerEnv = z.infer<typeof envSchema>;

export function loadEnv(env: NodeJS.ProcessEnv = process.env): IndexerEnv {
  return envSchema.parse(env);
}

export function getChainId(): number {
  return loadEnv().DEPLOYMENT_CHAIN_ID;
}

export function getRpcUrl(): string {
  const env = loadEnv();
  if (env.INDEXER_RPC_URL) return env.INDEXER_RPC_URL;
  if (env.DEPLOYMENT_CHAIN_ID === 50) return "https://rpc.xinfin.network";
  return "https://rpc.apothem.network";
}

export function getCorsOrigin(): string {
  return loadEnv().CORS_ORIGIN ?? "*";
}
