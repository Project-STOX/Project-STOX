import enum
from datetime import datetime

from sqlalchemy import DateTime, Enum, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class NotificationType(str, enum.Enum):
    Info = "Info"
    Alert = "Alert"
    Reminder = "Reminder"
    System = "System"
    Task = "Task"
    Message = "Message"


class Notification(Base):
    __tablename__ = "notification"

    id: Mapped[int] = mapped_column("notification_id", Integer, primary_key=True, index=True)
    sender_id: Mapped[int] = mapped_column(Integer, ForeignKey("user.user_id", ondelete="CASCADE"), nullable=False, index=True)
    recipient_id: Mapped[int] = mapped_column(Integer, ForeignKey("user.user_id", ondelete="CASCADE"), nullable=False, index=True)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    type: Mapped[str] = mapped_column(
        Enum(NotificationType, name="message_type"), 
        nullable=False, 
        index=True
    )
    sent_at: Mapped[datetime] = mapped_column(DateTime(timezone=False), server_default=func.now(), nullable=False)

    sender: Mapped["User"] = relationship("User", foreign_keys=[sender_id])
    recipient: Mapped["User"] = relationship("User", foreign_keys=[recipient_id])