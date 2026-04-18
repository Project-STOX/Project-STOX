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
from datetime import datetime
from fastapi import APIRouter, Body, Depends, HTTPException, status
from fastapi.responses import FileResponse
from starlette.background import BackgroundTask
from sqlalchemy.orm import Session
import os
from typing import Any

from app.core.security.dependencies import get_current_user
from app.db.database import get_db
from app.models.user import User
from app.models.backup_schedule import BackupSchedule
from app.services.export_service import ALL_CATEGORIES, build_export_zip
from app.services.auth_service import AuthService
from app.services.audit_service import AuditService
from app.services.feedback_service import FeedbackService
from pydantic import BaseModel
import json

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


class FeedbackRequest(BaseModel):
    category: str
    message: str

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


@router.post("/feedback")
def submit_feedback(
    payload: FeedbackRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict[str, str]:
    """Submit user feedback."""
    FeedbackService.save_feedback(
        db,
        user_id=current_user.id,
        username=current_user.full_name,
        email=current_user.email,
        category=payload.category,
        message=payload.message
    )
    return {"status": "success", "message": "Feedback received. Thank you!"}


@router.get("/schedules")
def list_schedules(
    current_user: User = Depends(_require_sme_owner),
    db: Session = Depends(get_db),
) -> list[dict[str, Any]]:
    """Return all backup schedules for the current SME owner."""
    schedules = (
        db.query(BackupSchedule)
        .filter(BackupSchedule.user_id == current_user.id)
        .order_by(BackupSchedule.id)
        .all()
    )
    return [
        {
            "id": s.id,
            "label": s.label,
            "categories": s.categories,
            "frequency": s.frequency,
            "scheduled_time": s.scheduled_time,
            "day_of_week": s.day_of_week,
            "day_of_month": s.day_of_month,
            "month": s.month,
            "last_run_at": s.last_run_at.isoformat() if s.last_run_at else None,
            "next_run_at": s.next_run_at.isoformat() if s.next_run_at else None,
        }
        for s in schedules
    ]


@router.post("/schedules")
def create_schedule(
    payload: dict[str, Any] = Body(...),
    current_user: User = Depends(_require_sme_owner),
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    """Create a new backup schedule."""
    # Enforce limit of 10 schedules per user
    count = db.query(BackupSchedule).filter(BackupSchedule.user_id == current_user.id).count()
    if count >= 10:
        raise HTTPException(status_code=400, detail="Maximum of 10 schedules allowed.")

    try:
        new_schedule = BackupSchedule(
            user_id=current_user.id,
            label=payload.get("label", "New Backup"),
            frequency=payload.get("frequency", "daily"),
            scheduled_time=payload.get("scheduled_time", "02:00"),
            day_of_week=payload.get("day_of_week"),
            day_of_month=payload.get("day_of_month"),
            month=payload.get("month"),
        )
        new_schedule.categories = payload.get("categories", [])
        
        db.add(new_schedule)
        db.commit()
        db.refresh(new_schedule)
        return {"id": new_schedule.id}
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=500, detail=str(exc))


@router.delete("/schedules/{schedule_id}")
def delete_schedule(
    schedule_id: int,
    current_user: User = Depends(_require_sme_owner),
    db: Session = Depends(get_db),
) -> dict[str, str]:
    """Delete a backup schedule."""
    schedule = (
        db.query(BackupSchedule)
        .filter(BackupSchedule.id == schedule_id, BackupSchedule.user_id == current_user.id)
        .first()
    )
    if not schedule:
        raise HTTPException(status_code=404, detail="Schedule not found.")

    db.delete(schedule)
    db.commit()
    return {"status": "deleted"}


@router.patch("/schedules/{schedule_id}/mark-run")
def mark_schedule_run(
    schedule_id: int,
    current_user: User = Depends(_require_sme_owner),
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    """Update the last_run_at timestamp for a schedule."""
    schedule = (
        db.query(BackupSchedule)
        .filter(BackupSchedule.id == schedule_id, BackupSchedule.user_id == current_user.id)
        .first()
    )
    if not schedule:
        raise HTTPException(status_code=404, detail="Schedule not found.")

    schedule.last_run_at = datetime.now()
    db.commit()
    return {"id": schedule.id, "last_run_at": schedule.last_run_at.isoformat()}


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
