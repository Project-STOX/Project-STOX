import logging
from typing import Any
# Forced reload - 2026-04-18 11:03 - Stable Local Revert


from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from starlette.middleware.base import BaseHTTPMiddleware

from app.core.audit_middleware import AuditMiddleware
from app.core.config import get_settings
from app.db.database import engine, is_db_fallback_active
from app.models import Base
from app.routes import (
    admin_router,
    auth_router,
    backup_router,
    dashboard_router,
    forecast_router,
    inventory_router,
    notification_router,
    report_router,
    item_router,
    protected_router,
    export_router,
)

settings = get_settings()
logger = logging.getLogger(__name__)

app = FastAPI(title=settings.app_name, version=settings.app_version, debug=settings.debug)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class DebugMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        origin = request.headers.get("origin")
        print(f"DEBUG: Incoming {request.method} request to {request.url.path} from Origin: {origin}")
        return await call_next(request)

app.add_middleware(DebugMiddleware)
app.add_middleware(AuditMiddleware)


@app.exception_handler(HTTPException)
async def http_exception_handler(_: Request, exc: HTTPException) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code, 
        content={"detail": exc.detail},
        headers={
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "*",
            "Access-Control-Allow-Headers": "*",
        }
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(_: Request, exc: Exception) -> JSONResponse:
    import traceback
    with open("server_error.log", "a") as f:
        f.write(f"--- Unhandled Exception ---\n")
        f.write(traceback.format_exc())
        f.write("\n")
    return JSONResponse(
        status_code=500, 
        content={"detail": "Internal server error"},
        headers={
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "*",
            "Access-Control-Allow-Headers": "*",
        }
    )


@app.get(settings.api_prefix + "/health", tags=["system"])
def health_check() -> dict[str, Any]:
    is_fallback = is_db_fallback_active()
    return {
        "status": "ok",
        "database_mode": "failover" if is_fallback else "primary",
        "read_only": is_fallback or settings.local_only_mode
    }


app.include_router(item_router, prefix=settings.api_prefix)
app.include_router(auth_router, prefix=settings.api_prefix)
app.include_router(protected_router, prefix=settings.api_prefix)
app.include_router(admin_router, prefix=settings.api_prefix)
app.include_router(inventory_router, prefix=settings.api_prefix)
app.include_router(notification_router, prefix=settings.api_prefix)
app.include_router(report_router, prefix=settings.api_prefix)
app.include_router(forecast_router, prefix=settings.api_prefix)
app.include_router(dashboard_router, prefix=settings.api_prefix)
app.include_router(backup_router, prefix=settings.api_prefix)
app.include_router(export_router, prefix=settings.api_prefix)


@app.on_event("startup")
def on_startup() -> None:
    from app.db.database import local_engine, is_db_fallback_active

    # Pre-warm the failover cache (synchronous probe, capped at DB_CONNECT_TIMEOUT_SECONDS).
    # This ensures the first user request is never blocked by a Supabase probe.
    fallback = is_db_fallback_active()

    if not fallback:
        logger.info("Primary DB (Supabase) connected successfully.")
        if settings.create_tables_on_startup:
            Base.metadata.create_all(bind=engine)
    else:
        logger.warning("Primary DB unreachable — verifying local failover DB...")
        try:
            with local_engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            logger.info("Local failover DB (localhost) connected. Running in READ-ONLY mode.")
        except Exception as exc:
            logger.warning(
                "Local DB also unreachable: %s — API may be degraded.", exc
            )
