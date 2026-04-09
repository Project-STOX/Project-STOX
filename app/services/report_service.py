from decimal import Decimal

from datetime import date

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.audit_log import AuditLog
from app.models.historical_sale import HistoricalSale
from app.models.product import Product
from app.models.supplier import Supplier
from app.models.user import User
from app.schemas.reports import AuditLogRead, HistoricalSaleImportRow, HistoricalSaleRead


class ReportService:
    @staticmethod
    def list_audit_logs(db: Session, limit: int = 500) -> list[AuditLogRead]:
        rows = db.execute(
            select(AuditLog, User.full_name)
            .select_from(AuditLog)
            .outerjoin(User, User.id == AuditLog.user_id)
            .order_by(AuditLog.timestamp.desc())
            .limit(limit)
        ).all()

        return [
            AuditLogRead(
                log_id=log.id,
                user_id=log.user_id if (log.user_id is not None and log.user_id > 0) else None,
                username=username,
                action=log.action,
                entity_type=log.entity_type,
                entity_id=log.entity_id if (log.entity_id is not None and log.entity_id > 0) else None,
                details=None,
                occurred_at=log.timestamp,
            )
            for log, username in rows
        ]

    @staticmethod
    def list_historical_sales(
        db: Session,
        *,
        limit: int = 500,
        start_date: date | None = None,
        end_date: date | None = None,
        product_id: int | None = None,
        product_query: str | None = None,
        supplier_query: str | None = None,
    ) -> list[HistoricalSaleRead]:
        stmt = (
            select(HistoricalSale, Product, Supplier)
            .join(Product, Product.id == HistoricalSale.product_id)
            .join(Supplier, Supplier.id == Product.supplier_id)
            .order_by(HistoricalSale.sale_date.desc(), HistoricalSale.id.desc())
        )
        if product_id is not None:
            stmt = stmt.where(HistoricalSale.product_id == product_id)
        if start_date is not None:
            stmt = stmt.where(HistoricalSale.sale_date >= start_date)
        if end_date is not None:
            stmt = stmt.where(HistoricalSale.sale_date <= end_date)
        if product_query:
            stmt = stmt.where(Product.name.ilike(f"%{product_query}%") | Product.product_code.ilike(f"%{product_query}%") | Product.sku.ilike(f"%{product_query}%"))
        if supplier_query:
            stmt = stmt.where(Supplier.name.ilike(f"%{supplier_query}%"))

        rows = db.execute(stmt.limit(limit)).all()
        return [
            HistoricalSaleRead(
                sale_id=sale.id,
                product_id=sale.product_id,
                sale_date=sale.sale_date,
                quantity_sold=sale.quantity_sold,
                revenue=Decimal(str(sale.revenue or Decimal("0.00"))),
                product={
                    "product_name": product.name,
                    "product_code": product.product_code,
                    "supplier": {"supplier_name": supplier.name},
                },
            )
            for sale, product, supplier in rows
        ]

    @staticmethod
    def import_historical_sales(db: Session, rows: list[HistoricalSaleImportRow]) -> dict[str, object]:
        inserted = 0
        rejected = []

        for index, row in enumerate(rows, start=1):
            product = db.scalar(select(Product).where(Product.product_code == row.product_code))
            if product is None:
                rejected.append({"row_number": index, "reason": f"Product code {row.product_code} not found"})
                continue

            existing = db.scalar(
                select(HistoricalSale).where(
                    HistoricalSale.product_id == product.id,
                    HistoricalSale.sale_date == row.sale_date,
                )
            )
            if existing is not None:
                rejected.append({"row_number": index, "reason": "Duplicate product/date combination"})
                continue

            quantity_sold = int(row.quantity_sold)
            revenue = Decimal(str(row.revenue))
            db.add(
                HistoricalSale(
                    product_id=product.id,
                    sale_date=row.sale_date,
                    quantity_sold=quantity_sold,
                    revenue=revenue,
                )
            )
            inserted += 1

        db.commit()
        return {
            "inserted_rows": inserted,
            "rejected_rows": len(rejected),
            "errors": rejected,
        }