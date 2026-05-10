import json
from types import SimpleNamespace
from typing import Any, cast
from unittest.mock import Mock

import app.routes.auth_routes as auth_routes
import app.routes.admin_routes as admin_routes
import app.routes.forecast_routes as forecast_routes
import app.routes.inventory_routes as inventory_routes
import app.services.auth_service as auth_service


def _fake_product():
    # fake product data for route tests
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
    # fake supplier data for route tests
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
    # fake forecast payload for route tests
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
    # check health endpoint response
    monkeypatch.setattr("main.is_db_fallback_active", lambda: False)
    monkeypatch.setattr("main.settings", type("S", (), {"local_only_mode": False})())

    response = client.get("/api/v1/health")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert response.json()["database_mode"] == "primary"
    assert response.json()["read_only"] is False


def test_login_returns_token_pair(client, monkeypatch):
    # check login returns tokens
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
    # check empty login payload fails
    response = client.post("/api/v1/auth/login", json={})

    assert response.status_code == 422


def test_generate_2fa_requires_user_or_email(client):
    # check 2fa needs user or email
    response = client.post("/api/v1/auth/generate-2fa", json={})

    assert response.status_code == 400
    assert response.json()["detail"] == "user_id or email is required"


def test_generate_2fa_unknown_email_returns_404(client, fake_db):
    # check unknown email gives not found
    fake_db.scalar_result = None

    response = client.post("/api/v1/auth/generate-2fa", json={"email": "missing@stox.local"})

    assert response.status_code == 404
    assert response.json()["detail"] == "User not found"


def test_me_returns_current_user(client):
    # check current user endpoint
    response = client.get("/api/v1/auth/me")

    assert response.status_code == 200
    assert response.json()["email"] == "admin@stox.local"
    assert response.json()["role"] == "Admin"


def test_create_user_without_verification_creates_active_user(client, fake_db, monkeypatch):
    # check user create without email verify
    fake_db.get = lambda model, key: SimpleNamespace(id=1, role_name="Admin") if model.__name__ == "Role" else None
    fake_db.refresh = lambda obj: setattr(obj, "id", 101)

    monkeypatch.setattr(
        admin_routes.UserRead,
        "from_user",
        classmethod(
            lambda cls, user: {
                "id": user.id,
                "email": user.email,
                "full_name": user.full_name,
                "role": "Admin",
                "role_id": user.role_id,
                "username": user.full_name,
                "is_active": user.is_active,
                "tfa_active": user.tfa_active,
                "totp_enabled": user.totp_enabled,
            }
        ),
    )

    response = client.post(
        "/api/v1/admin/users",
        json={
            "username": "New User",
            "email": "new.user@stox.local",
            "password": "Secret123!",
            "role_id": 1,
            "verify_email": False,
        },
    )

    assert response.status_code == 201
    assert response.json()["is_active"] is True


def test_create_user_with_verification_sends_email_and_marks_inactive(client, fake_db, monkeypatch):
    # check user create with email verify
    fake_db.get = lambda model, key: SimpleNamespace(id=1, role_name="Admin") if model.__name__ == "Role" else None
    fake_db.refresh = lambda obj: setattr(obj, "id", 102)

    sent_to: list[str] = []

    def fake_send_email_verification(db, user):
        sent_to.append(user.email)

    monkeypatch.setattr(
        auth_service.AuthService,
        "send_email_verification",
        staticmethod(fake_send_email_verification),
    )
    monkeypatch.setattr(
        admin_routes.UserRead,
        "from_user",
        classmethod(
            lambda cls, user: {
                "id": user.id,
                "email": user.email,
                "full_name": user.full_name,
                "role": "Admin",
                "role_id": user.role_id,
                "username": user.full_name,
                "is_active": user.is_active,
                "tfa_active": user.tfa_active,
                "totp_enabled": user.totp_enabled,
            }
        ),
    )

    response = client.post(
        "/api/v1/admin/users",
        json={
            "username": "Pending User",
            "email": "pending.user@stox.local",
            "password": "Secret123!",
            "role_id": 1,
            "verify_email": True,
        },
    )

    assert response.status_code == 201
    assert response.json()["is_active"] is False
    assert sent_to == ["pending.user@stox.local"]


