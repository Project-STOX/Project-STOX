from datetime import UTC, datetime, timedelta
from uuid import uuid4

import jwt

from app.core.config import get_settings

settings = get_settings()


def _base_claims(user_id: int, role: str, token_type: str, expires_delta: timedelta) -> dict[str, str | int]:
    now = datetime.now(UTC)
    return {
        "sub": str(user_id),
        "role": role,
        "type": token_type,
        "jti": str(uuid4()),
        "iat": int(now.timestamp()),
        "exp": int((now + expires_delta).timestamp()),
    }


def create_access_token(user_id: int, role: str) -> str:
    claims = _base_claims(
        user_id=user_id,
        role=role,
        token_type="access",
        expires_delta=timedelta(minutes=settings.access_token_expire_minutes),
    )
    return jwt.encode(claims, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def create_refresh_token(user_id: int, role: str) -> str:
    claims = _base_claims(
        user_id=user_id,
        role=role,
        token_type="refresh",
        expires_delta=timedelta(days=settings.refresh_token_expire_days),
    )
    return jwt.encode(claims, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def decode_token(token: str) -> dict:
    return jwt.decode(token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
