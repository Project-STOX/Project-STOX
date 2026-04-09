from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.security.rbac import require_any_permissions
from app.db.database import get_db
from app.models.user import User
from app.schemas.dashboard import (
    DashboardAlertsResponse,
    DashboardForecastResponse,
    DashboardSummaryResponse,
)
from app.services.dashboard_service import DashboardService

router = APIRouter(prefix="/dashboard", tags=["dashboard"])


@router.get("/summary", response_model=DashboardSummaryResponse)
def get_dashboard_summary(
    supplier_id: int | None = Query(default=None, ge=1),
    activity_limit: int = Query(default=10, ge=1, le=100),
    db: Session = Depends(get_db),
    _: User = Depends(require_any_permissions("Manage products", "Manage suppliers", "Manage stock")),
) -> DashboardSummaryResponse:
    return DashboardService.get_summary(db, supplier_id=supplier_id, activity_limit=activity_limit)


@router.get("/forecast", response_model=DashboardForecastResponse)
def get_dashboard_forecast(
    product_id: int = Query(..., ge=1),
    window: int = Query(...),
    supplier_id: int | None = Query(default=None, ge=1),
    db: Session = Depends(get_db),
    _: User = Depends(require_any_permissions("Manage products", "Manage suppliers", "Manage stock", "View forecasts")),
) -> DashboardForecastResponse:
    return DashboardService.get_forecast_view(
        db,
        product_id=product_id,
        window=window,
        supplier_id=supplier_id,
    )


@router.get("/alerts", response_model=DashboardAlertsResponse)
def get_dashboard_alerts(
    supplier_id: int | None = Query(default=None, ge=1),
    limit: int = Query(default=50, ge=1, le=100),
    db: Session = Depends(get_db),
    _: User = Depends(require_any_permissions("Manage products", "Manage suppliers", "Manage stock")),
) -> DashboardAlertsResponse:
    return DashboardService.get_alerts(db, supplier_id=supplier_id, limit=limit)
