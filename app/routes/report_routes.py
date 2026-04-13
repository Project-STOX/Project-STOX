from datetime import date

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.core.security.dependencies import get_current_user
from app.core.security.rbac import require_permissions
from app.db.database import get_db
from app.models.user import User
from app.schemas.imports import CsvImportResult
from app.schemas.reports import AuditLogCreateRequest, AuditLogRead, HistoricalSaleImportRequest, HistoricalSaleRead
from app.services.audit_service import AuditService
from app.services.report_service import ReportService

router = APIRouter(prefix="/reports", tags=["reports"])


@router.get("/audit-logs", response_model=list[AuditLogRead])
def list_audit_logs(
    limit: int = Query(default=500, ge=1, le=1000),
    db: Session = Depends(get_db),
    _: User = Depends(require_permissions("View audit log")),
) -> list[AuditLogRead]:
    return ReportService.list_audit_logs(db, limit=limit)


@router.post("/audit-logs", status_code=status.HTTP_201_CREATED)
def create_audit_log(
    payload: AuditLogCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> dict[str, str]:
    AuditService.write_log(
        db,
        user_id=current_user.id,
        action=payload.action,
        entity_type=payload.entity_type,
        entity_id=payload.entity_id,
    )
    return {"status": "ok"}


@router.get("/historical-sales", response_model=list[HistoricalSaleRead])
def list_historical_sales(
    limit: int = Query(default=500, ge=1, le=1000000),
    start_date: date | None = Query(default=None),
    end_date: date | None = Query(default=None),
    product_id: int | None = Query(default=None, ge=1),
    product_query: str | None = Query(default=None),
    supplier_query: str | None = Query(default=None),
    db: Session = Depends(get_db),
    _: User = Depends(require_permissions("Historical data")),
) -> list[HistoricalSaleRead]:
    return ReportService.list_historical_sales(
        db,
        limit=limit,
        start_date=start_date,
        end_date=end_date,
        product_id=product_id,
        product_query=product_query,
        supplier_query=supplier_query,
    )


@router.post("/historical-sales/import", response_model=CsvImportResult, status_code=status.HTTP_201_CREATED)
def import_historical_sales(
    payload: HistoricalSaleImportRequest,
    db: Session = Depends(get_db),
    _: User = Depends(require_permissions("Historical data")),
) -> CsvImportResult:
    result = ReportService.import_historical_sales(db, payload.items)
    return CsvImportResult(**result)