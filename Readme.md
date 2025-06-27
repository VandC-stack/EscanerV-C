@echo off
chcp 65001 >nul
title Instalador de Librerías - Escáner de Códigos V&C

echo.
echo ============================================================
echo    🔧 INSTALADOR DE LIBRERÍAS - ESCÁNER DE CÓDIGOS V&C
echo ============================================================
echo.

echo 📋 Verificando Python...
python --version >nul 2>&1
if errorlevel 1 (
    echo ❌ ERROR: Python no está instalado o no está en el PATH
    echo.
    echo 💡 Soluciones:
    echo    1. Instala Python desde https://python.org
    echo    2. Asegúrate de marcar "Add Python to PATH" durante la instalación
    echo    3. Reinicia esta ventana después de instalar Python
    echo.
    pause
    exit /b 1
)

echo ✅ Python encontrado
echo.

echo 📦 Actualizando pip...
python -m pip install --upgrade pip

echo.
echo 🚀 Ejecutando instalador de librerías...
echo.

python install_libraries.py

echo.
echo ============================================================
echo    📋 INSTALACIÓN COMPLETADA
echo ============================================================
echo.
echo 💡 Si hubo errores, intenta:
echo    1. Ejecutar como administrador
echo    2. Verificar conexión a internet
echo    3. Actualizar Python
echo.
pause 
