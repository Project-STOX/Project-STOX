"""
export_routes.py
----------------
FastAPI routes for the consumer-facing CSV/ZIP data export feature.
All endpoints are restricted to role_id == 1 (SME Owner).

NOTE: Backup schedules are persisted client-side (Flutter SharedPreferences).
The backend only handles the actual data export — no schedule table needed.
"""
from __future__ import annotations

import logging
import traceback
from fastapi import APIRouter, Body, Depends, HTTPException, status
from fastapi.responses import FileResponse
from starlette.background import BackgroundTask
from sqlalchemy.orm import Session
import os
from typing import Any

from app.core.security.dependencies import get_current_user
from app.db.database import get_db
from app.models.user import User
from app.services.export_service import ALL_CATEGORIES, build_export_zip
from app.services.auth_service import AuthService
from app.services.audit_service import AuditService

router = APIRouter(prefix="/export", tags=["export"])
_log = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────
# Guard — SME Owner only (role_id == 1)
# ─────────────────────────────────────────────────────────────────────────────

def _require_sme_owner(
    current_user: User = Depends(get_current_user),
) -> User:
    if current_user.role_id != 1:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This feature is available to SME Owners only.",
        )
    return current_user


# ─────────────────────────────────────────────────────────────────────────────
# Routes
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/categories")
def list_categories(_: User = Depends(_require_sme_owner)) -> list[dict[str, str]]:
    """Return all available export categories with display labels."""
    return [
        {"key": "users", "label": "Users", "description": "All user accounts and their assigned roles"},
        {"key": "roles_permissions", "label": "Roles & Permissions", "description": "Role definitions and permission assignments"},
        {"key": "products", "label": "Products", "description": "Product catalogue, pricing, stock levels, and reorder parameters"},
        {"key": "suppliers", "label": "Suppliers", "description": "Supplier details and lead times"},
        {"key": "stock_receipts", "label": "Stock Receipts", "description": "All recorded stock receipt transactions"},
        {"key": "historical_sales", "label": "Historical Sales", "description": "Past sales volumes and revenue by product"},
        {"key": "demand_forecasts", "label": "Demand Forecasts", "description": "All generated demand forecast predictions"},
        {"key": "audit_log", "label": "Audit Log", "description": "Full system activity and change history"},
        {"key": "notifications", "label": "Notifications", "description": "All sent system and user notifications"},
    ]


@router.post("/run")
def run_export(
    payload: dict[str, Any] = Body(...),
    current_user: User = Depends(_require_sme_owner),
    db: Session = Depends(get_db),
) -> FileResponse:
    """
    Generate and stream a ZIP file containing data for the selected categories.
    The ZIP is returned as binary — no files are persisted server-side.
    """
    categories: list[str] = payload.get("categories", [])
    formats: list[str] = payload.get("formats", ["csv"])
    
    valid_formats = {"csv", "json", "sql"}
    if not all(fmt in valid_formats for fmt in formats) or not formats:
        raise HTTPException(status_code=400, detail="Formats must be from 'csv', 'json', 'sql' and not empty")

    if not categories:
        raise HTTPException(status_code=400, detail="At least one category must be selected.")

    invalid = [c for c in categories if c not in ALL_CATEGORIES]
    if invalid:
        raise HTTPException(status_code=400, detail=f"Unknown categories: {invalid}")

    try:
        zip_filepath, zip_filename = build_export_zip(db, categories, formats)
    except Exception as exc:
        _log.error("Export failed: %s\n%s", exc, traceback.format_exc())
        raise HTTPException(
            status_code=500,
            detail=f"Export generation failed: {str(exc)}",
        )

    return FileResponse(
        path=zip_filepath,
        media_type="application/zip",
        filename=zip_filename,
        background=BackgroundTask(os.remove, zip_filepath),
        headers={
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )


@router.post("/end-of-contract")
def end_of_contract(
    payload: dict[str, Any] = Body(...),
    current_user: User = Depends(_require_sme_owner),
    db: Session = Depends(get_db),
) -> FileResponse:
    """
    Validates user password, triggers a system Audit Alert for IT to close the account,
    and returns the final data export in the requested format.
    """
    password = payload.get("password")
    categories = payload.get("categories", [])
    formats = payload.get("formats", ["csv"])
    feedback = payload.get("feedback", "")

    if not password:
        raise HTTPException(status_code=400, detail="Password is required for termination.")
    
    if not AuthService.check_user_password(current_user, password):
        raise HTTPException(status_code=401, detail="Invalid password.")

    valid_formats = {"csv", "json", "sql"}
    if not isinstance(formats, list) or not all(fmt in valid_formats for fmt in formats) or not formats:
        raise HTTPException(status_code=400, detail="Formats must be from 'csv', 'json', 'sql'")

    if not categories:
        raise HTTPException(status_code=400, detail="At least one category must be selected.")

    invalid = [c for c in categories if c not in ALL_CATEGORIES]
    if invalid:
        raise HTTPException(status_code=400, detail=f"Unknown categories: {invalid}")

    # Official notification logic for IT
    # The prompt explicitly asks to log a notification for IT
    AuditService.write_log(
        db,
        user_id=current_user.id,
        action="SME requested Account Closure - Notifying IT",
        entity_type="users",
        entity_id=current_user.id,
    )

    if feedback:
        AuditService.write_log(
            db,
            user_id=current_user.id,
            action=f"End of Contract Feedback: {feedback}",
            entity_type="users",
            entity_id=current_user.id,
        )

    try:
        zip_filepath, zip_filename = build_export_zip(db, categories, formats)
    except Exception as exc:
        _log.error("Export failed: %s\\n%s", exc, traceback.format_exc())
        raise HTTPException(
            status_code=500,
            detail=f"Export generation failed: {str(exc)}",
        )

    return FileResponse(
        path=zip_filepath,
        media_type="application/zip",
        filename=zip_filename,
        background=BackgroundTask(os.remove, zip_filepath),
        headers={
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )
