from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field


class ProductBase(BaseModel):
    product_code: str = Field(min_length=1, max_length=50)
    sku: str = Field(min_length=1, max_length=50)
    name: str = Field(min_length=1, max_length=255)
    supplier_id: int = Field(gt=0)
    current_qty: int = Field(default=0, ge=0)
    reorder_level: int = Field(default=10, ge=0)
    overstock_level: int = Field(default=500, ge=0)
    unit_cost: Decimal = Field(default=Decimal("0.00"), ge=0)
    serial_no: int | None = Field(default=None)
    lead_time_days: int | None = Field(default=None, ge=0)
    holding_cost: Decimal = Field(default=Decimal("0.00"), ge=0)
    ordering_cost: Decimal = Field(default=Decimal("0.00"), ge=0)


class ProductCreate(ProductBase):
    pass


class ProductUpdate(BaseModel):
    product_code: str | None = Field(default=None, min_length=1, max_length=50)
    sku: str | None = Field(default=None, min_length=1, max_length=50)
    name: str | None = Field(default=None, min_length=1, max_length=255)
    supplier_id: int | None = Field(default=None, gt=0)
    current_qty: int | None = Field(default=None, ge=0)
    reorder_level: int | None = Field(default=None, ge=0)
    overstock_level: int | None = Field(default=None, ge=0)
    unit_cost: Decimal | None = Field(default=None, ge=0)
    serial_no: int | None = Field(default=None)
    lead_time_days: int | None = Field(default=None, ge=0)
    holding_cost: Decimal | None = Field(default=None, ge=0)
    ordering_cost: Decimal | None = Field(default=None, ge=0)


class ProductRead(ProductBase):
    id: int
    status_flag: str
    lead_time_days: int | None
    model_config = ConfigDict(from_attributes=True)
