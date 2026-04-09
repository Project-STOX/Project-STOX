from decimal import Decimal
from sqlalchemy import Enum, ForeignKey, Integer, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.models.base import Base


class Product(Base):
    __tablename__ = "product"

    id: Mapped[int] = mapped_column("product_id", Integer, primary_key=True, index=True)
    product_code: Mapped[str] = mapped_column(String(50), unique=True, nullable=False, index=True)
    sku: Mapped[str] = mapped_column(String(50), unique=True, nullable=False, index=True)
    name: Mapped[str] = mapped_column("product_name", String(100), nullable=False, index=True)
    supplier_id: Mapped[int] = mapped_column(Integer, ForeignKey("supplier.supplier_id"), nullable=False, index=True)
    current_qty: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    reorder_level: Mapped[int] = mapped_column("reorder_point", Integer, default=0, nullable=False)
    unit_cost: Mapped[Decimal] = mapped_column(Numeric(12, 2), default=Decimal("0.00"), nullable=False)
    status_flag: Mapped[str | None] = mapped_column(
        Enum("Low Stock", "In Stock", "High Stock", "Discontinued", name="product_status"), 
        nullable=True, 
        index=True
    )
    serial_no: Mapped[int | None] = mapped_column(Integer, nullable=True)

    supplier: Mapped["Supplier"] = relationship("Supplier", back_populates="products")
    stock_receipts: Mapped["list[StockReceipt]"] = relationship("StockReceipt", back_populates="product")
    reorder_params: Mapped["ReorderParameter | None"] = relationship("ReorderParameter", back_populates="product", uselist=False)

    @property
    def overstock_level(self) -> int:
        return self.reorder_level

    @property
    def lead_time_days(self) -> int:
        return self.reorder_params.lead_time_days if self.reorder_params else 0
