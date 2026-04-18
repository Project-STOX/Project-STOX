import logging
# Forced reload - 2026-04-08 23:21


from fastapi import FastAPI
from fastapi import HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text

from app.core.audit_middleware import AuditMiddleware
from app.core.config import get_settings
from app.db.database import engine
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

app.add_middleware(AuditMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # More permissive for testing/failover mode
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(HTTPException)
async def http_exception_handler(_: Request, exc: HTTPException) -> JSONResponse:
    return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})


@app.exception_handler(Exception)
async def unhandled_exception_handler(_: Request, exc: Exception) -> JSONResponse:
    import traceback
    with open("server_error.log", "a") as f:
        f.write(f"--- Unhandled Exception ---\n")
        f.write(traceback.format_exc())
        f.write("\n")
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})


@app.get("/health", tags=["system"])
def health_check() -> dict[str, str]:
    return {"status": "ok"}


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
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
        if settings.create_tables_on_startup:
            Base.metadata.create_all(bind=engine)
    except Exception as exc:
        logger.warning(
            "Database startup check failed; continuing without eager DB validation: %s",
            exc,
        )

