from datetime import UTC, datetime, timedelta
from secrets import token_urlsafe

from fastapi import HTTPException, status
from sqlalchemy import or_, select
from sqlalchemy.orm import Session, selectinload

from app.core.config import get_settings
from app.core.security.input_sanitizer import sanitize_text
from app.core.security.jwt import create_access_token, create_refresh_token, decode_token
from app.core.security.password import hash_password, verify_password
from app.models.audit_log import AuditLog
from app.models.refresh_token import RefreshToken
from app.models.role import Role
from app.models.role_permission import RolePermission
from app.models.user import User
from app.schemas.auth import LoginRequest, TokenPairResponse
from app.schemas.user import UserRead
from app.services.audit_service import AuditService

settings = get_settings()

_LOGIN_CHALLENGES: dict[str, dict[str, int | str]] = {}


def _utc_now() -> datetime:
    return datetime.now(UTC)


class AuthService:
    @staticmethod
    def _get_user_with_role(db: Session, user_id: int) -> User | None:
        stmt = (
            select(User)
            .where(User.id == user_id)
            .options(
                selectinload(User.role)
                .selectinload(Role.role_permissions)
                .selectinload(RolePermission.permission)
            )
        )
        return db.scalar(stmt)

    @staticmethod
    def login_step_one(db: Session, payload: LoginRequest) -> dict[str, object]:
        identifier = sanitize_text(payload.email.strip(), max_length=255)
        normalized = identifier.lower()
        stmt = (
            select(User)
            .where(or_(User.email == normalized, User.full_name == identifier))
            .options(selectinload(User.role))
        )
        user = db.scalar(stmt)
        if user is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
        
        if not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED, 
                detail="User profile has been deactivated. Please contact the administrator."
            )

        if not verify_password(payload.password, user.password_hash):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")

        if user.role is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="User has no assigned role. Please contact an administrator.",
            )

        if user.tfa_active:
            return AuthService.generate_2fa_challenge(db, user.id)

        # The current schema has no trusted OTP seed/challenge store; issue backend tokens directly.
        token_pair = AuthService._issue_token_pair(db, user)
        AuditService.write_log(
            db,
            user_id=user.id,
            action="Login",
            entity_type="sessions",
            entity_id=user.id,
        )
        return token_pair.model_dump()

    @staticmethod
    def generate_2fa_challenge(db: Session, user_id: int) -> dict:
        user = db.get(User, user_id)
        if not user or not user.is_active:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
        
        challenge = token_urlsafe(32)
        
        # In a real Supabase integration, we would call Supabase Auth API here.
        # If supabase_url and supabase_anon_key are configured, we attempt an OTP request.
        if settings.supabase_url and settings.supabase_anon_key:
            try:
                import json
                from urllib import request, error

                url = f"{settings.supabase_url.rstrip('/')}/auth/v1/otp"
                headers = {
                    "apikey": settings.supabase_anon_key,
                    "Content-Type": "application/json",
                }
                data = json.dumps({"email": user.email, "create_user": False}).encode("utf-8")
                
                req = request.Request(url, data=data, headers=headers, method="POST")
                with request.urlopen(req, timeout=5) as response:
                    if response.status >= 200 and response.status < 300:
                        # Supabase doesn't return the code to us (it sends it directly).
                        # We would need to verify it via Supabase as well.
                        # For this hybrid implementation, we store a placeholder or wait for verify logic.
                        pass
            except error.HTTPError as he:
                if he.code == 429:
                    raise HTTPException(
                        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                        detail="Supabase free limit exceeded. Please try again later or use the default code."
                    )
                print(f"Failed to call Supabase OTP ({he.code}): {he.read().decode('utf-8')}")
            except Exception as e:
                print(f"Unexpected error calling Supabase OTP: {e}")

        import random
        # Generate a random 6-digit code as a primary method or fallback
        code = str(random.randint(100000, 999999))
        
        # Log the code to terminal as requested for development/debugging
        print(f"\n{'='*40}")
        print(f"  2FA LOGIN CHALLENGE GENERATED")
        print(f"  User: {user.email}")
        print(f"  OTP Code: {code}")
        print(f"{'='*40}\n")
        
        _LOGIN_CHALLENGES[challenge] = {
            "user_id": user_id,
            "code": code,
            "expire_at": int((_utc_now() + timedelta(minutes=settings.login_challenge_expire_minutes)).timestamp())
        }
        
        return {
            "login_challenge": challenge,
            "message": f"A 2FA code has been sent to {user.email}. Please check your inbox or the backend terminal."
        }

    @staticmethod
    def verify_2fa_and_issue_tokens(db: Session, login_challenge: str, code: str) -> TokenPairResponse:
        challenge_data = _LOGIN_CHALLENGES.get(login_challenge)
        if not challenge_data:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired login challenge",
            )
        
        # Security Check: Standard check against stored code
        # In a real Supabase-only flow, we would ONLY verify with Supabase.
        # Here we allow either for flexibility.
        code = code.strip()
        is_valid = (code == challenge_data["code"])
        
        user = AuthService._get_user_with_role(db, int(challenge_data["user_id"]))
        if user is None or not user.is_active:
            _LOGIN_CHALLENGES.pop(login_challenge, None)
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found or inactive")

        # If Supabase is configured, attempt to verify the token there as well
        if settings.supabase_url and settings.supabase_anon_key:
            try:
                import json
                from urllib import request, error

                url = f"{settings.supabase_url.rstrip('/')}/auth/v1/verify"
                headers = {
                    "apikey": settings.supabase_anon_key,
                    "Content-Type": "application/json",
                }
                # Try with 'magiclink' first as it is the standard for OTP emails in Supabase.
                # If it fails, we fall back to 'email' or other types.
                for verify_type in ["magiclink", "email"]:
                    payload = {
                        "email": user.email, 
                        "token": code, 
                        "type": verify_type
                    }
                    data = json.dumps(payload).encode("utf-8")
                    
                    req = request.Request(url, data=data, headers=headers, method="POST")
                    try:
                        with request.urlopen(req, timeout=10) as response:
                            if response.status >= 200 and response.status < 300:
                                is_valid = True
                                break # Success!
                    except error.HTTPError:
                        continue # Try next type
            except Exception as e:
                print(f"Unexpected error during Supabase verification: {e}")
        
        if int(challenge_data["expire_at"]) < int(_utc_now().timestamp()):
            _LOGIN_CHALLENGES.pop(login_challenge, None)
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired login challenge",
            )

        if not is_valid:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid 2FA code")

        _LOGIN_CHALLENGES.pop(login_challenge, None)
        token_pair = AuthService._issue_token_pair(db, user)
        AuditService.write_log(
            db,
            user_id=user.id,
            action="Login (2FA)",
            entity_type="sessions",
            entity_id=user.id,
        )
        return token_pair

    @staticmethod
    def refresh_tokens(db: Session, raw_refresh_token: str) -> TokenPairResponse:
        payload = AuthService._decode_refresh_token_or_401(raw_refresh_token)
        user = AuthService._get_user_with_role(db, int(payload["sub"]))
        if user is None or not user.is_active:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token")

        stored_token = db.scalar(select(RefreshToken).where(RefreshToken.token == raw_refresh_token))
        if stored_token is None or not stored_token.is_active or stored_token.created_at.replace(tzinfo=None) + timedelta(days=settings.refresh_token_expire_days) <= _utc_now().replace(tzinfo=None):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token")

        stored_token.is_active = False
        db.commit()
        return AuthService._issue_token_pair(db, user)

    @staticmethod
    def logout(db: Session, raw_refresh_token: str) -> None:
        # First, find the session associated with this token to identify the user
        token = db.scalar(select(RefreshToken).where(RefreshToken.token == raw_refresh_token))
        if token is not None:
            user_id = token.user_id
            # Delete all sessions for this specific user (Global Logout)
            db.query(RefreshToken).filter(RefreshToken.user_id == user_id).delete(synchronize_session=False)
            db.commit()
            AuditService.write_log(
                db,
                user_id=user_id,
                action="Logout",
                entity_type="sessions",
                entity_id=user_id,
            )

    @staticmethod
    def _decode_refresh_token_or_401(raw_refresh_token: str) -> dict:
        try:
            payload = decode_token(raw_refresh_token)
        except Exception as exc:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token") from exc
        if payload.get("type") != "refresh":
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token")
        if "sub" not in payload or "jti" not in payload:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token")
        return payload

    @staticmethod
    def _issue_token_pair(db: Session, user: User) -> TokenPairResponse:
        access_token = create_access_token(user.id, user.role_name)
        refresh_token = create_refresh_token(user.id, user.role_name)

        refresh_entity = RefreshToken(
            user_id=user.id,
            token=refresh_token,
            created_at=_utc_now().replace(tzinfo=None),
            is_active=True,
        )
        db.add(refresh_entity)
        db.commit()
        return TokenPairResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            user=UserRead.from_user(user),
        )

    @staticmethod
    def change_password(
        db: Session,
        *,
        user: User,
        current_password: str,
        new_password: str,
        two_factor_code: str | None = None,
    ) -> None:
        if not verify_password(current_password, user.password_hash):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid credentials")
        if current_password == new_password:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="New password must be different from current password",
            )
        user.password_hash = hash_password(new_password)
        db.commit()
        AuditService.write_log(
            db,
            user_id=user.id,
            action="Changed Password",
            entity_type="users",
            entity_id=user.id,
        )

    @staticmethod
    def check_user_password(user: User, password: str) -> bool:
        """Utility for verifying password before high security actions without altering session."""
        from app.core.security.password import verify_password
        return verify_password(password, user.password_hash)

    @staticmethod
    def delete_account(db: Session, *, user: User, two_factor_code: str | None = None) -> None:
        user_id = user.id
        # Log before deletion to avoid foreign key issues
        AuditService.write_log(
            db,
            user_id=user_id,
            action="Deleted Account",
            entity_type="users",
            entity_id=user_id,
        )
        db.query(RefreshToken).filter(RefreshToken.user_id == user_id).delete(synchronize_session=False)
        db.query(AuditLog).filter(AuditLog.user_id == user_id).update(
            {"user_id": None}, synchronize_session=False
        )
        db.delete(user)
        db.commit()
