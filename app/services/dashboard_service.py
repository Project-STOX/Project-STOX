from collections import deque
from datetime import UTC, datetime, timedelta
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import Select, case, desc, func, select
from sqlalchemy.orm import Session

from app.core.security.input_sanitizer import sanitize_text
from app.models.demand_forecast import DemandForecast
from app.models.historical_sale import HistoricalSale
from app.models.product import Product
from app.models.stock_receipt import StockReceipt
from app.models.reorder_parameter import ReorderParameter
from app.models.supplier import Supplier
from app.schemas.dashboard import (
    DashboardAlertsResponse,
    DashboardForecastResponse,
    DashboardSummaryResponse,
    ProductRiskItem,
    RecentActivityItem,
    SalesPoint,
    SlowMovingItem,
    ForecastSeriesPoint,
    ProductImportance,
)


class DashboardService:
    @staticmethod
    def get_summary(
        db: Session, *, supplier_id: int | None = None, activity_limit: int = 10
    ) -> DashboardSummaryResponse:
        # build main dashboard numbers and recent activity

        filters = []
        if supplier_id is not None:
            filters.append(Product.supplier_id == supplier_id)

        total_products = db.scalar(select(func.count(Product.id)).where(*filters)) or 0
        low_stock_count = db.scalar(
            select(func.count(Product.id)).where(*filters, Product.current_qty <= Product.reorder_level)
        ) or 0
        stock_value = db.scalar(
            select(func.coalesce(func.sum(Product.current_qty * Product.unit_cost), 0)).where(*filters)
        ) or Decimal("0.00")

        recent_stmt: Select[tuple[StockReceipt]] = (
            select(StockReceipt).order_by(StockReceipt.received_at.desc()).limit(activity_limit)
        )
        if supplier_id is not None:
            recent_stmt = recent_stmt.where(StockReceipt.supplier_id == supplier_id)
        recent_receipts = db.scalars(recent_stmt).all()

        recent_activity = [
            RecentActivityItem(
                activity_type="STOCK_RECEIPT",
                product_id=entry.product_id,
                quantity=entry.quantity,
                created_at=entry.received_at,
            )
            for entry in recent_receipts
        ]

        receipts_value = db.scalar(
            select(func.coalesce(func.sum(StockReceipt.quantity * Product.unit_cost), 0))
            .join(Product, StockReceipt.product_id == Product.id)
            .where(*filters)
        ) or Decimal("0.00")

        def get_forecast_worth(w_days: int) -> Decimal:
            # get forecast value for one window size

            q = select(func.coalesce(func.sum(DemandForecast.predicted_qty * Product.unit_cost), 0)).join(Product, DemandForecast.product_id == Product.id).where(DemandForecast.window_days == f"{w_days}days", DemandForecast.method == "EXPONENTIAL_SMOOTHING")
            if supplier_id is not None:
                q = q.where(Product.supplier_id == supplier_id)
            return db.scalar(q) or Decimal("0.00")

        forecast_worth_30d = get_forecast_worth(30)
        forecast_worth_60d = get_forecast_worth(60)

        def get_product_importance(asc_order=False) -> ProductImportance | None:
            # get top or bottom product by eoq

            order_col = ReorderParameter.eoq.asc().nulls_last() if asc_order else ReorderParameter.eoq.desc().nulls_last()
            q = select(Product, Supplier, ReorderParameter).join(Supplier, Product.supplier_id == Supplier.id).join(ReorderParameter, Product.id == ReorderParameter.product_id)
            if supplier_id is not None:
                q = q.where(Product.supplier_id == supplier_id)
            row = db.execute(q.order_by(order_col).limit(1)).first()
            if row:
                p, s, r = row
                return ProductImportance(
                    product_id=p.id,
                    name=p.name,
                    supplier_name=s.name,
                    reorder_point=p.reorder_level,
                    eoq=r.eoq
                )
            return None

        most_important = get_product_importance(asc_order=False)
        least_important = get_product_importance(asc_order=True)

        max_date_stmt = select(func.max(HistoricalSale.sale_date))
        if filters:
            max_date_stmt = max_date_stmt.join(Product, HistoricalSale.product_id == Product.id).where(*filters)
        max_sale_date = db.scalar(max_date_stmt)
        
        base_date = max_sale_date if max_sale_date else datetime.now(UTC).date()
        lookback_days = 120
        history_start = base_date - timedelta(days=lookback_days - 1)

        daily_sales_stmt = (
            select(
                HistoricalSale.sale_date,
                func.coalesce(func.sum(HistoricalSale.quantity_sold), 0).label("daily_qty"),
            )
            .join(Product, HistoricalSale.product_id == Product.id)
            .where(HistoricalSale.sale_date >= history_start, *filters)
            .group_by(HistoricalSale.sale_date)
            .order_by(HistoricalSale.sale_date.asc())
        )
        daily_sales_rows = db.execute(daily_sales_stmt).all()
        qty_by_date = {row.sale_date: int(row.daily_qty or 0) for row in daily_sales_rows}

        total_inventory_historical_sales: list[SalesPoint] = []
        historical_values: list[float] = []
        for day_offset in range(lookback_days):
            sale_day = history_start + timedelta(days=day_offset)
            qty = qty_by_date.get(sale_day, 0)
            historical_values.append(float(qty))
            total_inventory_historical_sales.append(
                SalesPoint(sale_date=sale_day, quantity_sold=qty)
            )

        def build_forecast_series(window_days: int, horizon_days: int) -> tuple[list[ForecastSeriesPoint], Decimal, Decimal]:
                # build moving average and smoothing forecast points

            if not historical_values:
                empty = [
                    ForecastSeriesPoint(
                        future_date=base_date + timedelta(days=idx + 1),
                        moving_average_qty=Decimal("0.00"),
                        exponential_smoothing_qty=Decimal("0.00"),
                    )
                    for idx in range(horizon_days)
                ]
                return empty, Decimal("0.00"), Decimal("0.00")

            trailing_len = min(window_days, len(historical_values))
            trailing_values = historical_values[-trailing_len:]

            ma_queue = deque(trailing_values, maxlen=trailing_len)
            ma_predictions: list[float] = []
            for _ in range(horizon_days):
                ma_next = sum(ma_queue) / len(ma_queue)
                ma_predictions.append(ma_next)
                ma_queue.append(ma_next)

            alpha = 0.35
            beta = 0.2
            if len(trailing_values) == 1:
                level = trailing_values[0]
                trend = 0.0
            else:
                level = trailing_values[0]
                trend = (trailing_values[-1] - trailing_values[0]) / max(len(trailing_values) - 1, 1)
                for value in trailing_values[1:]:
                    prev_level = level
                    level = alpha * value + (1 - alpha) * (level + trend)
                    trend = beta * (level - prev_level) + (1 - beta) * trend

            es_predictions: list[float] = []
            for step in range(1, horizon_days + 1):
                es_next = max(0.0, level + step * trend)
                es_predictions.append(es_next)

            points = [
                ForecastSeriesPoint(
                    future_date=base_date + timedelta(days=idx + 1),
                    moving_average_qty=Decimal(str(round(ma_predictions[idx], 2))),
                    exponential_smoothing_qty=Decimal(str(round(es_predictions[idx], 2))),
                )
                for idx in range(horizon_days)
            ]

            predicted_ma_total = Decimal(str(round(sum(ma_predictions), 2)))
            predicted_es_total = Decimal(str(round(sum(es_predictions), 2)))
            return points, predicted_ma_total, predicted_es_total

        total_inventory_forecast_30d, predicted_total_ma_30d, predicted_total_es_30d = build_forecast_series(30, 30)
        total_inventory_forecast_60d, predicted_total_ma_60d, predicted_total_es_60d = build_forecast_series(60, 60)

        return DashboardSummaryResponse(
            total_products=total_products,
            low_stock_count=low_stock_count,
            stock_value=Decimal(str(stock_value)),
            receipts_value=Decimal(str(receipts_value)),
            forecast_worth_30d=Decimal(str(forecast_worth_30d)),
            forecast_worth_60d=Decimal(str(forecast_worth_60d)),
            most_important_product=most_important,
            least_important_product=least_important,
            total_inventory_historical_sales=total_inventory_historical_sales,
            total_inventory_forecast_30d=total_inventory_forecast_30d,
            total_inventory_forecast_60d=total_inventory_forecast_60d,
            predicted_total_ma_30d=predicted_total_ma_30d,
            predicted_total_es_30d=predicted_total_es_30d,
            predicted_total_ma_60d=predicted_total_ma_60d,
            predicted_total_es_60d=predicted_total_es_60d,
            total_inventory_forecast=total_inventory_forecast_30d,
            recent_activity=recent_activity,
        )

    @staticmethod
    def get_forecast_view(
        db: Session,
        *,
        product_id: int,
        window: int,
        supplier_id: int | None = None,
    ) -> DashboardForecastResponse:
        # build detailed forecast for one product

        import math
        if window not in {30, 60}:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="window must be 30 or 60")

        product_stmt = select(Product).where(Product.id == product_id)
        if supplier_id is not None:
            product_stmt = product_stmt.where(Product.supplier_id == supplier_id)
        product = db.scalar(product_stmt)
        if product is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found")

        # Fetch all historical sales for this product (ordered ascending)
        history_rows = db.scalars(
            select(HistoricalSale)
            .where(HistoricalSale.product_id == product_id)
            .order_by(HistoricalSale.sale_date.asc())
        ).all()

        historical_sales = [
            SalesPoint(sale_date=row.sale_date, quantity_sold=row.quantity_sold) for row in history_rows
        ]
        n = len(history_rows)

        # Get the trailing window of daily sales values for computation
        trailing_values = [row.quantity_sold for row in history_rows[-window:]] if n > 0 else []
        trailing_n = len(trailing_values)

        # ── Moving Average (simple mean of trailing values) ──────────────────
        if trailing_n > 0:
            daily_ma = sum(trailing_values) / trailing_n
        else:
            daily_ma = 0.0

        # ── Exponential Smoothing (Holt single-parameter with alpha=0.3) ─────
        # Alpha 0.3 is the standard default used by Excel's FORECAST.ETS
        alpha = 0.3
        if trailing_n > 0:
            smoothed = float(trailing_values[0])
            for v in trailing_values[1:]:
                smoothed = alpha * v + (1 - alpha) * smoothed
            daily_es = smoothed
        else:
            daily_es = 0.0

        # ── Standard Deviation of daily demand  ──────────────────────────────
        if trailing_n > 1:
            mean = daily_ma
            variance = sum((v - mean) ** 2 for v in trailing_values) / (trailing_n - 1)
            std_dev = math.sqrt(variance)
        else:
            std_dev = 0.0

        # ── Trend direction (compare first-half vs second-half average) ───────
        if trailing_n >= 4:
            half = trailing_n // 2
            first_half_avg = sum(trailing_values[:half]) / half
            second_half_avg = sum(trailing_values[half:]) / (trailing_n - half)
            if second_half_avg > first_half_avg * 1.05:
                trend_direction = "upward"
            elif second_half_avg < first_half_avg * 0.95:
                trend_direction = "downward"
            else:
                trend_direction = "stable"
        else:
            trend_direction = "stable"

        # ── Totals for the window period ──────────────────────────────────────
        predicted_demand_ma = Decimal(str(round(daily_ma * window, 2)))
        predicted_demand_es = Decimal(str(round(daily_es * window, 2)))

        # ── Safety stock: uses service level Z=1.65 (95%) × std_dev × sqrt(lead_time) ──
        lead_time_days = product.lead_time_days or 7  # fallback to 7 days
        safety_stock_suggestion = int(math.ceil(1.65 * std_dev * math.sqrt(lead_time_days)))

        # ── Suggested order qty (dynamic reorder formula) ─────────────────────
        # EOQ-like logic: order enough to cover window demand + safety stock − current qty
        projected_need = int(math.ceil(daily_es * window)) + safety_stock_suggestion
        suggested_order_qty = max(0, projected_need - product.current_qty)
        reorder_suggestion = max(0, int(math.ceil(daily_es * lead_time_days)) + safety_stock_suggestion - product.current_qty)

        # ── Stock status ──────────────────────────────────────────────────────
        overstock_threshold = max(product.overstock_level, product.reorder_level * 2)
        if product.current_qty <= product.reorder_level:
            stock_status = "Low Stock"
        elif product.current_qty >= overstock_threshold:
            stock_status = "Overstock"
        else:
            stock_status = "Normal"

        # ── Generate cumulative future forecast series (running total) ────────
        # Each point represents "cumulative demand sold by this day" projected from today
        if history_rows:
            base_date = history_rows[-1].sale_date
        else:
            base_date = datetime.now(UTC).date()
        future_forecasts = []
        cumulative_ma = 0.0
        cumulative_es = 0.0
        for i in range(1, window + 1):
            cumulative_ma += daily_ma
            cumulative_es += daily_es
            future_forecasts.append(ForecastSeriesPoint(
                future_date=base_date + timedelta(days=i),
                moving_average_qty=Decimal(str(round(cumulative_ma, 2))),
                exponential_smoothing_qty=Decimal(str(round(cumulative_es, 2))),
            ))

        return DashboardForecastResponse(
            product_id=product_id,
            window=window,
            current_qty=product.current_qty,
            reorder_level=product.reorder_level,
            overstock_level=overstock_threshold,
            historical_sales=historical_sales,
            future_forecasts=future_forecasts,
            predicted_demand_ma=predicted_demand_ma,
            predicted_demand_es=predicted_demand_es,
            daily_demand_es=Decimal(str(round(daily_es, 4))),
            reorder_suggestion=reorder_suggestion,
            suggested_order_qty=suggested_order_qty,
            stock_status=stock_status,
            std_dev=Decimal(str(round(std_dev, 4))),
            trend_direction=trend_direction,
            safety_stock_suggestion=safety_stock_suggestion,
            historical_data_points=n,
        )

    @staticmethod
    def get_alerts(
        db: Session, *, supplier_id: int | None = None, limit: int = 50
    ) -> DashboardAlertsResponse:
        # collect stockout, overstock, and slow items

        product_filters = []
        if supplier_id is not None:
            product_filters.append(Product.supplier_id == supplier_id)

        stockout_stmt = (
            select(Product)
            .where(*product_filters, Product.current_qty <= Product.reorder_level)
            .order_by((Product.reorder_level - Product.current_qty).desc(), Product.id.desc())
            .limit(limit)
        )
        overstock_stmt = (
            select(Product)
            .where(*product_filters, Product.current_qty >= Product.reorder_level * 2)
            .order_by((Product.current_qty - Product.reorder_level * 2).desc(), Product.id.desc())
            .limit(limit)
        )
        stockout_products = db.scalars(stockout_stmt).all()
        overstock_products = db.scalars(overstock_stmt).all()

        since_date = (datetime.now(UTC) - timedelta(days=60)).date()
        slow_subquery = (
            select(
                HistoricalSale.product_id.label("product_id"),
                func.coalesce(func.sum(HistoricalSale.quantity_sold), 0).label("sold_last_60_days"),
            )
            .where(HistoricalSale.sale_date >= since_date)
            .group_by(HistoricalSale.product_id)
            .subquery()
        )
        slow_stmt = (
            select(
                Product.id,
                Product.sku,
                Product.name,
                func.coalesce(slow_subquery.c.sold_last_60_days, 0).label("sold_last_60_days"),
            )
            .outerjoin(slow_subquery, slow_subquery.c.product_id == Product.id)
            .where(
                *product_filters,
                func.coalesce(slow_subquery.c.sold_last_60_days, 0)
                <= case((Product.reorder_level > 0, Product.reorder_level), else_=1),
            )
            .order_by(desc("sold_last_60_days"), Product.id.desc())
            .limit(limit)
        )
        slow_rows = db.execute(slow_stmt).all()

        return DashboardAlertsResponse(
            stockout_risks=[
                ProductRiskItem(
                    product_id=p.id,
                    product_code=p.product_code,
                    sku=p.sku,
                    name=p.name,
                    current_qty=p.current_qty,
                    reorder_level=p.reorder_level,
                    overstock_level=p.overstock_level,
                )
                for p in stockout_products
            ],
            overstock_risks=[
                ProductRiskItem(
                    product_id=p.id,
                    product_code=p.product_code,
                    sku=p.sku,
                    name=p.name,
                    current_qty=p.current_qty,
                    reorder_level=p.reorder_level,
                    overstock_level=p.overstock_level,
                )
                for p in overstock_products
            ],
            slow_moving_items=[
                SlowMovingItem(
                    product_id=row.id,
                    sku=row.sku,
                    name=row.name,
                    sold_last_60_days=int(row.sold_last_60_days or 0),
                )
                for row in slow_rows
            ],
        )
