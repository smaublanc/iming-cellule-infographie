@echo off
start "IMING preview server" /min powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0preview-local.ps1"
timeout /t 1 /nobreak >nul
start "" "http://localhost:8899/maquette/index.html"
