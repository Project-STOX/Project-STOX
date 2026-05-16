@echo off
TITLE STOX Backend Server
echo ---------------------------------------------------
echo STOX Inventory Intelligence - Local Backend
echo ---------------------------------------------------
echo.

:: Navigate to the script's directory
cd /d %~dp0

:: Check if venv exists
if not exist "venv\Scripts\activate.bat" (
    echo [ERROR] Virtual environment not found. Please ensure 'venv' folder exists.
    pause
    exit /b
)

echo [1/2] Activating Virtual Environment...
call venv\Scripts\activate.bat

echo [2/2] Starting Uvicorn Server on http://localhost:8000...
echo (The window will stay open to show logs)
echo.

python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload

echo.
echo Server stopped.
pause
