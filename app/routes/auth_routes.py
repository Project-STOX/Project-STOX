from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from fastapi.responses import HTMLResponse

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.security.dependencies import get_current_user
from app.core.security.rbac import check_permission
from app.db.database import get_db
from app.models.user import User
from app.schemas.auth import (
    ChangePasswordRequest,
    DeleteAccountRequest,
    LoginChallengeResponse,
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    TokenPairResponse,
    Verify2FARequest,
    Generate2FARequest,
    TOTPSetupResponse,
    TOTPVerifySetupRequest,
    TOTPVerifySetupResponse,
    TOTPDisableRequest,
    VerifyEmailRequest,
)
from app.services.auth_service import AuthService
from app.schemas.user import UserRead

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login")
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> dict[str, object]:
    return AuthService.login_step_one(db, payload)


@router.get("/me", response_model=UserRead)
def get_me(current_user: User = Depends(get_current_user)) -> UserRead:
    return UserRead.from_user(current_user)


@router.get("/permissions")
def has_permission(
    permission: str = Query(..., min_length=1),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict[str, bool]:
    user_with_role = AuthService._get_user_with_role(db, current_user.id)
    current_user.role = user_with_role.role if user_with_role is not None else None
    return {"allowed": check_permission(current_user, permission, db=db)}


@router.get("/permissions/batch")
def has_permissions_batch(
    permissions: list[str] = Query(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict[str, bool]:
    user_with_role = AuthService._get_user_with_role(db, current_user.id)
    current_user.role = user_with_role.role if user_with_role is not None else None
    return {p: check_permission(current_user, p, db=db) for p in permissions}


@router.post("/verify-2fa", response_model=TokenPairResponse)
def verify_2fa(payload: Verify2FARequest, db: Session = Depends(get_db)) -> TokenPairResponse:
    return AuthService.verify_2fa_and_issue_tokens(db, payload.login_challenge, payload.code)


@router.post("/generate-2fa")
def generate_2fa(payload: Generate2FARequest, db: Session = Depends(get_db)):
    user_id = payload.user_id
    email = payload.email
    if not user_id and not email:
        raise HTTPException(status_code=400, detail="user_id or email is required")

    if email and not user_id:
        user = db.scalar(select(User).where(User.email == email.strip().lower()))
        if not user:
             raise HTTPException(status_code=404, detail="User not found")
        user_id = user.id

    if user_id is None:
        raise HTTPException(status_code=400, detail="user_id or email is required")

    return AuthService.generate_2fa_challenge(db, user_id)


@router.post("/totp/setup", response_model=TOTPSetupResponse)
def setup_totp(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> TOTPSetupResponse:
    """Initiate TOTP setup for the current user."""
    return AuthService.setup_totp(db, current_user)


@router.post("/totp/verify-setup", response_model=TOTPVerifySetupResponse)
def verify_totp_setup(
    payload: TOTPVerifySetupRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> TOTPVerifySetupResponse:
    """Verify TOTP setup with a 6-digit code."""
    return AuthService.verify_totp_setup(db, current_user, payload.totp_code)


@router.post("/totp/disable", status_code=status.HTTP_204_NO_CONTENT)
def disable_totp(
    payload: TOTPDisableRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    """Disable TOTP for the current user."""
    AuthService.disable_totp(db, current_user, payload.password)


@router.post("/refresh", response_model=TokenPairResponse)
def refresh(payload: RefreshRequest, db: Session = Depends(get_db)) -> TokenPairResponse:
    return AuthService.refresh_tokens(db, payload.refresh_token)


@router.post("/verify-email")
def verify_email(payload: VerifyEmailRequest, db: Session = Depends(get_db)) -> dict[str, str]:
    return AuthService.verify_email_and_activate_user(
        db,
        email=payload.email,
        code=payload.code,
        access_token=payload.access_token,
    )


@router.get("/verify-email/callback", response_class=HTMLResponse)
def verify_email_callback(request: Request) -> HTMLResponse:
    verify_url = f"{request.base_url}api/v1/auth/verify-email"
    html = f"""<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>STOX Email Verification</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 0; min-height: 100vh; display: grid; place-items: center; background: #f5f7fb; color: #1f2937; }}
        .card {{ background: white; padding: 2rem; border-radius: 16px; box-shadow: 0 20px 50px rgba(15, 23, 42, 0.12); max-width: 520px; width: calc(100% - 2rem); }}
        h1 {{ margin-top: 0; font-size: 1.4rem; }}
        p {{ line-height: 1.5; }}
        .status {{ font-weight: 600; }}
    </style>
</head>
<body>
    <main class="card">
        <h1>Verifying your email</h1>
        <p class="status" id="status">Checking the verification link...</p>
        <p>You can close this tab after verification completes.</p>
    </main>
    <script>
        (async () => {{
            const statusNode = document.getElementById('status');
            const fragment = new URLSearchParams(window.location.hash.replace(/^#/, ''));
            const accessToken = fragment.get('access_token');
            const code = fragment.get('token');
            const email = fragment.get('email');

            if (!accessToken && !code) {{
                statusNode.textContent = 'Verification data was missing from the link.';
                return;
            }}

            try {{
                const response = await fetch('{verify_url}', {{
                    method: 'POST',
                    headers: {{ 'Content-Type': 'application/json' }},
                    body: JSON.stringify({{ access_token: accessToken, code, email }}),
                }});
                const payload = await response.json();
                if (!response.ok) {{
                    throw new Error(payload.detail || 'Verification failed');
                }}
                statusNode.textContent = payload.message || 'Email verified successfully.';
            }} catch (error) {{
                statusNode.textContent = error.message || 'Verification failed.';
            }}
        }})();
    </script>
</body>
</html>"""
    return HTMLResponse(content=html)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(payload: LogoutRequest, db: Session = Depends(get_db)) -> None:
    AuthService.logout(db, payload.refresh_token)


@router.post("/change-password", status_code=status.HTTP_204_NO_CONTENT)
def change_password(
    payload: ChangePasswordRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    AuthService.change_password(
        db,
        user=current_user,
        current_password=payload.current_password,
        new_password=payload.new_password,
        two_factor_code=payload.two_factor_code,
    )


@router.delete("/account", status_code=status.HTTP_204_NO_CONTENT)
def delete_account(
    payload: DeleteAccountRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    AuthService.delete_account(db, user=current_user, two_factor_code=payload.two_factor_code)

