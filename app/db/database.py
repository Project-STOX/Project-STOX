from collections.abc import Generator
from typing import Any

from sqlalchemy import create_engine, text as txt
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import get_settings

settings = get_settings()

database_url = settings.database_url
if database_url.startswith("postgresql://"):
    database_url = database_url.replace("postgresql://", "postgresql+psycopg://", 1)

engine_kwargs: dict[str, Any] = {
    "echo": settings.debug, 
    "future": True,
    "pool_size": 20,
    "max_overflow": 40,
    "pool_pre_ping": True,
}
if database_url.startswith("postgresql"):
    engine_kwargs["connect_args"] = {"connect_timeout": settings.db_connect_timeout_seconds}

engine = create_engine(database_url, **engine_kwargs)
SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False, class_=Session)

# ── Local Failover Engine (Read-Only) ───────────────────────────────────
# Connection for local failover (localhost:5432, user: postgres)
# We use the same 'stox_db' name as configured in the backup service
local_db_url = f"postgresql+psycopg://{settings.local_db_user}:{settings.local_db_password}@localhost:{settings.local_db_port}/{settings.local_db_name}"
local_engine = create_engine(local_db_url, echo=settings.debug, pool_pre_ping=True)
LocalSession = sessionmaker(bind=local_engine, autocommit=False, autoflush=False, class_=Session)


def get_db() -> Generator[Session, None, None]:
    """
    Dependency to get a database session.
    Automatically falls back to local PostgreSQL in READ-ONLY mode if primary is down.
    """
    db: Session | None = None
    is_fallback = False

    try:
        # 1. Try Primary (Supabase)
        try:
            db = SessionLocal()
            db.execute(txt("SELECT 1"))
        except Exception:
            # 2. Try Fallback (Local)
            if db:
                db.close()
            db = LocalSession()
            db.execute(txt("SET SESSION CHARACTERISTICS AS TRANSACTION READ ONLY"))
            is_fallback = True
        
        # 3. Yield the established session
        yield db

    finally:
        if db:
            db.close()
