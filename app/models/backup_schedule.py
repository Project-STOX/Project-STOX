"""
backup_schedule.py
------------------
Stores SME Owner's scheduled export backup configurations.
"""
from __future__ import annotations

import json
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class BackupSchedule(Base):
    __tablename__ = "backup_schedule"

    id: Mapped[int] = mapped_column("schedule_id", Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(Integer, ForeignKey("user.user_id", ondelete="CASCADE"), nullable=False, index=True)
    label: Mapped[str] = mapped_column(String(100), nullable=False)
    categories_json: Mapped[str] = mapped_column("categories", Text, nullable=False)  # JSON array of strings
    frequency: Mapped[str] = mapped_column(String(20), nullable=False)  # daily | weekly | monthly | yearly
    scheduled_time: Mapped[str] = mapped_column(String(5), nullable=False, default="02:00")  # HH:MM
    day_of_week: Mapped[int | None] = mapped_column(Integer, nullable=True)   # 0=Mon … 6=Sun, for weekly
    day_of_month: Mapped[int | None] = mapped_column(Integer, nullable=True)  # 1-31, for monthly/yearly
    month: Mapped[int | None] = mapped_column(Integer, nullable=True)          # 1-12, for yearly
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    last_run_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    next_run_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    @property
    def categories(self) -> list[str]:
        try:
            return json.loads(self.categories_json)
        except Exception:
            return []

    @categories.setter
    def categories(self, value: list[str]) -> None:
        self.categories_json = json.dumps(value)
