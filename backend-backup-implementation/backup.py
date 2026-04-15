import os
import sys
import time
import subprocess
import logging
from datetime import datetime
from pathlib import Path
from dotenv import load_dotenv
import schedule

load_dotenv()

SUPABASE_URL = os.getenv('SUPABASE_URL')
LOCAL_DB_URL = os.getenv('LOCAL_DB_URL')
BACKUP_DIR = os.getenv('BACKUP_DIR', './full_backup')

def ensure_backup_dir():
    Path(BACKUP_DIR).mkdir(parents=True, exist_ok=True)
    
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s [%(levelname)s] - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S',
        handlers=[
            logging.FileHandler(f"{BACKUP_DIR}/backup_history.log", encoding='utf-8'),
            logging.StreamHandler(sys.stdout)
        ]
    )

def wait_for_db(max_retries=60):
    """Wait for local database to be ready"""
    logging.info("Waiting... local database is not ready.")
    for attempt in range(max_retries):
        try:
            result = subprocess.run(
                ["psql", LOCAL_DB_URL, "-c", "SELECT 1"],
                capture_output=True,
                timeout=5
            )
            if result.returncode == 0:
                logging.info("Local database is ready")
                return True
            else:
                logging.error(f"DEBUG Error: {result.stderr.decode()}")
        except Exception as e:
            logging.error(f"DEBUG Exception: {e}")
        
        logging.info(f"  Attempt {attempt + 1}/{max_retries}...")
        time.sleep(1)
    
    logging.error("Local database failed to start")
    return False

def rotate_backups():
    """Deletes old files to prevent TB of data (GFS Policy)"""
    logging.info("Running rotation, cleaning old files...")
    now = time.time()
    
    for arch_file in Path(BACKUP_DIR).glob("*.sql"):
        age_days = (now - arch_file.stat().st_mtime) / 86400
        name = arch_file.name
        
        # 1. Delete Hourly older than 3 days
        if name.startswith("hourly_") and age_days > 3:
            arch_file.unlink()
            logging.info(f"Deleted old backup: {name}")
        # 2. Delete Daily older than 31 days
        elif name.startswith("daily_") and age_days > 31:
            arch_file.unlink()
            logging.info(f"Deleted old backup: {name}")
        # 3. Delete Weekly older than 56 days (8 weeks)
        elif name.startswith("weekly_") and age_days > 56:
            arch_file.unlink()
            logging.info(f"Deleted old backup: {name}")
        # 4. Delete Monthly older than 90 days
        elif name.startswith("monthly_") and age_days > 90:
            arch_file.unlink()
            logging.info(f"Deleted old backup: {name}")

def backup_database(prefix="hourly"):
    now = datetime.now()
    timestamp = now.strftime("%Y%m%d_%H%M%S")
    backup_file = f"{BACKUP_DIR}/{prefix}_{timestamp}.sql"
    
    logging.info(f"--- Starting backup from Supabase ({prefix}) ---")
    
    try:
        # Dump Supabase database
        logging.info(f"Dumping Supabase database to {Path(backup_file).name}...")
        dump_result = subprocess.run(
            ["pg_dump", SUPABASE_URL],
            capture_output=True,
            timeout=300
        )
        
        if dump_result.returncode != 0:
            logging.error(f"Dump failed: {dump_result.stderr.decode()}")
            return False
        
        # Write dump bytes to file explicitly (avoids shell redirect bug)
        Path(backup_file).write_bytes(dump_result.stdout)
        file_size = os.path.getsize(backup_file) / (1024 * 1024)
        logging.info(f"Backup created: {Path(backup_file).name} ({file_size:.2f} MB)")
        
        # Restore to local database
        logging.info("Restoring to local database...")
        restore_result = subprocess.run(
            ["psql", LOCAL_DB_URL],
            input=dump_result.stdout,
            capture_output=True,
            timeout=300
        )
        
        if restore_result.returncode != 0:
            logging.error(f"Restore failed: {restore_result.stderr.decode()}")
            return False
        
        logging.info("Database restored to local instance")
        rotate_backups()
        logging.info("Backup workflow completed successfully.\n")
        return True
        
    except subprocess.TimeoutExpired:
        logging.error("Backup operation timed out\n")
        return False
    except Exception as e:
        logging.error(f"Backup failed: {e}\n")
        return False

def main():
    ensure_backup_dir()
    
    logging.info("=" * 60)
    logging.info("SUPABASE BACKUP SERVICE INITIALIZED")
    logging.info("=" * 60)
    logging.info(f"Supabase URL: {SUPABASE_URL[:50]}...")
    logging.info(f"Local DB URL: {LOCAL_DB_URL}")
    logging.info(f"Backup Directory: {BACKUP_DIR}")
    logging.info("=" * 60)
    
    # Wait for database to be ready
    if not wait_for_db():
        sys.exit(1)
    
    # Initial run (always an hourly 'Son' backup as a quick test)
    if not backup_database("hourly"):
        logging.warning("Initial backup failed, retrying in 30 seconds...")
        time.sleep(30)
        backup_database("hourly")
    
    def run_midnight_job():
        # Escalates hierarchically: Monthly (1st) -> Weekly (Sun) -> Daily
        now = datetime.now()
        if now.day == 1:
            backup_database("monthly")
        elif now.weekday() == 6:
            backup_database("weekly")
        else:
            backup_database("daily")
            
    # Set up fixed predictable CRON schedules
    schedule.every().day.at("04:00").do(backup_database, "hourly")
    schedule.every().day.at("08:00").do(backup_database, "hourly")
    schedule.every().day.at("12:00").do(backup_database, "hourly")
    schedule.every().day.at("16:00").do(backup_database, "hourly")
    schedule.every().day.at("20:00").do(backup_database, "hourly")
    
    # Midnight dynamically runs the Father / Grandfather job
    schedule.every().day.at("00:00").do(run_midnight_job)

    logging.info("GFS Backup started reliably on UTC Cron Schedule.")
    logging.info("Schedules: 00:00 (Monthly/Weekly/Daily hierarchy), 04:00, 08:00, 12:00, 16:00, 20:00 (Hourly)")
    
    while True:
        schedule.run_pending()
        time.sleep(1)

if __name__ == '__main__':
    main()
