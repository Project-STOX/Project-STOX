import os
from datetime import datetime
from sqlalchemy.orm import Session
from app.services.audit_service import AuditService

class FeedbackService:
    @staticmethod
    # Save user feedback to local log file and audit log in database
    def save_feedback(
        db: Session,
        user_id: int,
        username: str,
        email: str,
        category: str,
        message: str
    ) -> None:
        """
        Saves user feedback to a local log file and records an entry in the Audit Log.
        """
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_entry = f"[{timestamp}] User: {username} ({email}) | Category: {category} | Message: {message}\n"
        
        # 1. Save to local log file
        log_dir = "logs"
        log_path = os.path.join(log_dir, "feedback.log")
        
        try:
            if not os.path.exists(log_dir):
                os.makedirs(log_dir)
                
            with open(log_path, "a", encoding="utf-8") as f:
                f.write(log_entry)
        except Exception as e:
            # We don't want to crash the request if file writing fails, 
            # but we should log it.
            print(f"Failed to write to feedback.log: {e}")

        # 2. Save to Database (Audit Log)
        # This acts as the "Saved on Supabase" part since Audit Log is in the DB.
        AuditService.write_log(
            db,
            user_id=user_id,
            action=f"User Feedback [{category}]: {message}",
            entity_type="feedback",
            entity_id=0
        )
