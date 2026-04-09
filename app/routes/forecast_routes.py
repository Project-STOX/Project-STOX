from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.security.rbac import require_permissions
from app.db.database import get_db
from app.models.user import User
from app.schemas.forecast import ForecastGenerateRequest, ForecastGenerateResponse
from app.services.forecast_service import ForecastService

router = APIRouter(prefix="/forecast", tags=["forecast"])


@router.post("/generate", response_model=ForecastGenerateResponse)
def generate_forecast(
    payload: ForecastGenerateRequest,
    db: Session = Depends(get_db),
    _: User = Depends(require_permissions("View forecasts")),
) -> ForecastGenerateResponse:
    return ForecastService.generate_forecast(db, alpha=payload.alpha, windows=payload.windows)
