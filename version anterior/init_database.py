#!/usr/bin/env python3
"""
Script para inicializar la base de datos y crear usuario admin
"""

import sys
import os

# Agregar el directorio actual al path para importar módulos
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from config.database import DatabaseManager

def main():
    """Función principal"""
    print("🔧 Inicializando base de datos...")
    print("=" * 50)
    
    try:
        # Crear instancia del gestor de base de datos
        db_manager = DatabaseManager()
        
        # Probar conexión
        print("🔗 Probando conexión a la base de datos...")
        if not db_manager.test_connection():
            print("❌ Error: No se pudo conectar a la base de datos")
            print("Verifica que PostgreSQL esté ejecutándose y las credenciales sean correctas")
            return False
        
        print("✅ Conexión exitosa")
        
        # Crear tablas
        print("📋 Creando tablas...")
        db_manager.create_tables()
        print("✅ Tablas creadas")
        
        # Insertar datos por defecto
        print("👤 Creando usuario administrador...")
        db_manager.insert_default_data()
        print("✅ Usuario admin creado")
        
        print("\n" + "=" * 50)
        print("🎉 Base de datos inicializada correctamente!")
        print("=" * 50)
        print("📝 Credenciales de acceso:")
        print("   Usuario: admin")
        print("   Contraseña: admin123")
        print("   Rol: admin")
        print("\n🚀 Ya puedes ejecutar la aplicación: python Escaner_V3.0.0.py")
        
        return True
        
    except Exception as e:
        print(f"❌ Error inicializando base de datos: {str(e)}")
        return False

if __name__ == "__main__":
    success = main()
    if not success:
        sys.exit(1) 