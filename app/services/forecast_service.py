from collections import defaultdict
from decimal import Decimal

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.models.demand_forecast import DemandForecast
from app.models.historical_sale import HistoricalSale
from app.schemas.forecast import ForecastGenerateResponse, ForecastResultItem


class ForecastService:
    @staticmethod
    def _moving_average(values: list[int]) -> float:
        if not values:
            return 0.0
        return float(sum(values) / len(values))

    @staticmethod
    def _exponential_smoothing(values: list[int], alpha: float) -> float:
        if not values:
            return 0.0
        smoothed = float(values[0])
        for value in values[1:]:
            smoothed = alpha * float(value) + (1 - alpha) * smoothed
        return smoothed

    @staticmethod
    def generate_forecast(db: Session, *, alpha: float, windows: list[int]) -> ForecastGenerateResponse:
        normalized_windows = sorted({window for window in windows if window in {30, 60}})
        if not normalized_windows:
            normalized_windows = [30, 60]

        rows = db.scalars(
            select(HistoricalSale).order_by(HistoricalSale.product_id.asc(), HistoricalSale.sale_date.asc())
        ).all()

        sales_by_product: dict[int, list[int]] = defaultdict(list)
        for row in rows:
            sales_by_product[row.product_id].append(row.quantity_sold)

        db.execute(delete(DemandForecast).where(DemandForecast.window_days.in_([f"{w}days" for w in normalized_windows])))

        results: list[ForecastResultItem] = []
        for product_id, series in sales_by_product.items():
            for window in normalized_windows:
                trailing = series[-window:] if len(series) > window else series

                ma_daily = ForecastService._moving_average(trailing)
                es_daily = ForecastService._exponential_smoothing(trailing, alpha)

                ma_total = Decimal(str(round(ma_daily * window, 2)))
                es_total = Decimal(str(round(es_daily * window, 2)))

                ma_record = DemandForecast(
                    product_id=product_id,
                    method="MOVING_AVERAGE",
                    window_days=f"{window}days",
                    predicted_qty=ma_total,
                )
                es_record = DemandForecast(
                    product_id=product_id,
                    method="EXPONENTIAL_SMOOTHING",
                    window_days=f"{window}days",
                    predicted_qty=es_total,
                )
                db.add(ma_record)
                db.add(es_record)

                results.append(
                    ForecastResultItem(
                        product_id=product_id,
                        method="MOVING_AVERAGE",
                        window_days=window,
                        predicted_qty=ma_total,
                    )
                )
                results.append(
                    ForecastResultItem(
                        product_id=product_id,
                        method="EXPONENTIAL_SMOOTHING",
                        window_days=window,
                        predicted_qty=es_total,
                    )
                )

        db.commit()
        return ForecastGenerateResponse(generated_records=len(results), forecasts=results)
