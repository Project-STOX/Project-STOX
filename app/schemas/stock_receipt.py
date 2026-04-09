from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field


class StockReceiptBase(BaseModel):
    product_id: int = Field(gt=0)
    supplier_id: int = Field(gt=0)
    quantity: int = Field(gt=0)
    quantity_damaged: int = Field(default=0, ge=0)
    unit_cost: Decimal = Field(ge=0)
    reference_no: str | None = Field(default=None, max_length=100)
    received_at: datetime | None = None


class StockReceiptCreate(StockReceiptBase):
    pass


class StockReceiptUpdate(BaseModel):
    product_id: int | None = Field(default=None, gt=0)
    supplier_id: int | None = Field(default=None, gt=0)
    quantity: int | None = Field(default=None, gt=0)
    quantity_damaged: int | None = Field(default=None, ge=0)
    unit_cost: Decimal | None = Field(default=None, ge=0)
    reference_no: str | None = Field(default=None, max_length=100)
    received_at: datetime | None = None


class StockReceiptRead(StockReceiptBase):
    id: int
    recorded_by: int
    recorded_by_username: str | None = None
    received_at: datetime
    model_config = ConfigDict(from_attributes=True)


class StockReceiptImportRow(BaseModel):
    product_code: str = Field(min_length=1, max_length=50)
    supplier_id: int = Field(gt=0)
    quantity: int = Field(gt=0)
    quantity_damaged: int = Field(default=0, ge=0)
    reference_no: str | None = Field(default=None, max_length=100)
    received_at: datetime | None = None


class StockReceiptImportRequest(BaseModel):
    items: list[StockReceiptImportRow] = Field(min_length=1)
