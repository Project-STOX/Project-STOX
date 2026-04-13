from typing import TYPE_CHECKING

from pydantic import BaseModel, ConfigDict, EmailStr

if TYPE_CHECKING:
    from app.models.user import User


class UserRead(BaseModel):
    id: int
    email: str
    full_name: str
    role: str
    role_id: int
    username: str
    is_active: bool
    tfa_active: bool

    model_config = ConfigDict(from_attributes=True)

    @classmethod
    def from_user(cls, user: "User") -> "UserRead":
        return cls(
            id=user.id,
            email=user.email,
            full_name=user.full_name,
            role=user.role_name,
            role_id=user.role_id,
            username=user.full_name,
            is_active=user.is_active,
            tfa_active=user.tfa_active,
        )
