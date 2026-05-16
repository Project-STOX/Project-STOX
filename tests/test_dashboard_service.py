from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import Mock

import pytest

from app.services.dashboard_service import DashboardService
from app.core.audit_middleware import AuditMiddleware


def _product(**overrides):
    data = {
        "id": 1,
        "product_code": "P-001",
        "sku": "SKU-001",
        "name": "Product 1",
        "supplier_id": 2,
        "current_qty": 25,
        "reorder_level": 10,
        "overstock_level": 100,
        "unit_cost": Decimal("10.00"),
        "lead_time_days": 7,
        "reorder_params": SimpleNamespace(safety_stock=5, lead_time_days=7),
    }
    data.update(overrides)
    return SimpleNamespace(**data)


def _sale_row(day: date, qty: int):
    return SimpleNamespace(sale_date=day, quantity_sold=qty)


def test_dashboard_summary_returns_empty_values_when_no_data():
    db = Mock()
    db.scalar.side_effect = [
        0,
        0,
        Decimal("0"),
        Decimal("0"),
        Decimal("0"),
        Decimal("0"),
        None,
    ]
    db.scalars.return_value.all.return_value = []
    db.execute.side_effect = [Mock(first=lambda: None), Mock(first=lambda: None), Mock(all=lambda: [])]

    summary = DashboardService.get_summary(db)

    assert summary.total_products == 0
    assert summary.low_stock_count == 0
    assert summary.stock_value == Decimal("0")
    assert summary.receipts_value == Decimal("0")
    assert summary.forecast_worth_30d == Decimal("0")
    assert summary.forecast_worth_60d == Decimal("0")
    assert summary.total_inventory_historical_sales[0].quantity_sold == 0
    assert len(summary.total_inventory_forecast_30d) == 30
    assert len(summary.total_inventory_forecast_60d) == 60


def test_dashboard_summary_with_recent_receipts_and_important_product():
    db = Mock()
    db.scalar.side_effect = [
        3,
        1,
        Decimal("125.00"),
        Decimal("80.00"),
        Decimal("150.00"),
        Decimal("300.00"),
        date(2026, 4, 1),
    ]
    db.scalars.return_value.all.return_value = [
        SimpleNamespace(product_id=1, quantity=5, received_at=datetime(2026, 4, 20, 10, 0, tzinfo=UTC)),
    ]
    db.execute.side_effect = [
        Mock(first=lambda: (_product(), SimpleNamespace(name="Supplier A"), SimpleNamespace(eoq=Decimal("12.50")))),
        Mock(first=lambda: None),
        Mock(all=lambda: [SimpleNamespace(sale_date=date(2026, 4, 1), daily_qty=4)]),
    ]

    summary = DashboardService.get_summary(db)

    assert summary.total_products == 3
    assert summary.low_stock_count == 1
    assert summary.recent_activity[0].product_id == 1
    assert summary.most_important_product is not None
    assert summary.most_important_product.eoq == Decimal("12.50")
    assert summary.least_important_product is None


def test_forecast_view_rejects_invalid_window():
    with pytest.raises(Exception) as exc_info:
        DashboardService.get_forecast_view(Mock(), product_id=1, window=29)

    assert getattr(exc_info.value, "status_code", None) == 400


def test_forecast_view_returns_not_found_for_missing_product():
    db = Mock()
    db.scalar.return_value = None

    with pytest.raises(Exception) as exc_info:
        DashboardService.get_forecast_view(db, product_id=99, window=30)

    assert getattr(exc_info.value, "status_code", None) == 404


def test_forecast_view_classifies_stable_trend():
    db = Mock()
    db.scalar.side_effect = [
        _product(current_qty=25, reorder_level=10, overstock_level=40),
    ]
    db.scalars.return_value.all.return_value = [
        _sale_row(date(2026, 4, 1), 5),
        _sale_row(date(2026, 4, 2), 5),
        _sale_row(date(2026, 4, 3), 5),
        _sale_row(date(2026, 4, 4), 5),
    ]

    result = DashboardService.get_forecast_view(db, product_id=1, window=30)

    assert result.trend_direction == "stable"
    assert result.stock_status == "Normal"
    assert result.historical_data_points == 4
    assert len(result.future_forecasts) == 30


def test_forecast_view_classifies_upward_trend():
    db = Mock()
    db.scalar.side_effect = [
        _product(current_qty=25, reorder_level=10, overstock_level=100),
    ]
    db.scalars.return_value.all.return_value = [
        _sale_row(date(2026, 4, 1), 1),
        _sale_row(date(2026, 4, 2), 1),
        _sale_row(date(2026, 4, 3), 10),
        _sale_row(date(2026, 4, 4), 10),
    ]

    result = DashboardService.get_forecast_view(db, product_id=1, window=30)

    assert result.trend_direction == "upward"
    assert result.predicted_demand_es > result.predicted_demand_ma / 2


def test_forecast_view_classifies_downward_trend_and_overstock():
    db = Mock()
    db.scalar.side_effect = [
        _product(current_qty=250, reorder_level=10, overstock_level=100),
    ]
    db.scalars.return_value.all.return_value = [
        _sale_row(date(2026, 4, 1), 10),
        _sale_row(date(2026, 4, 2), 10),
        _sale_row(date(2026, 4, 3), 1),
        _sale_row(date(2026, 4, 4), 1),
    ]

    result = DashboardService.get_forecast_view(db, product_id=1, window=30)

    assert result.trend_direction == "downward"
    assert result.stock_status == "Overstock"


def test_alerts_return_stockout_overstock_and_slow_moving_items():
    db = Mock()
    db.scalars.side_effect = [
        SimpleNamespace(all=lambda: [
            _product(id=1, current_qty=5, reorder_level=10, overstock_level=100, product_code="A-1", sku="SKU-A1", name="Low Item"),
        ]),
        SimpleNamespace(all=lambda: [
            _product(id=2, current_qty=250, reorder_level=10, overstock_level=100, product_code="B-1", sku="SKU-B1", name="High Item"),
        ]),
    ]
    db.execute.return_value.all.return_value = [
        SimpleNamespace(id=3, sku="SKU-C1", name="Slow Item", sold_last_60_days=0),
    ]

    alerts = DashboardService.get_alerts(db, limit=10)

    assert len(alerts.stockout_risks) == 1
    assert alerts.stockout_risks[0].name == "Low Item"
    assert len(alerts.overstock_risks) == 1
    assert alerts.overstock_risks[0].name == "High Item"
    assert len(alerts.slow_moving_items) == 1
    assert alerts.slow_moving_items[0].sku == "SKU-C1"


def test_audit_middleware_extracts_nested_entity_id():
    entity_type, entity_id = AuditMiddleware._extract_entity("/api/v1/inventory/products/42")

    assert entity_type == "products"
    assert entity_id == 42
