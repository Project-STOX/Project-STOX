from app.db.database import engine
from sqlalchemy import text

def fix_audit_log():
    with engine.connect() as conn:
        print("Dropping NOT NULL constraint from audit_log.user_id...")
        conn.execute(text("ALTER TABLE audit_log ALTER COLUMN user_id DROP NOT NULL"))
        conn.commit()
        print("Success!")

if __name__ == "__main__":
    fix_audit_log()
