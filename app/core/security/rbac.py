from collections.abc import Callable

from fastapi import Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session, selectinload

from app.core.security.dependencies import get_current_user
from app.db.database import get_db
from app.models.role import Role
from app.models.role_permission import RolePermission
from app.models.user import User


def _has_permission(db: Session, role_id: int | None, permission_name: str) -> bool:
    if role_id is None:
        return False
    
    from app.models.permission import Permission
    from app.models.role_permission import RolePermission

    requested = permission_name.strip().lower()
    stmt = (
        select(Permission.id)
        .join(RolePermission, RolePermission.permission_id == Permission.id)
        .where(RolePermission.role_id == role_id)
        .where(func.lower(Permission.action_name) == requested)
    )
    return db.scalar(stmt) is not None


def check_permission(user: User, permission_name: str, db: Session | None = None) -> bool:
    """
    Check if a user has a specific permission.
    If db session is not provided, it will create one using failover logic.
    """
    if db is not None:
        return _has_permission(db, user.role_id, permission_name)

    from app.db.database import get_db
    try:
        # Use next(get_db()) to trigger the failover logic in database.py
        db_gen = get_db()
        temp_db = next(db_gen)
        try:
            return _has_permission(temp_db, user.role_id, permission_name)
        finally:
            # We don't need to call next(db_gen) again as get_db is a simple generator
            temp_db.close()
    except Exception:
        return False


def require_permissions(*required_permissions: str) -> Callable:
    def checker(
        current_user: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ) -> User:
        for permission in required_permissions:
            if not _has_permission(db, current_user.role_id, permission):
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN, 
                    detail=f"Insufficient permissions: Role {current_user.role_id} lacks '{permission}'"
                )
        return current_user

    return checker


def require_any_permissions(*required_permissions: str) -> Callable:
    def checker(
        current_user: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ) -> User:
        if current_user.role_id is None:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN, 
                detail="Insufficient permissions: No role assigned"
            )
            
        for permission in required_permissions:
            if _has_permission(db, current_user.role_id, permission):
                return current_user
                
        perms_str = ", ".join(required_permissions)
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, 
            detail=f"Insufficient permissions: Role {current_user.role_id} lacks any of: {perms_str}"
        )

    return checker
