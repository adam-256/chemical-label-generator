@echo off
cd /d "%~dp0"
python --version >nul 2>&1
if %errorlevel% == 0 (
    start /b cmd /c "timeout /t 2 /nobreak >nul & start http://localhost:8080/index.html"
    python -m http.server 8080
) else (
    start index.html
)
