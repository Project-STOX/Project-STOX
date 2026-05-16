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
    # simple fake user for auth tests

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
        # return fake role name

        return self._role_name


class FakeDb:
    def __init__(self, scalar_result=None):
        # store fake db result and call history

        self.scalar_result = scalar_result
        self.scalar_calls: list[object] = []
        self.get_calls: list[tuple[object, object]] = []
        self.closed = False

    def scalar(self, query):
        # record scalar query and return fake result

        self.scalar_calls.append(query)
        return self.scalar_result

    def get(self, model, key):
        # record get call and act like row not found

        self.get_calls.append((model, key))
        return None

    def close(self):
        # mark session closed

        self.closed = True

    def commit(self):
        # pretend commit worked

        return None

    def refresh(self, obj):
        # pretend refresh worked

        return None

    def add(self, obj):
        # pretend add worked

        return None

    def flush(self):
        # pretend flush worked

        return None

    def execute(self, *args, **kwargs):
        # pretend query ran

        return None

    def delete(self, *args, **kwargs):
        # pretend delete worked

        return None

    def rollback(self):
        # pretend rollback worked

        return None


def fake_get_db(db: FakeDb):
    # give fake db in same shape as real dependency

    def _gen():
        # yield fake session one time

        yield db

    return _gen()


@pytest.fixture()
def fake_user() -> FakeUser:
    # return fake user fixture

    return FakeUser()


@pytest.fixture()
def fake_db() -> FakeDb:
    # return fake db fixture

    return FakeDb()


@pytest.fixture()
def client(monkeypatch, fake_user, fake_db):
    # create test client with fake dependencies

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
