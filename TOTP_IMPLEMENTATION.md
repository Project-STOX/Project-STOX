# TOTP Implementation Documentation

## Overview
This document describes the implementation of Time-based One-Time Password (TOTP) authentication in STOX. TOTP is a time-based, standards-compliant 2FA method that works with any authenticator app (Google Authenticator, Microsoft Authenticator, Authy, Ente Auth, etc.).

## Database Changes

### Migration File
Location: `migrations/001_add_totp_support.sql`

Three new columns have been added to the `user` table:

| Column | Type | Description |
|--------|------|-------------|
| `totp_secret` | `VARCHAR(32)` | Stores the base32-encoded TOTP secret key. This is the shared secret used to generate codes. Null if TOTP is not enabled. |
| `totp_enabled` | `BOOLEAN` | Flag indicating whether TOTP is enabled for this user. Defaults to `false`. |
| `backup_codes` | `TEXT[]` | PostgreSQL array of backup codes for account recovery if the user loses access to their authenticator app. These are single-use codes. |

#### Rollback
If TOTP needs to be removed, run:
```sql
ALTER TABLE "user" DROP COLUMN totp_secret;
ALTER TABLE "user" DROP COLUMN totp_enabled;
ALTER TABLE "user" DROP COLUMN backup_codes;
```

## Backend Implementation

### New Dependencies
Added to `requirements.txt`:
- `qrcode[pil]` - For generating QR codes that users scan with their authenticator app

### New Files

#### `app/services/totp_service.py`
Service class handling all TOTP operations:
- `generate_secret()` - Generates a new random TOTP secret
- `generate_backup_codes()` - Creates 10 backup codes for recovery
- `generate_qr_code(email, secret)` - Creates a QR code for scanning
- `verify_totp_code(secret, code)` - Validates a TOTP code against the secret
- `use_backup_code(backup_codes, code)` - Validates and consumes a backup code

### Updated Files

#### `app/models/user.py`
Added three TOTP-related fields to the User model:
```python
totp_secret: Mapped[str | None]
totp_enabled: Mapped[bool]
backup_codes: Mapped[list[str] | None]
```

#### `app/schemas/auth.py`
Added new request/response schemas:
- `TOTPSetupResponse` - Returns secret, QR code, and backup codes
- `TOTPVerifySetupRequest` - 6-digit code for verification
- `TOTPVerifySetupResponse` - Confirmation after setup
- `TOTPDisableRequest` - Password required to disable TOTP

#### `app/routes/auth_routes.py`
Added three new endpoints:
- `POST /auth/totp/setup` - Initiate TOTP setup (returns QR code)
- `POST /auth/totp/verify-setup` - Verify setup with 6-digit code
- `POST /auth/totp/disable` - Disable TOTP (requires password)

#### `app/services/auth_service.py`
- `setup_totp(db, user)` - Generate and return setup data
- `verify_totp_setup(db, user, code)` - Enable TOTP after verification
- `disable_totp(db, user, password)` - Disable TOTP
- `generate_totp_challenge(db, user_id)` - Create challenge for login
- Updated `verify_2fa_and_issue_tokens()` - Now handles both TOTP and email-based 2FA
- Updated `login_step_one()` - Prioritizes TOTP over email 2FA

### Authentication Flow

#### Login with TOTP
1. User enters email/password
2. Backend checks if user has TOTP enabled
3. If yes, returns `{"login_challenge": "...", "is_totp": true, "message": "..."}`
4. Frontend shows TOTP input screen
5. User enters 6-digit code OR uses backup code
6. Backend validates against TOTP secret
7. If valid, returns access/refresh tokens

#### TOTP vs Email 2FA
- **Priority**: TOTP is checked first. If enabled, it's required.
- **Fallback**: Users can use backup codes if they lose their phone
- **Email 2FA**: Still supported for users without TOTP
- **Both**: Users can have both enabled; TOTP takes precedence

## Frontend Implementation

### New Files

#### `lib/views/totp_setup_view.dart`
Complete TOTP setup flow:
- Displays QR code for scanning
- Shows secret key for manual entry
- Displays 10 backup codes
- Requires 6-digit verification code
- Navigates back on success

#### `lib/controllers/auth_controller.dart` (Updated)
New methods:
- `setupTOTP()` - Initiate setup
- `verifyTOTPSetup(code)` - Verify and enable
- `disableTOTP(password)` - Disable TOTP

