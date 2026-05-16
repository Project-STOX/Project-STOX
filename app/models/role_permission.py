from sqlalchemy import ForeignKey, Integer, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class RolePermission(Base):
    __tablename__ = "role_permission"

    role_id: Mapped[int] = mapped_column(Integer, ForeignKey("role.role_id"), primary_key=True, index=True)
    permission_id: Mapped[int] = mapped_column(
        "perm_id",
        Integer,
        ForeignKey("permission.perm_id"),
        primary_key=True,
        index=True,
    )

    role: Mapped["Role"] = relationship("Role", back_populates="role_permissions")
    permission: Mapped["Permission"] = relationship("Permission", back_populates="role_permissions")
