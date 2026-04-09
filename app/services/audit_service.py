from datetime import UTC, datetime

from sqlalchemy.orm import Session

from app.models.audit_log import AuditLog


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
            
        log = AuditLog(
            user_id=user_id,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id or 0,
            timestamp=datetime.now(UTC).replace(tzinfo=None),
        )
        db.add(log)
        db.commit()
