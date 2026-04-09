from datetime import datetime
from decimal import Decimal

from sqlalchemy import DateTime, ForeignKey, Integer, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class StockReceipt(Base):
    __tablename__ = "stock_receipt"

    id: Mapped[int] = mapped_column("receipt_id", Integer, primary_key=True, index=True)
    product_id: Mapped[int] = mapped_column(Integer, ForeignKey("product.product_id"), nullable=False, index=True)
    supplier_id: Mapped[int] = mapped_column(Integer, ForeignKey("supplier.supplier_id"), nullable=False, index=True)
    recorded_by: Mapped[int] = mapped_column(Integer, ForeignKey("user.user_id", ondelete="CASCADE"), nullable=False, index=True)
    quantity: Mapped[int] = mapped_column("quantity_received", Integer, nullable=False)
    quantity_damaged: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    received_at: Mapped[datetime] = mapped_column("receipt_date", DateTime(timezone=False), server_default=func.now(), nullable=False)
    reference_no: Mapped[str | None] = mapped_column("notes", Text, nullable=True)

    product: Mapped["Product"] = relationship("Product", back_populates="stock_receipts")
    supplier: Mapped["Supplier"] = relationship("Supplier", back_populates="stock_receipts")
    user: Mapped["User"] = relationship("User")

    @property
    def unit_cost(self) -> Decimal:
        return Decimal("0.00")

    @property
    def recorded_by_username(self) -> str | None:
        return self.user.full_name if self.user else None
