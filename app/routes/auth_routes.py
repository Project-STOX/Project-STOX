from fastapi import APIRouter, Depends, HTTPException, Query, status

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
    TOTPSetupResponse,
    TOTPVerifySetupRequest,
    TOTPVerifySetupResponse,
    TOTPDisableRequest,
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
    return {"allowed": check_permission(current_user, permission)}


@router.get("/permissions/batch")
def has_permissions_batch(
    permissions: list[str] = Query(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict[str, bool]:
    user_with_role = AuthService._get_user_with_role(db, current_user.id)
    current_user.role = user_with_role.role if user_with_role is not None else None
    return {p: check_permission(current_user, p) for p in permissions}


@router.post("/verify-2fa", response_model=TokenPairResponse)
def verify_2fa(payload: dict, db: Session = Depends(get_db)) -> TokenPairResponse:
    print(f"DEBUG: verify_2fa raw payload: {payload}")
    # Still use the logic but extract from dict
    login_challenge = payload.get("login_challenge")
    code = payload.get("code")

    if not login_challenge or not code:
        raise HTTPException(status_code=422, detail="Missing login_challenge or code")

    return AuthService.verify_2fa_and_issue_tokens(db, login_challenge, str(code))


@router.post("/generate-2fa")
def generate_2fa(payload: dict, db: Session = Depends(get_db)):
    user_id = payload.get("user_id")
    email = payload.get("email")
    if not user_id and not email:
        raise HTTPException(status_code=400, detail="user_id or email is required")


    if email and not user_id:
        user = db.scalar(select(User).where(User.email == email.strip().lower()))

        if not user:
             raise HTTPException(status_code=404, detail="User not found")

        user_id = user.id

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

