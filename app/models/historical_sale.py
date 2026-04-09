from datetime import date
from decimal import Decimal

from sqlalchemy import Date, ForeignKey, Integer, Numeric, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class HistoricalSale(Base):
    __tablename__ = "historical_sales"
    __table_args__ = (UniqueConstraint("product_id", "sale_date", name="uq_historical_sales_product_date"),)

    id: Mapped[int] = mapped_column("sale_id", Integer, primary_key=True, index=True)
    product_id: Mapped[int] = mapped_column(Integer, ForeignKey("product.product_id"), nullable=False, index=True)
    sale_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    quantity_sold: Mapped[int] = mapped_column(Integer, nullable=False)
    revenue: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)

    product: Mapped["Product"] = relationship("Product")
