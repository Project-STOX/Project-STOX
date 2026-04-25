from datetime import datetime

import pytest
from pydantic import ValidationError

from app.schemas.stock_receipt import StockReceiptCreate, StockReceiptImportRow, _parse_received_at


def test_parse_received_at_supports_iso_datetime() -> None:
    parsed = _parse_received_at("2026-04-21T10:30:00")
    assert parsed == datetime(2026, 4, 21, 10, 30, 0)


def test_parse_received_at_supports_spreadsheet_datetime() -> None:
    parsed = _parse_received_at("4/21/2026 10:30")
    assert parsed == datetime(2026, 4, 21, 10, 30)


def test_parse_received_at_empty_string_returns_none() -> None:
    assert _parse_received_at("  ") is None


def test_parse_received_at_invalid_format_raises_value_error() -> None:
    with pytest.raises(ValueError):
        _parse_received_at("21-04-2026 10:30")


def test_stock_receipt_create_rejects_damaged_greater_than_quantity() -> None:
    with pytest.raises(ValidationError):
        StockReceiptCreate(
            product_id=1,
            supplier_id=2,
            quantity=5,
            quantity_damaged=6,
            unit_cost=10,
            received_at="2026-04-21T10:30:00",
        )


def test_stock_receipt_create_accepts_boundary_damaged_equals_quantity() -> None:
    payload = StockReceiptCreate(
        product_id=1,
        supplier_id=2,
        quantity=5,
        quantity_damaged=5,
        unit_cost=10,
        received_at="2026-04-21",
    )
    assert payload.quantity_damaged == payload.quantity == 5


def test_stock_receipt_import_row_validates_positive_quantity() -> None:
    with pytest.raises(ValidationError):
        StockReceiptImportRow(
            product_code="P-001",
            supplier_id=1,
            quantity=0,
            quantity_damaged=0,
            received_at="2026-04-21",
        )
