from __future__ import annotations

from dataclasses import dataclass
from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient

import app.core.audit_middleware as audit_middleware
import app.core.security.rbac as rbac
import app.routes.auth_routes as auth_routes
import app.routes.forecast_routes as forecast_routes
import app.routes.inventory_routes as inventory_routes
import main
from app.models.user import User
from app.db.database import get_db as database_get_db


@dataclass
class FakeUser:
    id: int = 1
    email: str = "admin@stox.local"
    full_name: str = "Admin User"
    role_id: int = 1
    is_active: bool = True
    tfa_active: bool = False
    totp_enabled: bool = False
    _role_name: str = "Admin"

    @property
    def role_name(self) -> str:
        return self._role_name


class FakeDb:
    def __init__(self, scalar_result=None):
        self.scalar_result = scalar_result
        self.scalar_calls: list[object] = []
        self.get_calls: list[tuple[object, object]] = []
        self.closed = False

    def scalar(self, query):
        self.scalar_calls.append(query)
        return self.scalar_result

    def get(self, model, key):
        self.get_calls.append((model, key))
        return None

    def close(self):
        self.closed = True

    def commit(self):
        return None

    def refresh(self, obj):
        return None

    def add(self, obj):
        return None

    def flush(self):
        return None

    def execute(self, *args, **kwargs):
        return None

    def delete(self, *args, **kwargs):
        return None

    def rollback(self):
        return None


def fake_get_db(db: FakeDb):
    def _gen():
        yield db

    return _gen()


@pytest.fixture()
def fake_user() -> FakeUser:
    return FakeUser()


@pytest.fixture()
def fake_db() -> FakeDb:
    return FakeDb()


@pytest.fixture()
def client(monkeypatch, fake_user, fake_db):
    monkeypatch.setattr(main, "is_db_fallback_active", lambda: False)
    monkeypatch.setattr(main.settings, "create_tables_on_startup", False)

    monkeypatch.setattr(audit_middleware, "get_db", lambda: fake_get_db(fake_db))
    monkeypatch.setattr(rbac, "_has_permission", lambda db, role_id, permission_name: True)

    main.app.dependency_overrides[database_get_db] = lambda: fake_db
    main.app.dependency_overrides[auth_routes.get_db] = lambda: fake_db
    main.app.dependency_overrides[forecast_routes.get_db] = lambda: fake_db
    main.app.dependency_overrides[inventory_routes.get_db] = lambda: fake_db
    main.app.dependency_overrides[auth_routes.get_current_user] = lambda: fake_user
    main.app.dependency_overrides[forecast_routes.require_permissions] = lambda *args, **kwargs: fake_user

    with TestClient(main.app) as test_client:
        yield test_client

    main.app.dependency_overrides.clear()
