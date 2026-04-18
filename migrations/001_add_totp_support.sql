-- Migration: Add TOTP Support
-- Date: 2026-04-18
-- Author: tsavid
-- Purpose: Add Time-based One-Time Password (TOTP) authentication support
-- Description: Adds 3 columns to support TOTP as an alternative 2FA method
-- Database: Supabase (PostgreSQL)

-- Add TOTP secret column (stores the base32 encoded secret key)
ALTER TABLE "user" ADD COLUMN totp_secret VARCHAR(32) NULL;

-- Add TOTP enabled flag (tracks if user has TOTP enabled)
ALTER TABLE "user" ADD COLUMN totp_enabled BOOLEAN DEFAULT FALSE NOT NULL;

-- Add backup codes column (JSON array of recovery codes for account recovery)
ALTER TABLE "user" ADD COLUMN backup_codes TEXT[] NULL;

-- ROLLBACK: If TOTP needs to be removed, run:
-- ALTER TABLE "user" DROP COLUMN totp_secret;
-- ALTER TABLE "user" DROP COLUMN totp_enabled;
-- ALTER TABLE "user" DROP COLUMN backup_codes;
