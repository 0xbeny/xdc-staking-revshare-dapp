import {
  boolean,
  integer,
  jsonb,
  numeric,
  pgTable,
  primaryKey,
  serial,
  text,
  timestamp,
  unique,
} from "drizzle-orm/pg-core";

/** uint256-safe decimal string. */
const u256 = (name: string) => numeric(name, { precision: 78, scale: 0, mode: "string" });

export const syncCursors = pgTable(
  "sync_cursors",
  {
    chainId: integer("chain_id").notNull(),
    contractKey: text("contract_key").notNull(),
    fromBlock: u256("from_block").notNull(),
  },
  (t) => [primaryKey({ columns: [t.chainId, t.contractKey] })],
);

export const positions = pgTable(
  "positions",
  {
    chainId: integer("chain_id").notNull(),
    tokenId: u256("token_id").notNull(),
    owner: text("owner").notNull(),
    amount: u256("amount").notNull(),
    unlockTime: u256("unlock_time").notNull(),
    penaltyCapBps: integer("penalty_cap_bps").notNull(),
    closed: boolean("closed").notNull().default(false),
    firstEligibleEpoch: u256("first_eligible_epoch"),
    exitEpoch: u256("exit_epoch"),
    createdAtBlock: u256("created_at_block").notNull(),
    updatedAtBlock: u256("updated_at_block").notNull(),
  },
  (t) => [primaryKey({ columns: [t.chainId, t.tokenId] })],
);

export const positionEvents = pgTable(
  "position_events",
  {
    id: serial("id").primaryKey(),
    chainId: integer("chain_id").notNull(),
    tokenId: u256("token_id").notNull(),
    eventName: text("event_name").notNull(),
    txHash: text("tx_hash").notNull(),
    logIndex: integer("log_index").notNull(),
    blockNumber: u256("block_number").notNull(),
    payload: jsonb("payload").$type<Record<string, unknown>>().notNull(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    unique("position_events_chain_tx_log_uidx").on(t.chainId, t.txHash, t.logIndex),
  ],
);

export const epochs = pgTable(
  "epochs",
  {
    chainId: integer("chain_id").notNull(),
    token: text("token").notNull(),
    epoch: u256("epoch").notNull(),
    revenue: u256("revenue").notNull().default("0"),
    settled: boolean("settled").notNull().default(false),
    supply: u256("supply"),
    pot: u256("pot"),
    forfeited: u256("forfeited").notNull().default("0"),
  },
  (t) => [primaryKey({ columns: [t.chainId, t.token, t.epoch] })],
);

export const claims = pgTable("claims", {
  id: serial("id").primaryKey(),
  chainId: integer("chain_id").notNull(),
  tokenId: u256("token_id").notNull(),
  token: text("token").notNull(),
  amount: u256("amount").notNull(),
  to: text("to").notNull(),
  claimCursor: u256("claim_cursor").notNull(),
  txHash: text("tx_hash").notNull(),
  blockNumber: u256("block_number").notNull(),
});

export const adapters = pgTable(
  "adapters",
  {
    chainId: integer("chain_id").notNull(),
    adapter: text("adapter").notNull(),
    dapp: text("dapp").notNull(),
    mode: integer("mode").notNull(),
    committedBps: integer("committed_bps").notNull(),
    version: integer("version").notNull(),
    termsHash: text("terms_hash").notNull(),
    active: boolean("active").notNull().default(true),
  },
  (t) => [primaryKey({ columns: [t.chainId, t.adapter] })],
);

export const contributions = pgTable("contributions", {
  id: serial("id").primaryKey(),
  chainId: integer("chain_id").notNull(),
  adapter: text("adapter").notNull(),
  token: text("token").notNull(),
  amount: u256("amount").notNull(),
  blockNumber: u256("block_number").notNull(),
  txHash: text("tx_hash").notNull(),
});

export const protocolStats = pgTable(
  "protocol_stats",
  {
    chainId: integer("chain_id").notNull(),
    day: text("day").notNull(),
    totalLocked: u256("total_locked").notNull().default("0"),
    epochRevenueWxdc: u256("epoch_revenue_wxdc").notNull().default("0"),
    epochRevenueUsdc: u256("epoch_revenue_usdc").notNull().default("0"),
    positionCount: integer("position_count").notNull().default(0),
  },
  (t) => [primaryKey({ columns: [t.chainId, t.day] })],
);

export type SyncCursor = typeof syncCursors.$inferSelect;
export type Position = typeof positions.$inferSelect;
export type PositionEvent = typeof positionEvents.$inferSelect;
export type Epoch = typeof epochs.$inferSelect;
export type Claim = typeof claims.$inferSelect;
export type Adapter = typeof adapters.$inferSelect;
export type Contribution = typeof contributions.$inferSelect;
export type ProtocolStat = typeof protocolStats.$inferSelect;
