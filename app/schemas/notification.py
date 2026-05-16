from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.user import UserRead


class NotificationSenderRead(BaseModel):
    id: int
    username: str

    model_config = ConfigDict(from_attributes=True)


class NotificationRead(BaseModel):
    notification_id: int
    sender_id: int
    recipient_id: int
    message: str
    type: str
    sent_at: datetime
    sender: NotificationSenderRead | None = None

    model_config = ConfigDict(from_attributes=True)

    @classmethod
    def from_notification(cls, notification: object) -> "NotificationRead":
        sender = getattr(notification, "sender", None)
        sender_payload = None
        if sender is not None:
            sender_payload = NotificationSenderRead(id=sender.id, username=sender.full_name)
        return cls(
            notification_id=notification.id,
            sender_id=notification.sender_id,
            recipient_id=notification.recipient_id,
            message=notification.message,
            type=str(notification.type.value) if hasattr(notification.type, "value") else str(notification.type),
            sent_at=notification.sent_at,
            sender=sender_payload,
        )


class NotificationSendRequest(BaseModel):
    recipient_ids: list[int] = Field(min_length=1)
    message: str = Field(min_length=1, max_length=2000)
    type: str = Field(min_length=1, max_length=20)


class NotificationRecipientRead(UserRead):
    pass