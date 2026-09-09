CREATE TABLE "adapters" (
	"chain_id" integer NOT NULL,
	"adapter" text NOT NULL,
	"dapp" text NOT NULL,
	"mode" integer NOT NULL,
	"committed_bps" integer NOT NULL,
	"version" integer NOT NULL,
	"terms_hash" text NOT NULL,
	"active" boolean DEFAULT true NOT NULL,
	CONSTRAINT "adapters_chain_id_adapter_pk" PRIMARY KEY("chain_id","adapter")
);
--> statement-breakpoint
CREATE TABLE "claims" (
	"id" serial PRIMARY KEY NOT NULL,
	"chain_id" integer NOT NULL,
	"token_id" numeric(78, 0) NOT NULL,
	"token" text NOT NULL,
	"amount" numeric(78, 0) NOT NULL,
	"to" text NOT NULL,
	"claim_cursor" numeric(78, 0) NOT NULL,
	"tx_hash" text NOT NULL,
	"block_number" numeric(78, 0) NOT NULL
);
--> statement-breakpoint
CREATE TABLE "contributions" (
	"id" serial PRIMARY KEY NOT NULL,
	"chain_id" integer NOT NULL,
	"adapter" text NOT NULL,
	"token" text NOT NULL,
	"amount" numeric(78, 0) NOT NULL,
	"block_number" numeric(78, 0) NOT NULL,
	"tx_hash" text NOT NULL
);
--> statement-breakpoint
CREATE TABLE "epochs" (
	"chain_id" integer NOT NULL,
	"token" text NOT NULL,
	"epoch" numeric(78, 0) NOT NULL,
	"revenue" numeric(78, 0) DEFAULT '0' NOT NULL,
	"settled" boolean DEFAULT false NOT NULL,
	"supply" numeric(78, 0),
	"pot" numeric(78, 0),
	"forfeited" numeric(78, 0) DEFAULT '0' NOT NULL,
	CONSTRAINT "epochs_chain_id_token_epoch_pk" PRIMARY KEY("chain_id","token","epoch")
);
--> statement-breakpoint
CREATE TABLE "position_events" (
	"id" serial PRIMARY KEY NOT NULL,
	"chain_id" integer NOT NULL,
	"token_id" numeric(78, 0) NOT NULL,
	"event_name" text NOT NULL,
	"tx_hash" text NOT NULL,
	"log_index" integer NOT NULL,
	"block_number" numeric(78, 0) NOT NULL,
	"payload" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "position_events_chain_tx_log_uidx" UNIQUE("chain_id","tx_hash","log_index")
);
--> statement-breakpoint
CREATE TABLE "positions" (
	"chain_id" integer NOT NULL,
	"token_id" numeric(78, 0) NOT NULL,
	"owner" text NOT NULL,
	"amount" numeric(78, 0) NOT NULL,
	"unlock_time" numeric(78, 0) NOT NULL,
	"penalty_cap_bps" integer NOT NULL,
	"closed" boolean DEFAULT false NOT NULL,
	"first_eligible_epoch" numeric(78, 0),
	"exit_epoch" numeric(78, 0),
	"created_at_block" numeric(78, 0) NOT NULL,
	"updated_at_block" numeric(78, 0) NOT NULL,
	CONSTRAINT "positions_chain_id_token_id_pk" PRIMARY KEY("chain_id","token_id")
);
--> statement-breakpoint
CREATE TABLE "protocol_stats" (
	"chain_id" integer NOT NULL,
	"day" text NOT NULL,
	"total_locked" numeric(78, 0) DEFAULT '0' NOT NULL,
	"epoch_revenue_wxdc" numeric(78, 0) DEFAULT '0' NOT NULL,
	"epoch_revenue_usdc" numeric(78, 0) DEFAULT '0' NOT NULL,
	"position_count" integer DEFAULT 0 NOT NULL,
	CONSTRAINT "protocol_stats_chain_id_day_pk" PRIMARY KEY("chain_id","day")
);
--> statement-breakpoint
CREATE TABLE "sync_cursors" (
	"chain_id" integer NOT NULL,
	"contract_key" text NOT NULL,
	"from_block" numeric(78, 0) NOT NULL,
	CONSTRAINT "sync_cursors_chain_id_contract_key_pk" PRIMARY KEY("chain_id","contract_key")
);
