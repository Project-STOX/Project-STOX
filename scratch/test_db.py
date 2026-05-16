import sys
import os
from sqlalchemy import create_engine, text

# Add the project root to sys.path so we can import app modules
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from app.core.config import get_settings

def test_connectivity():
    settings = get_settings()
    print(f"--- SYSTEM DIAGNOSTIC ---")
    print(f"LOCAL_ONLY_MODE: {settings.local_only_mode}")
    print(f"LOCAL_DB_PORT: {settings.local_db_port}")
    print(f"LOCAL_DB_NAME: {settings.local_db_name}")
    
    local_db_url = f"postgresql+psycopg://{settings.local_db_user}:{settings.local_db_password}@localhost:{settings.local_db_port}/{settings.local_db_name}"
    
    print(f"\nTesting connection to: {local_db_url.split('@')[1]}") # Don't print password
    
    try:
        engine = create_engine(local_db_url, connect_args={"connect_timeout": 3})
        with engine.connect() as conn:
            result = conn.execute(text("SELECT current_database(), current_user"))
            db_name, user = result.fetchone()
            print(f"  SUCCESS: Connected to {db_name} as {user}")
    except Exception as e:
        print(f"   FAILURE: Could not reach local database.")
        print(f"   Error: {e}")
        print("\nPossible solutions:")
        print("1. Is your local PostgreSQL server running?")
        print("2. Is the password in .env correct?")
        print("3. Is the database name 'postgres' (Supabase default) or 'stox_db'?")

if __name__ == "__main__":
    test_connectivity()
