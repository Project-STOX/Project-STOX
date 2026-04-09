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
