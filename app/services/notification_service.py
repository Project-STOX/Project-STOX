from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.core.security.input_sanitizer import sanitize_text
from app.models.notification import Notification
from app.models.user import User
from app.schemas.notification import NotificationRead


class NotificationService:
    allowed_types = {"Info", "Alert", "Reminder", "System", "Task", "Message"}

    @staticmethod
    def list_for_user(db: Session, user_id: int) -> list[NotificationRead]:
        notifications = db.scalars(
            select(Notification)
            .where(Notification.recipient_id == user_id)
            .options(selectinload(Notification.sender))
            .order_by(Notification.sent_at.desc())
        ).all()
        return [NotificationRead.from_notification(notification) for notification in notifications]

    @classmethod
    def send_notifications(
        cls,
        db: Session,
        *,
        sender_id: int,
        recipient_ids: list[int],
        message: str,
        notification_type: str,
    ) -> int:
        # Convert Enum members to their string values if necessary
        type_str = str(notification_type.value) if hasattr(notification_type, "value") else str(notification_type)
        
        clean_message = sanitize_text(message, max_length=2000)
        clean_type = sanitize_text(type_str, max_length=20)
        if clean_type not in cls.allowed_types:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid notification type")

        # Verify recipients exist in the database.
        # We don't filter by is_active here because we might be notifying a user that their account was just activated/deactivated.
        recipients = db.scalars(select(User).where(User.id.in_(recipient_ids))).all()
        valid_recipient_ids = [user.id for user in recipients]
        
        if not valid_recipient_ids:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid recipients found")

        notifications = [
            Notification(
                sender_id=sender_id,
                recipient_id=recipient_id,
                message=clean_message,
                type=clean_type,
            )
            for recipient_id in valid_recipient_ids
        ]
        db.add_all(notifications)
        db.commit()
        return len(notifications)

    @staticmethod
    def list_recipients(db: Session) -> list[User]:
        return db.scalars(select(User).where(User.is_active.is_(True)).order_by(User.full_name.asc())).all()