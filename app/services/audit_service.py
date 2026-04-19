from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.models.audit_log import AuditLog

# Define Indian Standard Time (IST) offset: UTC +5:30
IST = timezone(timedelta(hours=5, minutes=30))


class AuditService:
    @staticmethod
    def write_log(
        db: Session,
        *,
        user_id: int | None,
        action: str,
        entity_type: str,
        entity_id: int | None,
    ) -> None:
        if user_id is None:
            return
            
        from app.db.database import is_failover_active
        if is_failover_active():
            print(f"INFO: Skipping audit log '{action}' in failover mode.")
            return

        log = AuditLog(
            user_id=user_id,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id or 0,
            timestamp=datetime.now(IST).replace(tzinfo=None),
        )
        db.add(log)
        db.commit()
