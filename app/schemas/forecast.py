from decimal import Decimal

from pydantic import BaseModel, Field


class ForecastGenerateRequest(BaseModel):
    alpha: float = Field(default=0.3, gt=0, le=1)
    windows: list[int] = Field(default_factory=lambda: [30, 60], min_length=1)


class ForecastResultItem(BaseModel):
    product_id: int
    method: str
    window_days: int
    predicted_qty: Decimal


class ForecastGenerateResponse(BaseModel):
    generated_records: int
    forecasts: list[ForecastResultItem]
