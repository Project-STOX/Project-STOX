"""
backup_service.py
-----------------
Handles PostgreSQL database backup via pg_dump and streaming progress events via SSE.
"""
from __future__ import annotations

import asyncio
import datetime
import json
import os
import re
import shutil
import subprocess
import threading
from pathlib import Path
from typing import AsyncIterator
from urllib.parse import urlparse

from app.core.config import get_settings

# Default backup directory (relative to project root, created on first use)
_BACKUP_DIR = Path("backups")

# Default config file (persisted locally)
_CONFIG_PATH = Path("backup_config.json")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _parse_dsn(database_url: str) -> dict[str, str]:
    """Extract connection components from the SQLAlchemy DATABASE_URL."""
    # Strip driver prefix (e.g. "postgresql+psycopg://..." -> "postgresql://...")
    clean = re.sub(r"^\w+\+\w+://", "postgresql://", database_url)
    parsed = urlparse(clean)
    return {
        "host": parsed.hostname or "localhost",
        "port": str(parsed.port or 5432),
        "user": parsed.username or "postgres",
        "password": parsed.password or "",
        "dbname": (parsed.path or "").lstrip("/") or "postgres",
    }


def _local_dsn() -> dict[str, str]:
    """Return connection details for the LOCAL (backup target) PostgreSQL instance."""
    settings = get_settings()
    return {
        "host": "localhost",
        "port": str(settings.local_db_port),
        "user": settings.local_db_user,
        "password": settings.local_db_password,
        "dbname": settings.local_db_name,
    }


def get_backup_dir() -> Path:
    """Return (and create if necessary) the backup storage directory."""
    _BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    return _BACKUP_DIR


def list_backups() -> list[dict]:
    """Return metadata for all backup dump files, newest first."""
    directory = get_backup_dir()
    files = sorted(directory.glob("*.dump"), key=lambda p: p.stat().st_mtime, reverse=True)
    result = []
    for f in files:
        stat = f.stat()
        result.append(
            {
                "filename": f.name,
                "size_bytes": stat.st_size,
                "created_at": datetime.datetime.fromtimestamp(stat.st_mtime).isoformat(),
            }
        )
    return result


def get_backup_config() -> dict:
    """Read the backup schedule config from disk."""
    if _CONFIG_PATH.exists():
        try:
            return json.loads(_CONFIG_PATH.read_text())
        except Exception:
            pass
    return {
        "schedule_enabled": False,
        "frequency": "Daily",
        "time": "02:00",
        "sync_local": False,
    }


def save_backup_config(config: dict) -> None:
    """Save the backup schedule config to disk."""
    _CONFIG_PATH.write_text(json.dumps(config, indent=2))


# ---------------------------------------------------------------------------
# SSE event emitter
# ---------------------------------------------------------------------------

def _sse(event: str, data: dict) -> str:
    return f"event: {event}\ndata: {json.dumps(data)}\n\n"


# ---------------------------------------------------------------------------
# Core backup runner (synchronous, meant to run inside a thread)
# ---------------------------------------------------------------------------

