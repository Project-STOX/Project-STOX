from sqlalchemy import ForeignKey, Integer, Numeric
from sqlalchemy.orm import Mapped, mapped_column, relationship
from decimal import Decimal

from app.models.base import Base

class ReorderParameter(Base):
    __tablename__ = "reorder_parameter"

    id: Mapped[int] = mapped_column("param_id", Integer, primary_key=True, index=True)
    product_id: Mapped[int] = mapped_column(Integer, ForeignKey("product.product_id"), nullable=False, unique=True, index=True)
    configured_by: Mapped[int] = mapped_column(Integer, ForeignKey("user.user_id"), nullable=False, index=True)
    safety_stock: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    eoq: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    lead_time_days: Mapped[int | None] = mapped_column(Integer, nullable=True)

    product: Mapped["Product"] = relationship("Product", back_populates="reorder_params")
    user: Mapped["User"] = relationship("User")
