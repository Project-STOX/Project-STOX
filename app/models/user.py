from sqlalchemy import Boolean, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class User(Base):
    __tablename__ = "user"

    id: Mapped[int] = mapped_column("user_id", Integer, primary_key=True, index=True)
    full_name: Mapped[str] = mapped_column("username", String(50), nullable=False)
    email: Mapped[str] = mapped_column(String(50), unique=True, index=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(Text, nullable=False)
    role_id: Mapped[int] = mapped_column(Integer, ForeignKey("role.role_id"), nullable=False, index=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    tfa_active: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    role: Mapped["Role"] = relationship("Role", back_populates="users")

    @property
    def role_name(self) -> str:
        return self.role.role_name
