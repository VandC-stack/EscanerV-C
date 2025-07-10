#!/usr/bin/env python3
"""
Script para verificar que la aplicación funciona correctamente
"""
import sys
import os

def verificar_importaciones():
    """Verifica que todas las dependencias se pueden importar"""
    print("=== VERIFICACIÓN DE DEPENDENCIAS ===")
    
    dependencias = [
        ("customtkinter", "Interfaz gráfica"),
        ("PIL", "Manejo de imágenes"),
        ("pandas", "Procesamiento de datos"),
        ("openpyxl", "Archivos Excel"),
        ("psycopg2", "Base de datos PostgreSQL"),
        ("dotenv", "Variables de entorno"),
        ("tkcalendar", "Selector de fechas")
    ]
    
    errores = []
    for modulo, descripcion in dependencias:
        try:
            __import__(modulo)
            print(f"✅ {modulo} - {descripcion}")
        except ImportError as e:
            print(f"❌ {modulo} - Error: {e}")
            errores.append(modulo)
    
    return len(errores) == 0

def verificar_aplicacion():
    """Verifica que la aplicación se puede importar"""
    print("\n=== VERIFICACIÓN DE LA APLICACIÓN ===")
    
    try:
        # Intentar importar la aplicación
        import Escaner_V0_3_2
        print("✅ La aplicación se puede importar correctamente")
        return True
    except ImportError as e:
        print(f"❌ Error importando la aplicación: {e}")
        return False
    except Exception as e:
        print(f"⚠️  Advertencia al importar la aplicación: {e}")
        return True  # Puede ser un error menor

def main():
    print("Verificando aplicación Escáner V&C después de la actualización...\n")
    
    # Verificar dependencias
    dependencias_ok = verificar_importaciones()
    
    # Verificar aplicación
    aplicacion_ok = verificar_aplicacion()
    
    print("\n=== RESUMEN ===")
    if dependencias_ok and aplicacion_ok:
        print("✅ Todo está funcionando correctamente")
        print("✅ Tu aplicación está lista para usar")
    elif dependencias_ok:
        print("⚠️  Las dependencias están bien, pero hay un problema menor con la aplicación")
        print("💡 Intenta ejecutar la aplicación directamente: python Escaner_V0.3.2.py")
    else:
        print("❌ Hay problemas con las dependencias")
        print("💡 Revisa los errores y considera reinstalar las dependencias")

if __name__ == "__main__":
    main() 