def test_verify_email_activates_pending_user(client, fake_db, monkeypatch):
    # check email verify activates user
    pending_email = "pending.user@stox.local"
    auth_service._PENDING_EMAIL_VERIFICATIONS[pending_email] = {
        "user_id": 1,
        "expire_at": 9999999999,
    }
    fake_db.scalar_result = SimpleNamespace(id=1, email=pending_email, is_active=False)

    monkeypatch.setattr(
        auth_service.AuthService,
        "_fetch_supabase_user",
        staticmethod(lambda access_token: {"email": pending_email}),
    )

    response = client.post(
        "/api/v1/auth/verify-email",
        json={"access_token": "access-token-from-callback"},
    )

    assert response.status_code == 200
    assert response.json()["message"] == "Email verified successfully."
    assert fake_db.scalar_result.is_active is True
    assert pending_email not in auth_service._PENDING_EMAIL_VERIFICATIONS


def test_verify_email_callback_serves_html(client):
    # check verify callback page
    response = client.get("/api/v1/auth/verify-email/callback")

    assert response.status_code == 200
    assert "Verifying your email" in response.text
    assert "api/v1/auth/verify-email" in response.text


def test_send_supabase_signup_confirmation_posts_to_signup_endpoint(monkeypatch):
    # check signup request goes to supabase
    captured = {}

    class FakeResponse:
        status = 200

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

    def fake_urlopen(req, timeout, context):
        captured["url"] = req.full_url
        captured["body"] = json.loads(req.data.decode("utf-8"))
        return FakeResponse()

    monkeypatch.setattr(auth_service.settings, "supabase_url", "https://project.supabase.co", raising=False)
    monkeypatch.setattr(auth_service.settings, "supabase_anon_key", "anon-key", raising=False)
    monkeypatch.setattr(auth_service.request, "urlopen", fake_urlopen)

    auth_service.AuthService._send_supabase_signup_confirmation(
        "new.user@stox.local",
        redirect_to="http://localhost:8000/api/v1/auth/verify-email/callback",
    )

    assert captured["url"] == (
        "https://project.supabase.co/auth/v1/signup"
        "?redirect_to=http%3A%2F%2Flocalhost%3A8000%2Fapi%2Fv1%2Fauth%2Fverify-email%2Fcallback"
    )
    assert captured["body"]["email"] == "new.user@stox.local"
    assert captured["body"]["password"].endswith("Aa1!")


def test_send_email_verification_registers_pending_state_with_callback(monkeypatch):
    # check verification state is saved
    captured = {}
    pending_email = "Pending.User@stox.local"

    def fake_send_signup_confirmation(email_address, redirect_to=None):
        captured["email"] = email_address
        captured["redirect_to"] = redirect_to

    monkeypatch.setattr(auth_service.settings, "supabase_url", "https://project.supabase.co", raising=False)
    monkeypatch.setattr(auth_service.settings, "supabase_anon_key", "anon-key", raising=False)
    monkeypatch.setattr(auth_service.settings, "backend_origin", "http://localhost:8000", raising=False)
    monkeypatch.setattr(
        auth_service.AuthService,
        "_send_supabase_signup_confirmation",
        staticmethod(fake_send_signup_confirmation),
    )

    auth_service.AuthService.send_email_verification(
        cast(Any, None),
        cast(Any, SimpleNamespace(id=77, email=pending_email)),
    )

    assert captured["email"] == pending_email
    assert captured["redirect_to"] == "http://localhost:8000/api/v1/auth/verify-email/callback"
    assert auth_service._PENDING_EMAIL_VERIFICATIONS[pending_email.lower()]["user_id"] == 77
    auth_service._PENDING_EMAIL_VERIFICATIONS.pop(pending_email.lower(), None)


def test_forecast_generate_returns_service_payload(client, monkeypatch):
    # check forecast endpoint response
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
    # check supplier create route
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
    # check product create route
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
    # check product import rejects bad file
    response = client.post(
        "/api/v1/inventory/products/import-csv",
        files={"file": ("products.txt", b"not csv", "text/plain")},
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "Only CSV files are allowed"


def test_stock_receipt_import_rejects_empty_csv(client):
    # check empty receipt csv fails
    response = client.post(
        "/api/v1/inventory/stock-receipts/import-csv",
        files={"file": ("receipts.csv", b"", "text/csv")},
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "Uploaded CSV is empty"


def test_stock_receipt_list_query_validation_rejects_zero_limit(client):
    # check invalid limit fails
    response = client.get("/api/v1/inventory/stock-receipts?limit=0")

    assert response.status_code == 422
