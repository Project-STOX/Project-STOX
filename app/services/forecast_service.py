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
        from sqlalchemy.orm import joinedload
        from app.models.product import Product
        import math

        normalized_windows = sorted({window for window in windows if window in {30, 60}})
        if not normalized_windows:
            normalized_windows = [30, 60]

        rows = db.scalars(
            select(HistoricalSale).order_by(HistoricalSale.product_id.asc(), HistoricalSale.sale_date.asc())
        ).all()

        sales_by_product: dict[int, list[int]] = defaultdict(list)
        for row in rows:
            sales_by_product[row.product_id].append(row.quantity_sold)

        product_ids = list(sales_by_product.keys())
        products = db.scalars(
            select(Product).options(joinedload(Product.reorder_params)).where(Product.id.in_(product_ids))
        ).all() if product_ids else []
        products_map = {p.id: p for p in products}

        db.execute(delete(DemandForecast).where(DemandForecast.window_days.in_([f"{w}days" for w in normalized_windows])))

        results: list[ForecastResultItem] = []
        for product_id, series in sales_by_product.items():
            product = products_map.get(product_id)
            lead_time = product.lead_time_days if product else 0
            safety_stock = product.reorder_params.safety_stock if (product and product.reorder_params) else 0

            for window in normalized_windows:
                trailing = series[-window:] if len(series) > window else series

                ma_daily = ForecastService._moving_average(trailing)
                es_daily = ForecastService._exponential_smoothing(trailing, alpha)

                ma_total = Decimal(str(round(ma_daily * window, 2)))
                es_total = Decimal(str(round(es_daily * window, 2)))

                ma_reorder = int(math.ceil(ma_daily * lead_time)) + safety_stock
                es_reorder = int(math.ceil(es_daily * lead_time)) + safety_stock

                ma_record = DemandForecast(
                    product_id=product_id,
                    method="MOVING_AVERAGE",
                    window_days=f"{window}days",
                    predicted_qty=ma_total,
                    reorder_suggestion=ma_reorder,
                )
                es_record = DemandForecast(
                    product_id=product_id,
                    method="EXPONENTIAL_SMOOTHING",
                    window_days=f"{window}days",
                    predicted_qty=es_total,
                    reorder_suggestion=es_reorder,
                )
                db.add(ma_record)
                db.add(es_record)

                results.append(
                    ForecastResultItem(
                        product_id=product_id,
                        method="MOVING_AVERAGE",
                        window_days=window,
                        predicted_qty=ma_total,
                        reorder_suggestion=ma_reorder,
                    )
                )
                results.append(
                    ForecastResultItem(
                        product_id=product_id,
                        method="EXPONENTIAL_SMOOTHING",
                        window_days=window,
                        predicted_qty=es_total,
                        reorder_suggestion=es_reorder,
                    )
                )

        db.commit()
        return ForecastGenerateResponse(generated_records=len(results), forecasts=results)