class BackupRunner:
    """
    Executes a pg_dump and writes progress events to a queue.
    The caller drains the queue via async iteration.
    """

    def __init__(self, sync_local: bool = False) -> None:
        # Thread-safe queue for SSE frames
        self._queue: asyncio.Queue[str | None] = asyncio.Queue()
        self._loop: asyncio.AbstractEventLoop | None = None
        self.sync_local = sync_local

    def _put(self, frame: str) -> None:
        """Thread-safe: schedule a put on the event loop."""
        if self._loop is not None:
            self._loop.call_soon_threadsafe(self._queue.put_nowait, frame)

    def _run_backup(self) -> None:
        """
        Blocking function that runs pg_dump and emits SSE events.
        Runs inside an executor thread so it doesn't block the event loop.
        """
        # Diagnostic check: Ensure binaries are available
        pg_dump = shutil.which("pg_dump")
        pg_restore = shutil.which("pg_restore")
        psql = shutil.which("psql")

        # Fallback for Windows common paths
        if os.name == "nt":
            common_paths: list[str] = []
            base_dir = Path(r"C:\Program Files\PostgreSQL")
            if base_dir.exists():
                version_bins = sorted(
                    (p / "bin" for p in base_dir.iterdir() if p.is_dir()),
                    reverse=True,
                )
                common_paths.extend(str(p) for p in version_bins)
            for p in common_paths:
                if not pg_dump and os.path.exists(os.path.join(p, "pg_dump.exe")):
                    pg_dump = os.path.join(p, "pg_dump.exe")
                if not pg_restore and os.path.exists(os.path.join(p, "pg_restore.exe")):
                    pg_restore = os.path.join(p, "pg_restore.exe")
                if not psql and os.path.exists(os.path.join(p, "psql.exe")):
                    psql = os.path.join(p, "psql.exe")

        if not pg_dump:
            self._put(_sse("error", {"message": "pg_dump not found. Please install PostgreSQL and ensure it's in your PATH or common install dirs.", "progress": 0}))
            self._put(None)
            return

        # Check versions for diagnostic purposes
        try:
            dump_v = subprocess.run([pg_dump, "--version"], capture_output=True, text=True, shell=False).stdout.strip()
            self._put(_sse("progress", {"message": f"Using {dump_v}", "progress": 5}))
        except Exception:
            pass

        settings = get_settings()
        src = _parse_dsn(settings.database_url)

        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        out_path = get_backup_dir() / f"stox_backup_{timestamp}.dump"

        self._put(_sse("start", {"message": "Backup started", "file": out_path.name, "progress": 0}))

        # Build pg_dump command
        env = os.environ.copy()
        env["PGPASSWORD"] = src["password"]

        # Supabase often requires SSL
        ssl_mode = "require" if ".supabase.co" in src["host"] else "prefer"

        cmd = [
            pg_dump,
            "-h", src["host"],
            "-p", src["port"],
            "-U", src["user"],
            "-d", src["dbname"],
            "--format=custom",        
            "--no-password",
            "-v",                     
            "-f", str(out_path),
        ]
        
        # Add sslmode if not already in URL (via env for standard libpq tools)
        env["PGSSLMODE"] = ssl_mode

        self._put(_sse("progress", {"message": "Exporting data from Supabase…", "progress": 10}))

        try:
            process = subprocess.Popen(
                cmd,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                shell=False,
            )

            dumped_tables: list[str] = []
            stderr_lines: list[str] = []
            # pg_dump --verbose writes table names to stderr
            assert process.stderr is not None
            for line in iter(process.stderr.readline, ""):
                line = line.strip()
                if not line:
                    continue
                stderr_lines.append(line)
                # Detect table dumps
                if "pg_dump:" in line.lower() and ("dumping" in line.lower() or "reading" in line.lower()):
                    # Extract table name for friendly messaging
                    table_match = re.search(r'table "([^"]+)"', line)
                    table_name = table_match.group(1) if table_match else "object"
                    dumped_tables.append(table_name)
                    progress = min(10 + int(len(dumped_tables) * 3), 90)
                    self._put(_sse("progress", {
                        "message": f"Dumping: {table_name}",
                        "progress": progress,
                    }))

            process.wait()

            if process.returncode != 0:
                stderr_out = "\n".join(stderr_lines[-20:])
                raise RuntimeError(f"pg_dump exited with code {process.returncode}. {stderr_out}")

            if not self.sync_local:
                size_mb = round(out_path.stat().st_size / (1024 * 1024), 2)
                self._put(_sse("progress", {"message": "Finalising backup…", "progress": 95}))
                self._put(_sse("done", {
                    "message": "Backup completed successfully",
                    "file": out_path.name,
                    "size_mb": size_mb,
                    "progress": 100,
                }))
            else:
                if not pg_restore:
                    self._put(_sse("error", {"message": "pg_restore not found. Skipping local sync.", "progress": 90}))
                    return

                # Restoration phase
                self._put(_sse("progress", {"message": "Dumping complete. Starting local sync…", "progress": 70}))
                target = _local_dsn()
                
                # Check/Create local DB if it doesn't exist
                # We do this via psql or dropdb/createdb if available
                self._ensure_local_db_exists(target, psql)

                # Terminate active connections to the local DB to allow restore
                self._terminate_local_connections(target, psql)

                # Command to restore into the local postgres
                restore_env = os.environ.copy()
                restore_env["PGPASSWORD"] = target["password"]
                restore_env["PGSSLMODE"] = "prefer"

                if target["dbname"].lower() == "postgres":
                    self._put(_sse("progress", {
                        "message": "Local target DB is 'postgres'. A dedicated DB (e.g. stox_db) is recommended for sync.",
                        "progress": 74,
                    }))
                
                restore_cmd = [
                    pg_restore,
                    "-h", target["host"],
                    "-p", target["port"],
                    "-U", target["user"],
                    "-d", target["dbname"],
                    "--clean",         # drop database objects before recreating
                    "--if-exists",
                    "--no-owner",      # ignore ownership errors (common when syncing from Supabase)
                    "--no-privileges", # ignore permission errors
                    "--no-password",
                    "-v",
                    str(out_path)
                ]
                
                self._put(_sse("progress", {"message": "Syncing to local PostgreSQL (localhost:5432)…", "progress": 75}))
                
                restore_proc = subprocess.Popen(
                    restore_cmd,
                    env=restore_env,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.PIPE,
                    text=True,
                    shell=False,
                )
                
                # Consume verbose restore output as it is produced.
                # Without reading stderr continuously, large restores can deadlock when the pipe buffer fills.
                restore_lines: list[str] = []
                restore_step = 0
                assert restore_proc.stderr is not None
                for line in iter(restore_proc.stderr.readline, ""):
                    line = line.strip()
                    if not line:
                        continue
                    restore_lines.append(line)
                    restore_step += 1
                    if restore_step % 15 == 0:
                        progress = min(76 + (restore_step // 15), 97)
                        short_line = line[:120]
                        self._put(_sse("progress", {
                            "message": f"Syncing local DB… {short_line}",
                            "progress": progress,
                        }))

                restore_proc.wait()
                
                if restore_proc.returncode != 0:
                    stderr_out = "\n".join(restore_lines[-20:])
                    # If this fails, we still have the dump file, but it's a sync error
                    # We report it clearly so the user knows why the local DB didn't update
                    self._put(_sse("progress", {"message": f"Local Sync Failed: {stderr_out[:250]}", "progress": 90}))
                    sync_success = False
                else:
                    self._put(_sse("progress", {"message": "Local sync completed", "progress": 98}))
                    sync_success = True
                
                size_mb = round(out_path.stat().st_size / (1024 * 1024), 2)
                self._put(_sse("done", {
                    "message": "Backup completed" + (" with Local Sync" if sync_success else " (Local Sync Failed)"),
                    "file": out_path.name,
                    "size_mb": size_mb,
                    "progress": 100,
                    "sync_ok": sync_success
                }))

        except Exception as exc:
            # Clean up partial dump file if it exists
            if 'out_path' in locals() and out_path.exists():
                try:
                    out_path.unlink()
                except OSError:
                    pass
            self._put(_sse("error", {"message": str(exc), "progress": 0}))
        finally:
            # Sentinel: stop the async iterator
            self._put(None)  # type: ignore[arg-type]

    def _ensure_local_db_exists(self, target: dict[str, str], psql_path: str | None) -> None:
        """Attempts to create the local database if it does not exist."""
        if not psql_path:
            return

        # Use 'postgres' DB to run 'CREATE DATABASE'
        env = os.environ.copy()
        env["PGPASSWORD"] = target["password"]
        env["PGSSLMODE"] = "prefer"
        
        cmd = [
            psql_path,
            "-h", target["host"],
            "-p", target["port"],
            "-U", target["user"],
            "-d", "postgres",
            "-tc", f"SELECT 1 FROM pg_database WHERE datname = '{target['dbname']}'"
        ]
        
        try:
            res = subprocess.run(cmd, env=env, capture_output=True, text=True, shell=False)
            if "1" not in res.stdout:
                # DB doesn't exist, create it
                create_cmd = [
                    psql_path,
                    "-h", target["host"],
                    "-p", target["port"],
                    "-U", target["user"],
                    "-d", "postgres",
                    "-c", f"CREATE DATABASE {target['dbname']}"
                ]
                subprocess.run(create_cmd, env=env, capture_output=True, shell=False)
        except Exception:
            pass

    def _terminate_local_connections(self, target: dict[str, str], psql_path: str | None) -> None:
        """Kicks out other users from the local DB so pg_restore can --clean it."""
        if not psql_path:
            return

        env = os.environ.copy()
        env["PGPASSWORD"] = target["password"]
        env["PGSSLMODE"] = "prefer"
        
        # SQL to terminate all other backends for the target database
        sql = (
            f"SELECT pg_terminate_backend(pid) "
            f"FROM pg_stat_activity "
            f"WHERE datname = '{target['dbname']}' "
            f"AND pid <> pg_backend_pid()"
        )
        
        cmd = [
            psql_path,
            "-h", target["host"],
            "-p", target["port"],
            "-U", target["user"],
            "-d", "postgres",
            "-c", sql
        ]
        
        try:
            # We don't check for failure here; if it fails, pg_restore might still work or will fail with its own error
            subprocess.run(cmd, env=env, capture_output=True, shell=False)
        except Exception:
            pass

    async def run(self) -> AsyncIterator[str]:
        """
        Async generator that yields SSE frames while the backup runs in a thread.
        """
        self._loop = asyncio.get_running_loop()
        # Start blocking work in a thread pool
        thread = threading.Thread(target=self._run_backup, daemon=True)
        thread.start()

        while True:
            frame = await self._queue.get()
            if frame is None:
                break
            yield frame

        thread.join(timeout=5)
