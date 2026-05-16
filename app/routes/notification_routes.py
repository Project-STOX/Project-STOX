from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.core.security.dependencies import get_current_user
from app.core.security.rbac import require_permissions
from app.db.database import get_db
from app.models.user import User
from app.schemas.notification import NotificationRead, NotificationSendRequest
from app.schemas.user import UserRead
from app.services.notification_service import NotificationService

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("/me", response_model=list[NotificationRead])
def get_my_notifications(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[NotificationRead]:
    return NotificationService.list_for_user(db, current_user.id)


@router.get("/recipients", response_model=list[UserRead])
def get_recipients(
    db: Session = Depends(get_db),
    _: User = Depends(require_permissions("Send message")),
) -> list[UserRead]:
    users = NotificationService.list_recipients(db)
    return [UserRead.from_user(user) for user in users]


@router.post("/send", status_code=status.HTTP_201_CREATED)
def send_notifications(
    payload: NotificationSendRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    _: User = Depends(require_permissions("Send message")),
) -> dict[str, int]:
    inserted = NotificationService.send_notifications(
        db,
        sender_id=current_user.id,
        recipient_ids=payload.recipient_ids,
        message=payload.message,
        notification_type=payload.type,
    )
    return {"sent": inserted}