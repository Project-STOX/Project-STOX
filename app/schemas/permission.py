from pydantic import BaseModel, ConfigDict, Field


class PermissionRead(BaseModel):
    perm_id: int = Field(alias="id")
    perm_name: str = Field(alias="action_name")

    model_config = ConfigDict(from_attributes=True, populate_by_name=True)
