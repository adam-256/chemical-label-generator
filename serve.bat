@echo off
cd /d "%~dp0"
start /b cmd /c "timeout /t 2 /nobreak >nul & start http://localhost:8080/index.html"
python -m http.server 8080
