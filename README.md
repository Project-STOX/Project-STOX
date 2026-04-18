# project_stox

Flutter frontend with FastAPI backend and PostgreSQL database.

## Workspace Setup Status

- Flutter dependencies installed with `flutter pub get`.
- VS Code task created at `.vscode/tasks.json`:
	- `Flutter Analyze` -> runs `flutter analyze .`
- `copilot-instructions.md` checklist tracked at `.github/copilot-instructions.md`.

## Run and Debug

1. Install Flutter SDK and platform toolchains (Android/iOS/Web/Desktop as needed).
2. Configure backend environment in `.env`.
3. Start PostgreSQL (local or Supabase remote).
4. Start FastAPI backend from workspace root:

```bash
./.venv/Scripts/python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

5. Verify backend health:

```bash
curl http://localhost:8000/health
```

6. Run Flutter (web) with API base URL:

```bash
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000/api/v1
```

7. For static diagnostics, run:

```bash
flutter analyze .
```

## Supabase Remote Database Configuration

Use FastAPI environment variable `DATABASE_URL` to connect to Supabase Postgres:

```env
DATABASE_URL=postgresql+psycopg://postgres:YOUR_PASSWORD@db.odowtpnnkxgdbmtnqphr.supabase.co:5432/postgres?sslmode=require
```

Notes:
- `sslmode=require` is required for Supabase direct DB connections.
- Do not expose database credentials or service role secrets in Flutter.
- Flutter should call FastAPI endpoints only.

## Supabase CLI

```bash
supabase login
supabase init
supabase link --project-ref odowtpnnkxgdbmtnqphr
```

## Database Backup & Failover

STOX includes automatic failover to a local PostgreSQL database if Supabase becomes unavailable. Your local database is **read-only** to prevent accidental data modifications during failover.

### Quick Setup

1. **Check backup status:**
   ```powershell
   .\scripts\check_backup_status.ps1
   ```

2. **Restore latest backup:**
   ```powershell
   # Easy: Double-click this
   .\scripts\restore_latest.bat
   
   # Or PowerShell:
   .\scripts\restore_backup.ps1 -BackupFile ".\backups\latest.sql"
   ```

3. **Done!** Your app will auto-failover when Supabase is down.

### How It Works

- **Primary:** Supabase remote database (live)
- **Fallback:** Local PostgreSQL on `localhost:5432` (read-only)
- **Auto-failover:** FastAPI automatically switches to local if Supabase is down
- **Data consistency:** Local database is a read-only replica for data integrity

### Create Fresh Backup

```powershell
python main.py --backup
# or via script
.\scripts\backup_database.ps1
```

#### Scripts Documentation

See [`scripts/README.md`](./scripts/README.md) for detailed usage of:
- `restore_backup.ps1` - Full restore with role setup
- `check_backup_status.ps1` - Diagnostic health check
- `restore_latest.bat` - One-click Windows launcher

## Existing VS Code Tasks

Use these tasks from `.vscode/tasks.json`:
- Start FastAPI Backend
- Run Flutter Web (API)
- Flutter Analyze

```bash
flutter run --dart-define=SUPABASE_URL=<your_url> --dart-define=SUPABASE_ANON_KEY=<your_anon_key>
```

If no defines are passed, the current code includes fallback development defaults.
