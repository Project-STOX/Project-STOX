from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field


class ReportSupplierRead(BaseModel):
    supplier_name: str | None = None

    model_config = ConfigDict(from_attributes=True)


class ReportProductRead(BaseModel):
    product_name: str
    product_code: str | None = None
    supplier: ReportSupplierRead | None = None

    model_config = ConfigDict(from_attributes=True)


class HistoricalSaleRead(BaseModel):
    sale_id: int
    product_id: int
    sale_date: date
    quantity_sold: int
    revenue: Decimal
    product: ReportProductRead

    model_config = ConfigDict(from_attributes=True)


class HistoricalSaleImportRow(BaseModel):
    product_code: str = Field(min_length=1, max_length=50)
    sale_date: date
    quantity_sold: int = Field(gt=0)
    revenue: Decimal = Field(ge=0)


class HistoricalSaleImportRequest(BaseModel):
    items: list[HistoricalSaleImportRow] = Field(min_length=1)


class AuditLogRead(BaseModel):
    log_id: int
    user_id: int | None = None
    username: str | None = None
    action: str
    entity_type: str
    entity_id: int | None = None
    details: str | None = None
    occurred_at: datetime

    model_config = ConfigDict(from_attributes=True)


class AuditLogCreateRequest(BaseModel):
    action: str = Field(min_length=1, max_length=50)
    entity_type: str = Field(min_length=1, max_length=50)
    entity_id: int = Field(default=0, ge=0)
    details: str | None = Field(default=None, max_length=1000)