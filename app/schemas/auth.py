from pydantic import BaseModel, Field

from app.schemas.user import UserRead


class LoginRequest(BaseModel):
    email: str = Field(min_length=1, max_length=255)
    password: str = Field(max_length=128)


class LoginChallengeResponse(BaseModel):
    login_challenge: str
    message: str = "2FA verification required"


class Verify2FARequest(BaseModel):
    login_challenge: str
    code: str = Field(min_length=1, max_length=10)

class Generate2FARequest(BaseModel):
    user_id: int | None = None
    email: str | None = Field(None, max_length=255)

class RefreshRequest(BaseModel):
    refresh_token: str


class LogoutRequest(BaseModel):
    refresh_token: str


class TokenPairResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: UserRead


class ChangePasswordRequest(BaseModel):
    current_password: str = Field(min_length=8, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)
    two_factor_code: str | None = None


class DeleteAccountRequest(BaseModel):
    two_factor_code: str | None = None


# TOTP Schemas
class TOTPSetupResponse(BaseModel):
    """Response for TOTP setup initiation."""
    secret: str
    qr_code: str
    backup_codes: list[str]
    message: str = "Scan the QR code with your authenticator app. Save the backup codes in a safe place."


class TOTPVerifySetupRequest(BaseModel):
    """Request to verify TOTP setup by providing a code."""
    totp_code: str = Field(min_length=6, max_length=6, pattern=r"^\d{6}$")


class TOTPVerifySetupResponse(BaseModel):
    """Response after successful TOTP setup verification."""
    message: str = "TOTP has been enabled successfully"
    backup_codes: list[str]


class TOTPDisableRequest(BaseModel):
    """Request to disable TOTP."""
    password: str = Field(min_length=8, max_length=128)

