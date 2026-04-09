from sqlalchemy import ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class Supplier(Base):
    __tablename__ = "supplier"

    id: Mapped[int] = mapped_column("supplier_id", Integer, primary_key=True, index=True)
    name: Mapped[str] = mapped_column("supplier_name", String(100), unique=True, nullable=False, index=True)
    contact_info: Mapped[str | None] = mapped_column(String(150), nullable=True)
    lead_time_days: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    address: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_by: Mapped[int] = mapped_column(Integer, ForeignKey("user.user_id"), nullable=False, index=True)

    products: Mapped[list["Product"]] = relationship("Product", back_populates="supplier")
    stock_receipts: Mapped[list["StockReceipt"]] = relationship("StockReceipt", back_populates="supplier")

    @property
    def email(self) -> str | None:
        value = (self.contact_info or "").strip()
        return value if "@" in value else None

    @property
    def phone(self) -> str | None:
        value = (self.contact_info or "").strip()
        return value if value and "@" not in value else None

    @property
    def is_active(self) -> bool:
        return True
