@echo off
echo ========================================
echo   DD-CLASS 后端服务启动中...
echo ========================================
cd /d "%~dp0"
python -m uvicorn app.main:app --host 0.0.0.0 --port 8001
pause
