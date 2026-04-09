from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel


class RecentActivityItem(BaseModel):
    activity_type: str
    product_id: int
    quantity: int
    created_at: datetime


class ProductImportance(BaseModel):
    product_id: int
    name: str
    supplier_name: str
    reorder_point: int
    eoq: Decimal | None


class ForecastSeriesPoint(BaseModel):
    future_date: date
    moving_average_qty: Decimal
    exponential_smoothing_qty: Decimal


class SalesPoint(BaseModel):
    sale_date: date
    quantity_sold: int


class DashboardSummaryResponse(BaseModel):
    total_products: int
    low_stock_count: int
    stock_value: Decimal
    receipts_value: Decimal
    forecast_worth_30d: Decimal
    forecast_worth_60d: Decimal
    most_important_product: ProductImportance | None
    least_important_product: ProductImportance | None
    total_inventory_historical_sales: list[SalesPoint]
    total_inventory_forecast_30d: list[ForecastSeriesPoint]
    total_inventory_forecast_60d: list[ForecastSeriesPoint]
    predicted_total_ma_30d: Decimal
    predicted_total_es_30d: Decimal
    predicted_total_ma_60d: Decimal
    predicted_total_es_60d: Decimal
    total_inventory_forecast: list[ForecastSeriesPoint]
    recent_activity: list[RecentActivityItem]


class DashboardForecastResponse(BaseModel):
    product_id: int
    window: int
    current_qty: int
    reorder_level: int
    overstock_level: int
    historical_sales: list[SalesPoint]
    future_forecasts: list[ForecastSeriesPoint]
    predicted_demand_ma: Decimal
    predicted_demand_es: Decimal
    daily_demand_es: Decimal
    reorder_suggestion: int
    suggested_order_qty: int
    stock_status: str          # "Low Stock" | "Normal" | "Overstock"
    std_dev: Decimal           # standard deviation of daily demand
    trend_direction: str       # "upward" | "downward" | "stable"
    safety_stock_suggestion: int
    historical_data_points: int


class ProductRiskItem(BaseModel):
    product_id: int
    product_code: str
    sku: str
    name: str
    current_qty: int
    reorder_level: int
    overstock_level: int


class SlowMovingItem(BaseModel):
    product_id: int
    sku: str
    name: str
    sold_last_60_days: int


class DashboardAlertsResponse(BaseModel):
    stockout_risks: list[ProductRiskItem]
    overstock_risks: list[ProductRiskItem]
    slow_moving_items: list[SlowMovingItem]
