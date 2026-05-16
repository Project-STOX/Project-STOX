from sqlalchemy import Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class Permission(Base):
    __tablename__ = "permission"

    id: Mapped[int] = mapped_column("perm_id", Integer, primary_key=True, index=True)
    action_name: Mapped[str] = mapped_column("perm_name", String(100), unique=True, nullable=False, index=True)

    role_permissions: Mapped[list["RolePermission"]] = relationship(
        "RolePermission",
        back_populates="permission",
        cascade="all, delete-orphan",
    )

    @property
    def name(self) -> str:
        return self.action_name
