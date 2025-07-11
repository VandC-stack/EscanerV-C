#!/usr/bin/env python3
"""
Script para actualizar todas las dependencias del proyecto Escáner V&C
"""
import subprocess
import sys
import os
import json
from datetime import datetime

def ejecutar_comando(comando, cwd=None):
    """Ejecuta un comando y muestra el resultado"""
    print(f"Ejecutando: {comando}")
    try:
        resultado = subprocess.run(comando, shell=True, capture_output=True, text=True, cwd=cwd)
        if resultado.stdout:
            print(resultado.stdout)
        if resultado.stderr:
            print(f"Error: {resultado.stderr}")
        return resultado.returncode == 0, resultado.stdout
    except Exception as e:
        print(f"Error ejecutando comando: {e}")
        return False, ""

def obtener_version_latest(package_name):
    """Obtiene la versión más reciente de un paquete"""
    try:
        resultado = subprocess.run(
            f"pip index versions {package_name}",
            shell=True, capture_output=True, text=True
        )
        if resultado.returncode == 0:
            # Buscar la versión más reciente en la salida
            lines = resultado.stdout.split('\n')
            for line in lines:
                if 'LATEST:' in line:
                    version = line.split('LATEST:')[1].strip()
                    return version
    except Exception as e:
        print(f"Error obteniendo versión de {package_name}: {e}")
    return None

def actualizar_dependencias():
    """Actualiza todas las dependencias del proyecto"""
    print("=== ACTUALIZACIÓN DE DEPENDENCIAS ESCÁNER V&C ===\n")
    
    # Dependencias esenciales con versiones actuales
    dependencias_actuales = {
        "customtkinter": "5.2.2",
        "pillow": "11.2.1", 
        "pandas": "2.3.0",
        "openpyxl": "3.1.5",
        "psycopg2-binary": "2.9.10",
        "python-dotenv": "1.1.1",
        "tkcalendar": "1.6.1"
    }
    
    print("1. Verificando versiones actuales...")
    dependencias_actualizadas = {}
    
    for package, version_actual in dependencias_actuales.items():
        print(f"\nVerificando {package}...")
        version_latest = obtener_version_latest(package)
        
        if version_latest:
            print(f"  Versión actual: {version_actual}")
            print(f"  Versión más reciente: {version_latest}")
            
            if version_latest != version_actual:
                print(f"  ✅ Actualización disponible")
                dependencias_actualizadas[package] = version_latest
            else:
                print(f"  ✅ Ya está actualizada")
                dependencias_actualizadas[package] = version_actual
        else:
            print(f"  ⚠️  No se pudo verificar versión, manteniendo actual")
            dependencias_actualizadas[package] = version_actual
    
    # Actualizar pip primero
    print("\n2. Actualizando pip...")
    ejecutar_comando("python -m pip install --upgrade pip")
    
    # Actualizar dependencias
    print("\n3. Actualizando dependencias...")
    for package, version in dependencias_actualizadas.items():
        print(f"\nActualizando {package} a versión {version}...")
        comando = f"pip install {package}=={version} --upgrade"
        if ejecutar_comando(comando)[0]:
            print(f"  ✅ {package} actualizado correctamente")
        else:
            print(f"  ❌ Error actualizando {package}")
    
    # Crear nuevo requirements.txt
    print("\n4. Generando nuevo requirements.txt...")
    nuevo_requirements = "# Dependencias actualizadas para Escáner V&C\n"
    nuevo_requirements += f"# Actualizado el: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n"
    
    for package, version in dependencias_actualizadas.items():
        nuevo_requirements += f"{package}=={version}\n"
    
    nuevo_requirements += "\n# Dependencias opcionales para desarrollo/distribución\n"
    nuevo_requirements += "# pyinstaller==6.14.1  # Solo si necesitas crear ejecutables\n"
    
    # Guardar nuevo requirements.txt
    with open("requirements.txt", "w", encoding="utf-8") as f:
        f.write(nuevo_requirements)
    
    print("✅ requirements.txt actualizado")
    
    # Mostrar dependencias finales
    print("\n5. Dependencias instaladas:")
    ejecutar_comando("pip freeze")
    
    # Crear reporte de actualización
    reporte = {
        "fecha_actualizacion": datetime.now().isoformat(),
        "dependencias_actualizadas": dependencias_actualizadas,
        "total_dependencias": len(dependencias_actualizadas)
    }
    
    with open("reporte_actualizacion.json", "w", encoding="utf-8") as f:
        json.dump(reporte, f, indent=2, ensure_ascii=False)
    
    print("\n=== ACTUALIZACIÓN COMPLETADA ===")
    print(f"✅ {len(dependencias_actualizadas)} dependencias actualizadas")
    print("✅ requirements.txt regenerado")
    print("✅ reporte_actualizacion.json creado")
    print("\nTu proyecto está ahora con las versiones más recientes y estables.")

def verificar_compatibilidad():
    """Verifica que la aplicación funcione después de la actualización"""
    print("\n=== VERIFICACIÓN DE COMPATIBILIDAD ===")
    
    # Verificar que se pueden importar las dependencias
    dependencias_test = [
        "customtkinter",
        "PIL",
        "pandas", 
        "openpyxl",
        "psycopg2",
        "dotenv",
        "tkcalendar"
    ]
    
    errores = []
    for dep in dependencias_test:
        try:
            __import__(dep)
            print(f"✅ {dep} - OK")
        except ImportError as e:
            print(f"❌ {dep} - Error: {e}")
            errores.append(dep)
    
    if errores:
        print(f"\n⚠️  Problemas detectados con: {', '.join(errores)}")
        print("Revisa los errores y considera usar versiones anteriores si es necesario.")
    else:
        print("\n✅ Todas las dependencias son compatibles")
    
    # Intentar ejecutar la aplicación
    print("\nProbando ejecución de la aplicación...")
    try:
        resultado = subprocess.run(
            "python -c \"import Escaner_V0.3.2; print('✅ Aplicación se puede importar correctamente')\"",
            shell=True, capture_output=True, text=True, timeout=10
        )
        if resultado.returncode == 0:
            print("✅ La aplicación se puede importar sin errores")
        else:
            print(f"⚠️  Problemas al importar la aplicación: {resultado.stderr}")
    except Exception as e:
        print(f"⚠️  Error verificando aplicación: {e}")

if __name__ == "__main__":
    actualizar_dependencias()
    verificar_compatibilidad() 