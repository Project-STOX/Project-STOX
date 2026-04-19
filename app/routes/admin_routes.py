from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.core.security.dependencies import get_current_user
from app.core.security.rbac import require_any_permissions, require_permissions
from app.db.database import get_db
from app.models.permission import Permission
from app.models.role import Role
from app.models.role_permission import RolePermission
from app.models.user import User
from app.schemas.admin import (
    AssignPermissionRequest,
    AssignRoleRequest,
    CreateRoleRequest,
    CreateUserRequest,
    UpdateUserRequest,
)
from app.schemas.permission import PermissionRead
from app.schemas.role import RoleRead
from app.schemas.user import UserRead
from app.core.security.password import hash_password
from app.core.security.input_sanitizer import sanitize_text
from app.models.refresh_token import RefreshToken
from app.models.notification import Notification
from app.models.stock_receipt import StockReceipt
from app.models.audit_log import AuditLog
from sqlalchemy import delete, update
from sqlalchemy.exc import IntegrityError

from app.models.notification import NotificationType
from app.services.notification_service import NotificationService

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/users", response_model=list[UserRead])
def list_users(
    db: Session = Depends(get_db),
    _: User = Depends(require_permissions("Manage users")),
) -> list[UserRead]:
    users = db.scalars(select(User).order_by(User.id.desc())).all()
    return [UserRead.from_user(user) for user in users]


@router.post("/users", response_model=UserRead, status_code=status.HTTP_201_CREATED)
def create_user(
    payload: CreateUserRequest,
    db: Session = Depends(get_db),
    _: User = Depends(require_permissions("Manage users")),
) -> UserRead:
    existing = db.scalar(select(User).where(User.email == payload.email.lower().strip()))
    if existing is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="User already exists")

    # Verify role exists
    if db.get(Role, payload.role_id) is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid role ID")

    user = User(
        full_name=sanitize_text(payload.username, max_length=50),
        email=payload.email.lower().strip(),
        password_hash=hash_password(payload.password),
        role_id=payload.role_id,
        is_active=True,
        tfa_active=False,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return UserRead.from_user(user)


@router.put("/users/{user_id}", response_model=UserRead)
def update_user(
    user_id: int,
    payload: UpdateUserRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> UserRead:
    # 1. Authorize the request
    is_self = current_user.id == user_id
    
    # Load role if not already present to check permissions
    from app.services.auth_service import AuthService
    user_with_role = AuthService._get_user_with_role(db, current_user.id)
    current_user.role = user_with_role.role if user_with_role else None
    
    from app.core.security.rbac import check_permission
    is_admin = check_permission(current_user, "Manage users", db=db)

    if not (is_self or is_admin):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient admin permissions")

    # 2. Fetch the target user
    user = db.scalar(select(User).where(User.id == user_id).options(selectinload(User.role)))
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    # 3. Apply changes (with restrictions for non-admins)
    changes = payload.model_dump(exclude_none=True)
    
    # 4. Apply changes and check for notifications
    personal_info_changed = False
    role_changed = False

    if "username" in changes:
        new_name = sanitize_text(str(changes["username"]), max_length=50)
        if user.full_name != new_name:
            user.full_name = new_name
            personal_info_changed = True
            
    if "email" in changes:
        new_email = str(changes["email"]).lower().strip()
        if user.email != new_email:
            user.email = new_email
            personal_info_changed = True
            
    if "tfa_active" in changes:
        user.tfa_active = bool(changes["tfa_active"])

    if "role_id" in changes:
        if not is_admin:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only administrators can change roles")
        new_role_id = int(changes["role_id"])
        if user.role_id != new_role_id:
            user.role_id = new_role_id
            role_changed = True
            
    if "is_active" in changes:
        if not is_admin:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only administrators can deactivate accounts")
        user.is_active = bool(changes["is_active"])

    password_changed = False
    if "password" in changes:
        if not is_admin:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only administrators can change passwords of other users")
        user.password_hash = hash_password(str(changes["password"]))
        password_changed = True

    db.commit()
    db.refresh(user)

    # 5. Send notifications
    if personal_info_changed:
        NotificationService.send_notifications(
            db,
            sender_id=current_user.id,
            recipient_ids=[user.id],
            message="Your personal information (Name/Email) has been updated by an administrator.",
            notification_type=NotificationType.Info
        )
    
    if password_changed:
        NotificationService.send_notifications(
            db,
            sender_id=current_user.id,
            recipient_ids=[user.id],
            message="Your account password has been reset by an administrator.",
            notification_type=NotificationType.System
        )
    
    if role_changed:
        NotificationService.send_notifications(
            db,
            sender_id=current_user.id,
            recipient_ids=[user.id],
            message=f"Your system role has been changed. You may need to re-login to see new permissions.",
            notification_type=NotificationType.System
        )

    return UserRead.from_user(user)

from app.models.refresh_token import RefreshToken
from app.models.notification import Notification
from app.models.stock_receipt import StockReceipt
from app.models.audit_log import AuditLog
from sqlalchemy import delete, update


@router.delete("/users/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permissions("Manage users")),
) -> None:
    # 1. Prevent self-deletion
    if current_user.id == user_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You cannot delete your own account"
        )

    # 2. Fetch target user
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
        
    try:
        # 3. Force clean related records
        # Cleanup sessions
        db.execute(delete(RefreshToken).where(RefreshToken.user_id == user_id))
        
        # Cleanup notifications
        db.execute(
            delete(Notification).where(
                (Notification.sender_id == user_id) | (Notification.recipient_id == user_id)
            )
        )
        
        # Cleanup stock receipts (this is destructive for inventory history but requested)
        db.execute(delete(StockReceipt).where(StockReceipt.recorded_by == user_id))
        
        # Cleanup audit logs (set to NULL to preserve logs but detach user)
        db.execute(update(AuditLog).where(AuditLog.user_id == user_id).values(user_id=None))
        
        # 4. Delete the user
        db.delete(user)
        db.commit()
    except Exception as exc:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to delete user and their records: {str(exc)}"
        )


