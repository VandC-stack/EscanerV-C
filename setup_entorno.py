#!/usr/bin/env python3
"""
Script para crear un entorno virtual limpio con solo las dependencias esenciales
"""
import subprocess
import sys
import os
import venv

def ejecutar_comando(comando, cwd=None):
    """Ejecuta un comando y muestra el resultado"""
    print(f"Ejecutando: {comando}")
    try:
        resultado = subprocess.run(comando, shell=True, capture_output=True, text=True, cwd=cwd)
        if resultado.stdout:
            print(resultado.stdout)
        if resultado.stderr:
            print(f"Error: {resultado.stderr}")
        return resultado.returncode == 0
    except Exception as e:
        print(f"Error ejecutando comando: {e}")
        return False

def crear_entorno_virtual():
    """Crea un entorno virtual limpio"""
    print("=== CREANDO ENTORNO VIRTUAL LIMPIO ===\n")
    
    # Crear directorio para el entorno virtual
    venv_dir = "venv_escaner"
    if os.path.exists(venv_dir):
        print(f"Eliminando entorno virtual existente: {venv_dir}")
        subprocess.run(f"rmdir /s /q {venv_dir}", shell=True)
    
    print(f"Creando entorno virtual: {venv_dir}")
    venv.create(venv_dir, with_pip=True)
    
    # Determinar el comando de activación según el sistema operativo
    if os.name == 'nt':  # Windows
        pip_path = os.path.join(venv_dir, "Scripts", "pip.exe")
        python_path = os.path.join(venv_dir, "Scripts", "python.exe")
    else:  # Linux/Mac
        pip_path = os.path.join(venv_dir, "bin", "pip")
        python_path = os.path.join(venv_dir, "bin", "python")
    
    # Instalar dependencias esenciales
    dependencias = [
        "customtkinter==5.2.2",
        "pillow==11.2.1", 
        "pandas==2.3.0",
        "openpyxl==3.1.5",
        "psycopg2-binary==2.9.10",
        "python-dotenv==1.1.1",
        "tkcalendar==1.6.1"
    ]
    
    print("\nInstalando dependencias esenciales...")
    for dep in dependencias:
        print(f"Instalando {dep}...")
        comando = f'"{pip_path}" install {dep}'
        if not ejecutar_comando(comando):
            print(f"Error instalando {dep}")
    
    # Mostrar dependencias instaladas
    print("\nDependencias instaladas:")
    ejecutar_comando(f'"{pip_path}" freeze')
    
    print(f"\n=== ENTORNO VIRTUAL CREADO EN: {venv_dir} ===")
    print("Para activar el entorno virtual:")
    if os.name == 'nt':  # Windows
        print(f"  {venv_dir}\\Scripts\\activate")
    else:  # Linux/Mac
        print(f"  source {venv_dir}/bin/activate")
    print("\nPara ejecutar la aplicación:")
    print(f"  {python_path} Escaner_V0.3.2.py")

if __name__ == "__main__":
    crear_entorno_virtual() 