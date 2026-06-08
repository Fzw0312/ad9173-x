@echo off
setlocal
cd /d "%~dp0"

if exist ".venv\Scripts\python.exe" (
    ".venv\Scripts\python.exe" "%~dp0run_host_app.py"
) else (
    python "%~dp0run_host_app.py"
)
