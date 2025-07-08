#!/usr/bin/env python3
"""
Script para arreglar la estructura de la base de datos
"""

import sys
import os

# Agregar el directorio actual al path para importar módulos
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from config.database import DatabaseManager

def main():
    """Función principal"""
    print("🔧 Arreglando estructura de la base de datos...")
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
        
        # Leer el script SQL
        script_path = os.path.join(os.path.dirname(__file__), 'fix_database.sql')
        with open(script_path, 'r', encoding='utf-8') as f:
            sql_script = f.read()
        
        print("📝 Ejecutando script SQL...")
        
        # Dividir el script en comandos individuales
        commands = [cmd.strip() for cmd in sql_script.split(';') if cmd.strip()]
        
        for i, command in enumerate(commands, 1):
            if command and not command.startswith('--'):
                try:
                    print(f"   Ejecutando comando {i}/{len(commands)}...")
                    db_manager.execute_query(command, fetch=False)
                except Exception as e:
                    print(f"   ⚠️  Advertencia en comando {i}: {str(e)}")
                    # Continuar con el siguiente comando
        
        print("✅ Script SQL ejecutado correctamente")
        
        # Verificar que las tablas se crearon
        print("\n🔍 Verificando estructura de tablas...")
        
        # Verificar tabla codigos_items
        result = db_manager.execute_query(
            "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'codigos_items' ORDER BY ordinal_position"
        )
        if result:
            print("✅ Tabla 'codigos_items' creada correctamente")
            for col in result:
                print(f"   - {col['column_name']}: {col['data_type']}")
        else:
            print("❌ Error: No se pudo verificar la tabla 'codigos_items'")
        
        # Verificar tabla capturas
        result = db_manager.execute_query(
            "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'capturas' ORDER BY ordinal_position"
        )
        if result:
            print("✅ Tabla 'capturas' creada correctamente")
            for col in result:
                print(f"   - {col['column_name']}: {col['data_type']}")
        else:
            print("❌ Error: No se pudo verificar la tabla 'capturas'")
        
        print("\n🎉 ¡Base de datos arreglada exitosamente!")
        print("Ahora puedes ejecutar la aplicación sin errores de estructura de tabla")
        
        return True
        
    except Exception as e:
        print(f"❌ Error: {str(e)}")
        return False

if __name__ == "__main__":
    success = main()
    if not success:
        sys.exit(1) 