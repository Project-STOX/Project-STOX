from types import SimpleNamespace
from unittest.mock import Mock

import app.routes.auth_routes as auth_routes
import app.routes.forecast_routes as forecast_routes
import app.routes.inventory_routes as inventory_routes


def _fake_product():
    return SimpleNamespace(
        id=10,
        product_code="P-001",
        sku="SKU-001",
        name="Test Product",
        supplier_id=2,
        current_qty=25,
        reorder_level=10,
        overstock_level=100,
        unit_cost=50,
        serial_no=None,
        lead_time_days=7,
        holding_cost=5,
        ordering_cost=10,
        status_flag="In Stock",
    )


def _fake_supplier():
    return SimpleNamespace(
        id=7,
        name="Test Supplier",
        email="supplier@example.com",
        phone="0123456789",
        address="Warehouse Road",
        lead_time_days=5,
        is_active=True,
    )


def _fake_forecast_payload():
    return {
        "generated_records": 1,
        "forecasts": [
            {
                "product_id": 10,
                "method": "MOVING_AVERAGE",
                "window_days": 30,
                "predicted_qty": "120.00",
                "reorder_suggestion": 15,
            }
        ],
    }


def test_health_endpoint_reports_ok(client, monkeypatch):
    monkeypatch.setattr("main.is_db_fallback_active", lambda: False)
    monkeypatch.setattr("main.settings", type("S", (), {"local_only_mode": False})())

    response = client.get("/api/v1/health")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert response.json()["database_mode"] == "primary"
    assert response.json()["read_only"] is False


def test_login_returns_token_pair(client, monkeypatch):
    monkeypatch.setattr(
        auth_routes.AuthService,
        "login_step_one",
        staticmethod(
            lambda db, payload: {
                "access_token": "access-token",
                "refresh_token": "refresh-token",
                "token_type": "bearer",
                "user": {
                    "id": 1,
                    "email": "admin@stox.local",
                    "full_name": "Admin User",
                    "role": "Admin",
                    "role_id": 1,
                    "username": "Admin User",
                    "is_active": True,
                    "tfa_active": False,
                    "totp_enabled": False,
                },
            }
        ),
    )

    response = client.post("/api/v1/auth/login", json={"email": "admin@stox.local", "password": "Secret123!"})

    assert response.status_code == 200
    assert response.json()["access_token"] == "access-token"
    assert response.json()["refresh_token"] == "refresh-token"


def test_login_rejects_empty_payload(client):
    response = client.post("/api/v1/auth/login", json={})

    assert response.status_code == 422


def test_generate_2fa_requires_user_or_email(client):
    response = client.post("/api/v1/auth/generate-2fa", json={})

    assert response.status_code == 400
    assert response.json()["detail"] == "user_id or email is required"


def test_generate_2fa_unknown_email_returns_404(client, fake_db):
    fake_db.scalar_result = None

    response = client.post("/api/v1/auth/generate-2fa", json={"email": "missing@stox.local"})

    assert response.status_code == 404
    assert response.json()["detail"] == "User not found"


def test_me_returns_current_user(client):
    response = client.get("/api/v1/auth/me")

    assert response.status_code == 200
    assert response.json()["email"] == "admin@stox.local"
    assert response.json()["role"] == "Admin"


def test_forecast_generate_returns_service_payload(client, monkeypatch):
    called = {}

    def fake_generate_forecast(db, *, alpha, windows):
        called["alpha"] = alpha
        called["windows"] = windows
        return SimpleNamespace(**_fake_forecast_payload())

    monkeypatch.setattr(forecast_routes.ForecastService, "generate_forecast", staticmethod(fake_generate_forecast))

    response = client.post("/api/v1/forecast/generate", json={"alpha": 0.3, "windows": [30, 60]})

    assert response.status_code == 200
    assert response.json()["generated_records"] == 1
    assert called == {"alpha": 0.3, "windows": [30, 60]}


def test_create_supplier_returns_created_resource(client, monkeypatch):
    monkeypatch.setattr(inventory_routes.SupplierService, "create_supplier", staticmethod(lambda db, payload, created_by: _fake_supplier()))

    response = client.post(
        "/api/v1/inventory/suppliers",
        json={
            "name": "Test Supplier",
            "email": "supplier@example.com",
            "phone": "0123456789",
            "address": "Warehouse Road",
            "lead_time_days": 5,
            "is_active": True,
        },
    )

    assert response.status_code == 201
    assert response.json()["name"] == "Test Supplier"
    assert response.json()["email"] == "supplier@example.com"


def test_create_product_returns_created_resource(client, monkeypatch):
    monkeypatch.setattr(inventory_routes.ProductService, "create_product", staticmethod(lambda db, payload, actor_id: _fake_product()))

    response = client.post(
        "/api/v1/inventory/products",
        json={
            "product_code": "P-001",
            "sku": "SKU-001",
            "name": "Test Product",
            "supplier_id": 2,
            "current_qty": 25,
            "reorder_level": 10,
            "overstock_level": 100,
            "unit_cost": 50,
            "serial_no": None,
            "lead_time_days": 7,
            "holding_cost": 5,
            "ordering_cost": 10,
        },
    )

    assert response.status_code == 201
    assert response.json()["product_code"] == "P-001"
    assert response.json()["status_flag"] == "In Stock"


def test_product_import_rejects_non_csv_file(client):
    response = client.post(
        "/api/v1/inventory/products/import-csv",
        files={"file": ("products.txt", b"not csv", "text/plain")},
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "Only CSV files are allowed"


def test_stock_receipt_import_rejects_empty_csv(client):
    response = client.post(
        "/api/v1/inventory/stock-receipts/import-csv",
        files={"file": ("receipts.csv", b"", "text/csv")},
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "Uploaded CSV is empty"


def test_stock_receipt_list_query_validation_rejects_zero_limit(client):
    response = client.get("/api/v1/inventory/stock-receipts?limit=0")

    assert response.status_code == 422
