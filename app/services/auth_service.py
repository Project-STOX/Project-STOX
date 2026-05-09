from datetime import UTC, datetime, timedelta
import json
import logging
import random
import ssl
from secrets import token_urlsafe
from urllib.parse import urlencode, urlparse
from urllib import error, request

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
from app.schemas.auth import LoginRequest, TokenPairResponse, TOTPSetupResponse, TOTPVerifySetupResponse
from app.schemas.user import UserRead
from app.services.audit_service import AuditService
from app.services.totp_service import TOTPService

settings = get_settings()
_log = logging.getLogger(__name__)

_LOGIN_CHALLENGES: dict[str, dict[str, object]] = {}
_PENDING_SETUPS: dict[int, dict[str, object]] = {}
_PENDING_EMAIL_VERIFICATIONS: dict[str, dict[str, object]] = {}


def _utc_now() -> datetime:
    return datetime.now(UTC)


class AuthService:
    @staticmethod
    def _supabase_ssl_context() -> ssl.SSLContext:
        """Return an SSL context with a reliable CA bundle for HTTPS calls."""
        context = ssl.create_default_context()
        try:
            import certifi

            return ssl.create_default_context(cafile=certifi.where())
        except Exception:
            # Fall back to platform certificates if certifi is unavailable.
            return context

    @staticmethod
    def _supabase_base_url() -> str:
        url = settings.supabase_url.strip()
        # Defensive fix for a common typo seen in local env files.
        if url.startswith("hhttps://"):
            url = "https://" + url[len("hhttps://"):]
        return url.rstrip("/")

    @staticmethod
    def _is_valid_supabase_url() -> bool:
        parsed = urlparse(AuthService._supabase_base_url())
        return parsed.scheme in {"http", "https"} and bool(parsed.netloc)

    @staticmethod
    def _is_supabase_auth_configured() -> bool:
        return bool(
            AuthService._supabase_base_url()
            and settings.supabase_anon_key.strip()
            and AuthService._is_valid_supabase_url()
        )

    @staticmethod
    def _supabase_headers() -> dict[str, str]:
        key = settings.supabase_anon_key.strip()
        return {
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        }

    @staticmethod
    def _send_supabase_email_otp(email_address: str, redirect_to: str | None = None) -> None:
        if not AuthService._is_valid_supabase_url():
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Invalid SUPABASE_URL in backend configuration.",
            )

        url = f"{AuthService._supabase_base_url()}/auth/v1/otp"
        payload = {
            "email": email_address,
            "create_user": settings.supabase_otp_create_user,
        }
        if redirect_to:
            payload["redirect_to"] = redirect_to
        data = json.dumps(payload).encode("utf-8")

        req = request.Request(
            url,
            data=data,
            headers=AuthService._supabase_headers(),
            method="POST",
        )

        try:
            with request.urlopen(
                req,
                timeout=settings.supabase_auth_timeout_seconds,
                context=AuthService._supabase_ssl_context(),
            ) as response:
                if response.status < 200 or response.status >= 300:
                    raise HTTPException(
                        status_code=status.HTTP_502_BAD_GATEWAY,
                        detail="Failed to send 2FA email via Supabase.",
                    )
        except error.HTTPError as exc:
            raw_body = exc.read().decode("utf-8", errors="ignore")
            _log.warning("Supabase OTP request failed (%s): %s", exc.code, raw_body)
            body_json: dict[str, object] = {}
            try:
                body_json = json.loads(raw_body) if raw_body else {}
            except Exception:
                body_json = {}

            body_code = str(body_json.get("error_code", ""))
            body_msg = str(body_json.get("msg", ""))

            if exc.code == 429:
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail="Too many OTP requests. Please wait before trying again.",
                ) from exc

            if exc.code == 422 and (
                body_code == "otp_disabled" or "signups not allowed for otp" in body_msg.lower()
            ):
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail=(
                        "Supabase Email OTP is currently disabled for this project. "
                        "Enable Email provider and OTP/signups in Supabase Auth settings."
                    ),
                ) from exc

            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Supabase rejected the OTP email request. Check Supabase Auth email settings and API key.",
            ) from exc
        except error.URLError as exc:
            _log.warning("Supabase OTP request network failure: %s", exc)
            if "unknown url type" in str(exc.reason).lower():
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="Invalid SUPABASE_URL in backend configuration.",
                ) from exc
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Could not reach Supabase to send the OTP email.",
            ) from exc

    @staticmethod
    def _send_supabase_signup_confirmation(email_address: str, redirect_to: str | None = None) -> None:
        if not AuthService._is_valid_supabase_url():
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Invalid SUPABASE_URL in backend configuration.",
            )

        signup_password = f"{token_urlsafe(32)}Aa1!"
        base_url = f"{AuthService._supabase_base_url()}/auth/v1/signup"
        if redirect_to:
            base_url = f"{base_url}?{urlencode({'redirect_to': redirect_to})}"

        payload = {
            "email": email_address,
            "password": signup_password,
        }
        data = json.dumps(payload).encode("utf-8")

        req = request.Request(
            base_url,
            data=data,
            headers=AuthService._supabase_headers(),
            method="POST",
        )

        try:
            with request.urlopen(
                req,
                timeout=settings.supabase_auth_timeout_seconds,
                context=AuthService._supabase_ssl_context(),
            ) as response:
                if response.status < 200 or response.status >= 300:
                    raise HTTPException(
                        status_code=status.HTTP_502_BAD_GATEWAY,
                        detail="Failed to send email verification link via Supabase.",
                    )
        except error.HTTPError as exc:
            raw_body = exc.read().decode("utf-8", errors="ignore")
            _log.warning("Supabase signup request failed (%s): %s", exc.code, raw_body)
            body_json: dict[str, object] = {}
            try:
                body_json = json.loads(raw_body) if raw_body else {}
            except Exception:
                body_json = {}

            body_code = str(body_json.get("error_code", ""))
            body_msg = str(body_json.get("msg", ""))

            if exc.code == 429:
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail="Too many verification email requests. Please wait before trying again.",
                ) from exc

            if exc.code in {400, 422} and (
                body_code == "user_already_exists"
                or body_code == "email_exists"
                or "user already registered" in body_msg.lower()
                or "already registered" in body_msg.lower()
            ):
                resend_url = f"{AuthService._supabase_base_url()}/auth/v1/resend"
                resend_payload = {
                    "email": email_address,
                    "type": "signup",
                }
                if redirect_to:
                    resend_payload["emailRedirectTo"] = redirect_to

                resend_req = request.Request(
                    resend_url,
                    data=json.dumps(resend_payload).encode("utf-8"),
                    headers=AuthService._supabase_headers(),
                    method="POST",
                )

                try:
                    with request.urlopen(
                        resend_req,
                        timeout=settings.supabase_auth_timeout_seconds,
                        context=AuthService._supabase_ssl_context(),
                    ) as response:
                        if response.status < 200 or response.status >= 300:
                            raise HTTPException(
                                status_code=status.HTTP_502_BAD_GATEWAY,
                                detail="Failed to resend email verification link via Supabase.",
                            )
                        return
                except error.HTTPError as resend_exc:
                    resend_raw_body = resend_exc.read().decode("utf-8", errors="ignore")
                    _log.warning("Supabase resend request failed (%s): %s", resend_exc.code, resend_raw_body)
                    if resend_exc.code == 429:
                        raise HTTPException(
                            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                            detail="Too many verification email requests. Please wait before trying again.",
                        ) from resend_exc
                    raise HTTPException(
                        status_code=status.HTTP_502_BAD_GATEWAY,
                        detail="Supabase rejected the verification resend request. Check Supabase Auth email settings and API key.",
                    ) from resend_exc
                except error.URLError as resend_exc:
                    _log.warning("Supabase resend request network failure: %s", resend_exc)
                    if "unknown url type" in str(resend_exc.reason).lower():
                        raise HTTPException(
                            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                            detail="Invalid SUPABASE_URL in backend configuration.",
                        ) from resend_exc
                    raise HTTPException(
                        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                        detail="Could not reach Supabase to resend the verification link.",
                    ) from resend_exc

            if exc.code == 422 and (
                body_code == "signup_disabled" or "signups not allowed" in body_msg.lower()
            ):
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail=(
                        "Supabase signup-based verification is currently disabled for this project. "
                        "Enable email signups in Supabase Auth settings."
                    ),
                ) from exc

            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Supabase rejected the verification link request. Check Supabase Auth email settings and API key.",
            ) from exc
        except error.URLError as exc:
            _log.warning("Supabase signup request network failure: %s", exc)
            if "unknown url type" in str(exc.reason).lower():
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="Invalid SUPABASE_URL in backend configuration.",
                ) from exc
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Could not reach Supabase to send the verification link.",
            ) from exc

    @staticmethod
    def _verify_supabase_email_otp(email_address: str, code: str) -> bool:
        url = f"{AuthService._supabase_base_url()}/auth/v1/verify"
        payload = {
            "email": email_address,
            "token": code,
            "type": "email",
        }
        data = json.dumps(payload).encode("utf-8")

        req = request.Request(
            url,
            data=data,
            headers=AuthService._supabase_headers(),
            method="POST",
        )

        try:
            with request.urlopen(
                req,
                timeout=settings.supabase_auth_timeout_seconds,
                context=AuthService._supabase_ssl_context(),
            ) as response:
                return 200 <= response.status < 300
        except error.HTTPError as exc:
            # Invalid/expired token is expected as 4xx and should simply fail verification.
            if 400 <= exc.code < 500:
                return False
            raw_body = exc.read().decode("utf-8", errors="ignore")
            _log.warning("Supabase OTP verify failed (%s): %s", exc.code, raw_body)
            return False
        except Exception as exc:
            _log.warning("Unexpected Supabase OTP verify failure: %s", exc)
            return False

    @staticmethod
    def _fetch_supabase_user(access_token: str) -> dict[str, object]:
        url = f"{AuthService._supabase_base_url()}/auth/v1/user"
        req = request.Request(
            url,
            headers={
                **AuthService._supabase_headers(),
                "Authorization": f"Bearer {access_token.strip()}",
            },
            method="GET",
        )

        try:
            with request.urlopen(
                req,
                timeout=settings.supabase_auth_timeout_seconds,
                context=AuthService._supabase_ssl_context(),
            ) as response:
                raw_body = response.read().decode("utf-8", errors="ignore")
                data = json.loads(raw_body) if raw_body else {}
                return data if isinstance(data, dict) else {}
        except error.HTTPError as exc:
            raw_body = exc.read().decode("utf-8", errors="ignore")
            _log.warning("Supabase user lookup failed (%s): %s", exc.code, raw_body)
            return {}
        except Exception as exc:
            _log.warning("Unexpected Supabase user lookup failure: %s", exc)
            return {}

    @staticmethod
    def send_email_verification(db: Session, user: User) -> None:
        if not AuthService._is_supabase_auth_configured():
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Supabase email verification is not configured on the backend.",
            )

        callback_url = f"{settings.backend_origin.rstrip('/')}/api/v1/auth/verify-email/callback"
        AuthService._send_supabase_signup_confirmation(user.email, redirect_to=callback_url)
        _PENDING_EMAIL_VERIFICATIONS[user.email.strip().lower()] = {
            "user_id": user.id,
            "expire_at": int((_utc_now() + timedelta(minutes=settings.login_challenge_expire_minutes)).timestamp()),
        }

    @staticmethod
    def verify_email_and_activate_user(
        db: Session,
        email: str | None = None,
        code: str | None = None,
        access_token: str | None = None,
    ) -> dict[str, str]:
        normalized_email = email.strip().lower() if email else None

        if access_token:
            supabase_user = AuthService._fetch_supabase_user(access_token)
            email_from_token = str(supabase_user.get("email", "")).strip().lower()
            if not email_from_token:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Invalid or expired verification session.",
                )
            normalized_email = email_from_token

        if not normalized_email:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="email or access_token is required",
            )

        pending = _PENDING_EMAIL_VERIFICATIONS.get(normalized_email)
        if access_token:
            pending = pending or {"expire_at": int((_utc_now() + timedelta(minutes=settings.login_challenge_expire_minutes)).timestamp())}
        else:
            if not pending:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="No pending email verification found for this account.",
                )

            if int(pending["expire_at"]) < int(_utc_now().timestamp()):
                _PENDING_EMAIL_VERIFICATIONS.pop(normalized_email, None)
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="The email verification request has expired. Please request a new verification email.",
                )

        user = db.scalar(select(User).where(User.email == normalized_email))
        if user is None:
            _PENDING_EMAIL_VERIFICATIONS.pop(normalized_email, None)
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

        if user.is_active:
            _PENDING_EMAIL_VERIFICATIONS.pop(normalized_email, None)
            return {"message": "Email is already verified."}

        if access_token:
            user.is_active = True
            db.commit()
            _PENDING_EMAIL_VERIFICATIONS.pop(normalized_email, None)
            return {"message": "Email verified successfully."}

        if not code or not AuthService._verify_supabase_email_otp(normalized_email, code.strip()):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired verification code.",
            )

        user.is_active = True
        db.commit()
        _PENDING_EMAIL_VERIFICATIONS.pop(normalized_email, None)
        return {"message": "Email verified successfully."}

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

        # Check TOTP first (preferred 2FA method), then fall back to email-based 2FA
        if user.totp_enabled:
            return AuthService.generate_totp_challenge(db, user.id)
        elif user.tfa_active:
            return AuthService.generate_2fa_challenge(db, user.id)

        # No 2FA enabled, issue backend tokens directly.
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

        if AuthService._is_supabase_auth_configured():
            AuthService._send_supabase_email_otp(user.email)
            provider = "supabase"
            code: str | None = None
        elif settings.allow_local_2fa_fallback:
            # Fallback is disabled by default and should only be used for local-only development.
            provider = "local"
            code = str(random.randint(100000, 999999))
            _log.warning(
                "Using local 2FA fallback because Supabase auth is not configured. "
                "No email will be sent for user %s.",
                user.email,
            )
        else:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Supabase email OTP is not configured on the backend.",
            )

        _LOGIN_CHALLENGES[challenge] = {
            "user_id": user_id,
            "code": code,
            "provider": provider,
            "expire_at": int((_utc_now() + timedelta(minutes=settings.login_challenge_expire_minutes)).timestamp())
        }

        return {
            "login_challenge": challenge,
            "message": f"A 2FA code has been sent to {user.email}. Please check your email inbox."
        }

    @staticmethod
    def generate_totp_challenge(db: Session, user_id: int) -> dict:
        """Generate a TOTP challenge for login. Returns challenge ID for verification."""
        user = db.get(User, user_id)
        if not user or not user.is_active:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

        if not user.totp_enabled or not user.totp_secret:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="TOTP is not enabled for this user"
            )

        challenge = token_urlsafe(32)
        _LOGIN_CHALLENGES[challenge] = {
            "user_id": user_id,
            "code": None,  # TOTP code will be verified against the secret
            "totp_secret": user.totp_secret,
            "backup_codes": user.backup_codes,
            "is_totp": True,
            "expire_at": int((_utc_now() + timedelta(minutes=settings.login_challenge_expire_minutes)).timestamp())
        }

        return {
            "login_challenge": challenge,
            "message": "Enter the 6-digit code from your authenticator app, or use a backup code.",
            "is_totp": True,
        }

    @staticmethod
    def verify_2fa_and_issue_tokens(db: Session, login_challenge: str, code: str) -> TokenPairResponse:
        challenge_data = _LOGIN_CHALLENGES.get(login_challenge)
        if not challenge_data:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired login challenge",
            )

        # Check if challenge has expired
        if int(challenge_data["expire_at"]) < int(_utc_now().timestamp()):
            _LOGIN_CHALLENGES.pop(login_challenge, None)
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired login challenge",
            )

        user = AuthService._get_user_with_role(db, int(challenge_data["user_id"]))
        if user is None or not user.is_active:
            _LOGIN_CHALLENGES.pop(login_challenge, None)
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found or inactive")

        # Sanitize input: Remove spaces, dashes, and other common separators
        code = code.replace(" ", "").replace("-", "").strip()
        is_valid = False

        # Handle TOTP verification
        if challenge_data.get("is_totp"):
            totp_secret = challenge_data.get("totp_secret")
            backup_codes = challenge_data.get("backup_codes")

            # Try TOTP code first
            if totp_secret and TOTPService.verify_totp_code(totp_secret, code):
                is_valid = True
            # Try backup code as fallback
            elif backup_codes:
                is_valid_backup, updated_codes = TOTPService.use_backup_code(backup_codes, code)
                if is_valid_backup:
                    is_valid = True
                    # Update the user's backup codes in database
                    user.backup_codes = updated_codes
                    db.commit()

        # Handle email-based 2FA verification
        else:
            provider = str(challenge_data.get("provider", "local"))
            if provider == "supabase" and AuthService._is_supabase_auth_configured():
                is_valid = AuthService._verify_supabase_email_otp(user.email, code)
            else:
                # Local fallback validation (used only when explicitly enabled in env).
                stored_code = challenge_data.get("code")
                is_valid = isinstance(stored_code, str) and code == stored_code

        if not is_valid:
            # Brute force protection: track and limit failed attempts
            failed_count = challenge_data.get("failed_attempts", 0) + 1
            challenge_data["failed_attempts"] = failed_count
            
            # Log the failed attempt
            AuditService.write_log(
                db,
                user_id=user.id,
                action="Failed 2FA Attempt",
                entity_type="users",
                entity_id=user.id,
                metadata={"reason": "Invalid code", "attempt": failed_count}
            )

            if failed_count >= 5:
                _LOGIN_CHALLENGES.pop(login_challenge, None)
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED, 
                    detail="Too many failed attempts. For security, your login session has been reset. Please log in again."
                )
            
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=f"Invalid 2FA code. {5 - failed_count} attempts remaining.")

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

        from app.db.database import is_failover_active
        if is_failover_active():
            print(f"INFO: Issuing non-persistent token pair for {user.email} in failover mode.")
            return TokenPairResponse(
                access_token=access_token,
                refresh_token=refresh_token,
                user=UserRead.from_user(user),
            )

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

    # TOTP Methods
    @staticmethod
    def setup_totp(db: Session, user: User) -> TOTPSetupResponse:
        """Initiate TOTP setup for a user. Returns secret, QR code, and backup codes."""
        if user.totp_enabled:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="TOTP is already enabled for this user. Disable it first to set up again.",
            )

        secret = TOTPService.generate_secret()
        backup_codes = TOTPService.generate_backup_codes()
        qr_code_image = TOTPService.generate_qr_code(user.email, secret)

        # Store the secret temporarily in a global cache (keyed by user_id)
        # In a distributed system, this would go into Redis.
        _PENDING_SETUPS[user.id] = {
            "secret": secret,
            "backup_codes": backup_codes,
            "expires_at": int((_utc_now() + timedelta(minutes=10)).timestamp())
        }

        AuditService.write_log(
            db,
            user_id=user.id,
            action="Started TOTP Setup",
            entity_type="users",
            entity_id=user.id,
        )

        return TOTPSetupResponse(
            secret=secret,
            qr_code=qr_code_image,
            backup_codes=backup_codes,
        )

    @staticmethod
    def verify_totp_setup(db: Session, user: User, totp_code: str) -> TOTPVerifySetupResponse:
        """Verify TOTP setup with a 6-digit code and enable TOTP for the user."""
        pending = _PENDING_SETUPS.get(user.id)
        
        if not pending or int(pending["expires_at"]) < int(_utc_now().timestamp()):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No pending TOTP setup found or it has expired. Call /auth/totp/setup first.",
            )

        secret = str(pending["secret"])
        backup_codes = pending.get("backup_codes", [])
        if not isinstance(backup_codes, list):
             backup_codes = []

        # Verify the TOTP code
        if not TOTPService.verify_totp_code(secret, totp_code):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid TOTP code. Please try again.",
            )

        # Enable TOTP on the user
        user.totp_secret = secret
        user.totp_enabled = True
        user.backup_codes = backup_codes
        db.commit()

        # Cleanup
        _PENDING_SETUPS.pop(user.id, None)

        AuditService.write_log(
            db,
            user_id=user.id,
            action="Enabled TOTP",
            entity_type="users",
            entity_id=user.id,
        )

        return TOTPVerifySetupResponse(
            message="TOTP has been enabled successfully",
            backup_codes=backup_codes,
        )

    @staticmethod
    def disable_totp(db: Session, user: User, password: str) -> None:
        """Disable TOTP for a user. Requires password verification."""
        if not user.totp_enabled:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="TOTP is not enabled for this user.",
            )

        # Verify password before disabling
        if not AuthService.check_user_password(user, password):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid password.",
            )

        user.totp_secret = None
        user.totp_enabled = False
        user.backup_codes = None
        db.commit()

        AuditService.write_log(
            db,
            user_id=user.id,
            action="Disabled TOTP",
            entity_type="users",
            entity_id=user.id,
        )

    @staticmethod
    def verify_totp_code_for_login(secret: str, code: str) -> bool:
        """Verify a TOTP code during login. Supports both TOTP codes and backup codes."""
        return TOTPService.verify_totp_code(secret, code, window=1)
