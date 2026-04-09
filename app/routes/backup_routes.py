"""
backup_routes.py
----------------
FastAPI routes for the local PostgreSQL backup feature.
Requires the "Setup backup" permission for triggering a backup or
reading backup metadata.  The permission check is RBAC-driven via
role_permission table just like every other protected route.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse

from app.core.security.dependencies import get_current_user
from app.core.security.rbac import require_permissions
from app.db.database import get_db
from app.models.user import User
from app.services.backup_service import (
    BackupRunner, 
    list_backups, 
    get_backup_config, 
    save_backup_config
)

router = APIRouter(prefix="/backup", tags=["backup"])


@router.get("/list")
def get_backup_list(
    _: User = Depends(require_permissions("Setup backup")),
) -> list[dict]:
    """Return metadata for all existing local backup dump files."""
    return list_backups()


@router.post("/run")
def run_backup(
    sync: bool = False,
    _: User = Depends(require_permissions("Setup backup")),
) -> StreamingResponse:
    """
    Trigger a pg_dump of the remote Supabase database and stream
    Server-Sent Events (SSE) that report progress back to the client.

    If sync=True, it will also attempt to restore the dump locally.
    """
    runner = BackupRunner(sync_local=sync)

    return StreamingResponse(
        runner.run(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",   # disable nginx buffering
        },
    )


@router.get("/config")
def get_config(
    _: User = Depends(require_permissions("Setup backup")),
) -> dict:
    """Return the current backup schedule configuration."""
    return get_backup_config()


@router.put("/config")
def update_config(
    payload: dict,
    _: User = Depends(require_permissions("Setup backup")),
) -> dict:
    """Update the backup schedule configuration."""
    save_backup_config(payload)
    return payload