@router.get("/roles", response_model=list[RoleRead])
def list_roles(
    db: Session = Depends(get_db),
    _: User = Depends(require_any_permissions("Manage roles", "Send message")),
) -> list[RoleRead]:
    roles = db.scalars(select(Role).order_by(Role.id.desc())).all()
    return roles


@router.post("/roles", response_model=RoleRead, status_code=status.HTTP_201_CREATED)
def create_role(
    payload: CreateRoleRequest,
    db: Session = Depends(get_db),
    _: User = Depends(require_permissions("Manage roles")),
) -> RoleRead:
    role = Role(role_name=sanitize_text(payload.role_name, max_length=50), description=payload.description)
    db.add(role)
    db.commit()
    db.refresh(role)
    return role


@router.put("/roles/{role_id}", response_model=RoleRead)
def update_role(
    role_id: int,
    payload: CreateRoleRequest,
    db: Session = Depends(get_db),
    _: User = Depends(require_permissions("Manage roles")),
) -> RoleRead:
    role = db.get(Role, role_id)
    if role is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Role not found")
    role.role_name = sanitize_text(payload.role_name, max_length=50)
    role.description = payload.description
    db.commit()
    db.refresh(role)
    return role


@router.delete("/roles/{role_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_role(
    role_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_permissions("Manage roles")),
) -> None:
    role = db.get(Role, role_id)
    if role is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Role not found")
    db.delete(role)
    db.commit()


@router.get("/permissions", response_model=list[PermissionRead])
def list_permissions(
    db: Session = Depends(get_db),
    _: User = Depends(require_any_permissions("Manage roles", "Send message")),
) -> list[PermissionRead]:
    return db.scalars(select(Permission).order_by(Permission.id.asc())).all()


@router.get("/roles/{role_id}/permissions", response_model=list[PermissionRead])
def get_role_permissions(
    role_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_permissions("Manage roles")),
) -> list[PermissionRead]:
    role = db.scalar(
        select(Role)
        .where(Role.id == role_id)
        .options(selectinload(Role.role_permissions).selectinload(RolePermission.permission))
    )
    if role is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Role not found")
    return [rp.permission for rp in role.role_permissions if rp.permission is not None]


@router.post("/roles/{role_id}/permissions", status_code=status.HTTP_204_NO_CONTENT)
def add_role_permission(
    role_id: int,
    payload: AssignPermissionRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permissions("Manage roles")),
) -> None:
    if db.get(Role, role_id) is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Role not found")
    if db.get(Permission, payload.perm_id) is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Permission not found")
    existing = db.scalar(
        select(RolePermission).where(
            RolePermission.role_id == role_id,
            RolePermission.permission_id == payload.perm_id,
        )
    )
    if existing is None:
        db.add(RolePermission(role_id=role_id, permission_id=payload.perm_id))
        db.commit()
        
        # Notify all users in this role
        users_in_role = db.scalars(select(User.id).where(User.role_id == role_id)).all()
        if users_in_role:
            role = db.get(Role, role_id)
            NotificationService.send_notifications(
                db,
                sender_id=current_user.id,
                recipient_ids=users_in_role,
                message=f"Permissions for your role ({role.role_name}) have been updated.",
                notification_type=NotificationType.System
            )


@router.delete("/roles/{role_id}/permissions/{perm_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_role_permission(
    role_id: int,
    perm_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permissions("Manage roles")),
) -> None:
    mapping = db.scalar(
        select(RolePermission).where(
            RolePermission.role_id == role_id,
            RolePermission.permission_id == perm_id,
        )
    )
    if mapping is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Role permission not found")
    db.delete(mapping)
    db.commit()
    
    # Notify all users in this role
    users_in_role = db.scalars(select(User.id).where(User.role_id == role_id)).all()
    if users_in_role:
        role = db.get(Role, role_id)
        NotificationService.send_notifications(
            db,
            sender_id=current_user.id,
            recipient_ids=users_in_role,
            message=f"Permissions for your role ({role.role_name}) have been changed (revoked).",
            notification_type=NotificationType.System
        )


@router.get("/roles/{role_id}/users", response_model=list[UserRead])
def get_role_users(
    role_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_permissions("Manage roles")),
) -> list[UserRead]:
    users = db.scalars(select(User).where(User.role_id == role_id).order_by(User.id.desc())).all()
    return [UserRead.from_user(user) for user in users]


@router.post("/users/{user_id}/role", response_model=UserRead)
def assign_user_role(
    user_id: int,
    payload: AssignRoleRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permissions("Manage roles")),
) -> UserRead:
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    if db.get(Role, payload.role_id) is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Role not found")
    user.role_id = payload.role_id
    db.commit()
    db.refresh(user)
    
    # Notify the user
    NotificationService.send_notifications(
        db,
        sender_id=current_user.id,
        recipient_ids=[user.id],
        message="Your system role has been explicitly updated by an administrator.",
        notification_type=NotificationType.System
    )

    return UserRead.from_user(user)