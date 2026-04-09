from pydantic import BaseModel, Field


class AssignRoleRequest(BaseModel):
    role_id: int = Field(gt=0)


class AssignPermissionRequest(BaseModel):
    perm_id: int = Field(gt=0)


class CreateUserRequest(BaseModel):
    username: str = Field(min_length=1, max_length=50)
    email: str = Field(min_length=3, max_length=50)
    password: str = Field(min_length=8, max_length=128)
    role_id: int = Field(gt=0)
    verify_email: bool = False


class UpdateUserRequest(BaseModel):
    username: str | None = Field(default=None, min_length=1, max_length=50)
    email: str | None = Field(default=None, min_length=3, max_length=50)
    role_id: int | None = Field(default=None, gt=0)
    is_active: bool | None = None
    tfa_active: bool | None = None
    password: str | None = Field(default=None, min_length=8, max_length=128)


class CreateRoleRequest(BaseModel):
    role_name: str = Field(min_length=1, max_length=50)
    description: str | None = Field(default=None, max_length=255)
