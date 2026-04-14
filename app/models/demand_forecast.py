from datetime import datetime
from decimal import Decimal

from sqlalchemy import DateTime, ForeignKey, Integer, Numeric, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class DemandForecast(Base):
    __tablename__ = "demand_forecast"

    id: Mapped[int] = mapped_column("forecast_id", Integer, primary_key=True, index=True)
    product_id: Mapped[int] = mapped_column(Integer, ForeignKey("product.product_id"), nullable=False, index=True)
    method: Mapped[str] = mapped_column("model_by", String(20), nullable=False, index=True)
    window_days: Mapped[str] = mapped_column("forecast_window", String(20), nullable=False, index=True)
    predicted_qty: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False)
    reorder_suggestion: Mapped[int | None] = mapped_column(Integer, nullable=True)
    generated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    product: Mapped["Product"] = relationship("Product", back_populates="forecasts")
