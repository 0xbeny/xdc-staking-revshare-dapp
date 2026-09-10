ALTER TABLE "contributions" ADD COLUMN IF NOT EXISTS "epoch" numeric(78, 0);
--> statement-breakpoint
ALTER TABLE "contributions" ADD COLUMN IF NOT EXISTS "log_index" integer DEFAULT 0 NOT NULL;
