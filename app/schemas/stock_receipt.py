from datetime import date, datetime
from decimal import Decimal
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator


# Formats tried in order when parsing a string value for received_at.
_DATETIME_FORMATS = [
    "%m/%d/%Y %H:%M",   # 2/5/2026 5:00  (from spreadsheet exports)
    "%m/%d/%Y %H:%M:%S",
    "%d/%m/%Y %H:%M",
    "%d/%m/%Y %H:%M:%S",
    "%Y-%m-%d %H:%M:%S",
    "%Y-%m-%dT%H:%M:%S",
    "%Y-%m-%dT%H:%M:%SZ",
    "%m/%d/%Y",         # date-only M/D/YYYY
    "%d/%m/%Y",         # date-only D/M/YYYY
    "%Y-%m-%d",         # ISO date-only
]


def _parse_received_at(v: Any) -> datetime | None:
    """Parse a flexible date/datetime value into a datetime object."""
    if v is None or isinstance(v, datetime):
        return v
    if isinstance(v, date):
        return datetime(v.year, v.month, v.day)
    if isinstance(v, str):
        raw = v.strip()
        if not raw:
            return None
        for fmt in _DATETIME_FORMATS:
            try:
                return datetime.strptime(raw, fmt)
            except ValueError:
                continue
        raise ValueError(
            f"Unable to parse '{raw}' as a date/datetime. "
            "Accepted formats include M/D/YYYY H:MM, M/D/YYYY, YYYY-MM-DD, etc."
        )
    raise TypeError(f"Unsupported type for received_at: {type(v)}")


class StockReceiptBase(BaseModel):
    product_id: int = Field(gt=0)
    supplier_id: int = Field(gt=0)
    quantity: int = Field(gt=0)
    quantity_damaged: int = Field(default=0, ge=0)
    unit_cost: Decimal = Field(ge=0)
    reference_no: str | None = Field(default=None, max_length=100)
    received_at: datetime | None = None

    @field_validator("received_at", mode="before")
    @classmethod
    def parse_received_at(cls, v: Any) -> datetime | None:
        return _parse_received_at(v)


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

    @field_validator("received_at", mode="before")
    @classmethod
    def parse_received_at(cls, v: Any) -> datetime | None:
        return _parse_received_at(v)


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

    @field_validator("received_at", mode="before")
    @classmethod
    def parse_received_at(cls, v: Any) -> datetime | None:
        return _parse_received_at(v)


class StockReceiptImportRequest(BaseModel):
    items: list[StockReceiptImportRow] = Field(min_length=1)