#### `lib/services/api/auth_api_service.dart` (Updated)
New API methods:
- `setupTOTP()` - Call `/auth/totp/setup`
- `verifyTOTPSetup(code)` - Call `/auth/totp/verify-setup`
- `disableTOTP(password)` - Call `/auth/totp/disable`

#### `lib/views/two_factor_view.dart` (Updated)
Enhanced to support both TOTP and email 2FA:
- Detects mode via `isTotp` parameter
- Shows appropriate labels and instructions
- Supports TOTP (no resend button) and email (with resend)
- Shows backup code guidance for TOTP

#### `lib/views/login_view.dart` (Updated)
Updated login flow:
- Checks for `is_totp` flag in response
- Passes `isTotp` to `TwoFactorView`

## Security Considerations

### TOTP Seed Storage
- Seeds are 32-character base32 strings (160 bits of entropy)
- Stored in database, not in code or config
- Should be protected like passwords in production

### Backup Codes
- 10 codes per user, 8 characters each
- Single-use only (consumed when used)
- Must be saved in a safe place by user
- Displayed only once during setup

### Timing Window
- Current code is valid for 30 seconds (RFC 6238 standard)
- Implementation allows 1-window drift for synchronization tolerance
- Prevents replay attacks with time-based validation

### Rate Limiting
- Same 5-minute challenge expiration as email 2FA
- Login challenge tokens stored in memory (not persistent)
- Consider moving to database for production

## Testing Checklist

### Backend
- [ ] Run migration on test database
- [ ] Test TOTP secret generation (randomness)
- [ ] Test QR code generation (scanning with phone)
- [ ] Test backup code generation (10 codes, uniqueness)
- [ ] Test code verification (valid/invalid codes)
- [ ] Test backup code usage (single-use enforcement)
- [ ] Test login with TOTP enabled user
- [ ] Test login with TOTP and backup code
- [ ] Test setup flow (initiate, verify, enable)
- [ ] Test disable flow (password verification)
- [ ] Test priority: TOTP before email 2FA

### Frontend
- [ ] Test TOTP setup page loads QR code
- [ ] Test QR code scans into authenticator app
- [ ] Test manual secret entry
- [ ] Test backup codes display correctly
- [ ] Test verification with valid code
- [ ] Test verification with invalid code
- [ ] Test backup code usage during login
- [ ] Test disable TOTP (password required)
- [ ] Test app switching (Ente Auth, Google Authenticator, etc.)

## Supported Authenticator Apps
TOTP works with any RFC 6238 compliant authenticator:
- Google Authenticator
- Microsoft Authenticator
- Authy
- Ente Auth
- FreeOTP
- Twilio Authy
- 1Password
- LastPass Authenticator
- And many others

## Known Limitations

### Current Implementation
1. **In-memory challenge storage**: Login challenges are stored in memory, not persisted to database. This means challenges are lost on server restart. For production, consider:
   - Storing in Redis
   - Storing in database with TTL
   - Using a persistent session store

2. **No TOTP enforcement policy**: Users can enable/disable TOTP anytime. Consider adding:
   - Admin-enforced TOTP requirement
   - Mandatory 2FA after first login
   - Audit logging for 2FA changes

3. **Backup code regeneration**: Users cannot regenerate backup codes. Consider adding:
   - Endpoint to regenerate codes
   - List remaining codes count
   - Warning when codes are running low

## Migration Notes for Supabase Free Tier

### Compatibility
✅ **Fully compatible** with Supabase free tier:
- No additional API costs (TOTP is local computation)
- No rate limiting (doesn't use Supabase OTP API)
- Minimal storage (32 bytes per secret + backup codes)
- No dependency on Supabase's email service

### Advantages over Email 2FA on Free Tier
- No Supabase OTP API calls (bypasses rate limits)
- No email sending (avoids rate limits)
- Instant code generation
- User owns the code in their authenticator

## Future Enhancements
- [ ] Device fingerprinting for trusted devices
- [ ] Admin enforcement of TOTP
- [ ] Backup code management UI
- [ ] TOTP recovery codes export
- [ ] Per-session code history audit log
- [ ] WebAuthn/FIDO2 support

## Deployment Checklist

Before deploying to production:
- [ ] Run database migration
- [ ] Test login flow with TOTP user
- [ ] Test login flow with backup codes
- [ ] Verify QR codes scan correctly
- [ ] Check error handling for invalid codes
- [ ] Ensure secret seeds use cryptographically random generation
- [ ] Test on multiple authenticator apps
- [ ] Update user documentation
- [ ] Add TOTP setup to onboarding
- [ ] Monitor 2FA adoption metrics
