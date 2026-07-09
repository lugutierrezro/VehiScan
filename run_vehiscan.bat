@echo off
title VehiScan Smart System Launcher
color 0A
cls
echo =======================================================================
echo               __      __    _     _  _____                     
echo               \ \    / /   (_)   (_)/ ____|                    
echo                \ \  / /___  _    _| |  __  __ _ _ __   ___ _ __ 
echo                 \ \/ / _ \| |  | | | |_ \/ _` | '_ \ / _ \ '__|
echo                  \  /  __/ | |  | | |__| | (_| | | | |  __/ |   
echo                   \/ \___|_|___|_|\_____|\__,_|_| |_|\___|_|   
echo                                                                        
echo =======================================================================
echo   Bienvenido al Sistema Inteligente de Lectura de Placas ALPR (VehiScan)
echo =======================================================================
echo.

:: Verificar si Docker esta instalado y ejecutandose
echo [1/4] Verificando requisitos del sistema (Docker)...
docker --version >nul 2>&1
if %errorlevel% neq 0 (
    color 0C
    echo [ERROR] Docker no esta instalado o no se encuentra en el PATH.
    echo Por favor, instale Docker Desktop desde: https://www.docker.com/products/docker-desktop
    echo.
    pause
    exit /b 1
)

docker info >nul 2>&1
if %errorlevel% neq 0 (
    color 0C
    echo [ERROR] El servicio de Docker no esta ejecutandose o no se ha iniciado.
    echo Por favor, inicie Docker Desktop y vuelva a intentar.
    echo.
    pause
    exit /b 1
)
echo [OK] Docker se encuentra instalado y ejecutandose.
echo.

:: Levantar contenedores mediante Docker Compose
echo [2/4] Construyendo y levantando contenedores (Base de datos y Backend)...
echo Esto puede tomar unos minutos la primera vez...
docker-compose up --build -d

if %errorlevel% neq 0 (
    color 0C
    echo [ERROR] Hubo un problema al levantar los contenedores de Docker.
    echo Verifique los mensajes anteriores para mas informacion.
    echo.
    pause
    exit /b 1
)
echo [OK] Contenedores montados e iniciados correctamente en segundo plano.
echo.

:: Esperar a que el servidor este listo
echo [3/4] Esperando a que el servidor web este listo (15 segundos)...
timeout /t 15 /nobreak >nul
echo.

:: Abrir navegador en localhost:4000
echo [4/4] Abriendo VehiScan en su navegador web predeterminado...
start http://localhost:4000

echo.
echo =======================================================================
echo   El sistema se esta ejecutando en: http://localhost:4000
echo   Para detener los contenedores y el servicio, ejecute:
echo   docker-compose down
echo =======================================================================
echo.
pause
