from collections.abc import Generator
import time
from typing import Any

from sqlalchemy import create_engine, text as txt
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import get_settings

settings = get_settings()

# ── Primary Engine (Supabase) ─────────────────────────────────────────────────
database_url = settings.database_url
if database_url.startswith("postgresql://"):
    database_url = database_url.replace("postgresql://", "postgresql+psycopg://", 1)

_timeout = settings.db_connect_timeout_seconds  # default: 5 s

engine_kwargs: dict[str, Any] = {
    "echo": settings.debug,
    "future": True,
    "pool_size": 10,
    "max_overflow": 20,
    "pool_pre_ping": True,
    "connect_args": {"connect_timeout": _timeout},
}
engine = create_engine(database_url, **engine_kwargs)
SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False, class_=Session)

# ── Local Failover Engine (Read-Only) ─────────────────────────────────────────
local_db_url = (
    f"postgresql+psycopg://{settings.local_db_user}:{settings.local_db_password}"
    f"@localhost:{settings.local_db_port}/{settings.local_db_name}"
)
local_engine = create_engine(
    local_db_url,
    echo=settings.debug,
    pool_pre_ping=True,
    connect_args={"connect_timeout": 5},
)
LocalSession = sessionmaker(bind=local_engine, autocommit=False, autoflush=False, class_=Session)

# ── Failover State (Simple Cache) ─────────────────────────────────────────────
_failover_active: bool = False
_last_check_time: float = 0.0
_CHECK_INTERVAL = 60.0  # Check Supabase status at most once per minute


def is_failover_active() -> bool:
    """Returns True if the system is currently in local failover mode."""
    return _failover_active


def is_db_fallback_active() -> bool:
    """
    Checks if we should be in failover mode.
    Uses a simple timestamp-based cache to avoid excessive probing.
    """
    global _failover_active, _last_check_time
    now = time.time()
    
    # If the cache is still fresh, return the last known state
    if now - _last_check_time < _CHECK_INTERVAL:
        return _failover_active

    # Otherwise, try a lightweight probe
    try:
        # Use a temporary connection with very short timeout
        with engine.connect() as conn:
            conn.execute(txt("SELECT 1"))
        _failover_active = False
        print("INFO: Supabase is online.")
    except Exception as e:
        _failover_active = True
        print(f"INFO: Supabase unreachable, using local failover. Error: {e}")
    
    _last_check_time = now
    return _failover_active


def _set_read_only(db: Session) -> None:
    """Mark the session as read-only at the transaction level."""
    try:
        print("DEBUG: Marking database session as READ ONLY")
        db.execute(txt("SET SESSION CHARACTERISTICS AS TRANSACTION READ ONLY"))
    except Exception as e:
        print(f"DEBUG: Failed to set READ ONLY mode: {e}")
        pass


def get_db() -> Generator[Session, None, None]:
    """
    Yields a database session, falling back to local PostgreSQL if primary is down.
    """
    db: Session | None = None
    try:
        if settings.local_only_mode:
            db = LocalSession()
            _set_read_only(db)
            yield db
            return

        # Check for failover
        if is_db_fallback_active():
            db = LocalSession()
            _set_read_only(db)
        else:
            db = SessionLocal()
        
        yield db

    except Exception as e:
        # If the yielded session fails, we might want to force a re-check next time
        global _last_check_time
        _last_check_time = 0 
        raise e
    finally:
        if db:
            db.close()


