from pydantic import BaseModel, ConfigDict, EmailStr, Field


class SupplierBase(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    email: EmailStr | None = None
    phone: str | None = Field(default=None, max_length=50)
    address: str | None = Field(default=None)
    lead_time_days: int | None = Field(default=None, ge=0)
    is_active: bool = True


class SupplierCreate(SupplierBase):
    pass


class SupplierUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=255)
    email: EmailStr | None = None
    phone: str | None = Field(default=None, max_length=50)
    address: str | None = Field(default=None)
    lead_time_days: int | None = Field(default=None, ge=0)
    is_active: bool | None = None


class SupplierRead(SupplierBase):
    id: int
    model_config = ConfigDict(from_attributes=True)
