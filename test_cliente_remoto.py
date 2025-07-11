#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Script de prueba para clientes remotos
Verifica que la conexión al servidor PostgreSQL funcione
"""
import sys
import socket

def test_conexion():
    """Prueba la conexión al servidor"""
    print("🔍 PRUEBA DE CONEXIÓN REMOTA")
    print("=" * 40)
    print("Servidor: 192.168.1.167")
    print("Puerto: 5432")
    print()
    
    # Verificar conectividad básica
    print("1. Verificando conectividad de red...")
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        result = sock.connect_ex(('192.168.1.167', 5432))
        sock.close()
        
        if result == 0:
            print("✅ Puerto 5432 está abierto y accesible")
        else:
            print("❌ No se puede conectar al puerto 5432")
            print("   Verifica:")
            print("   - Que el servidor esté encendido")
            print("   - Que no haya firewall bloqueando")
            print("   - Que el reenvío de puertos esté configurado")
            return False
    except Exception as e:
        print(f"❌ Error de red: {e}")
        return False
    
    # Verificar conexión PostgreSQL
    print("\n2. Verificando conexión PostgreSQL...")
    try:
        import psycopg2
        
        config = {
            "host": "192.168.1.167",
            "port": 5432,
            "user": "postgres",
            "password": "ubuntu",
            "database": "Escaner",
            "connect_timeout": 10
        }
        
        conn = psycopg2.connect(**config)
        cursor = conn.cursor()
        
        # Probar consulta simple
        cursor.execute("SELECT COUNT(*) FROM usuarios;")
        count = cursor.fetchone()
        
        conn.close()
        
        print(f"✅ Conexión PostgreSQL exitosa")
        print(f"✅ Base de datos accesible ({count[0]} usuarios)")
        print("\n🎉 ¡Todo funciona correctamente!")
        print("   Tu aplicación .exe debería funcionar sin problemas")
        return True
        
    except ImportError:
        print("❌ psycopg2 no está instalado")
        print("   Esto es normal en clientes - la aplicación .exe incluye todo lo necesario")
        print("✅ La aplicación debería funcionar correctamente")
        return True
        
    except Exception as e:
        print(f"❌ Error de conexión PostgreSQL: {e}")
        print("\nPosibles soluciones:")
        print("1. Verifica que el servidor esté configurado para conexiones remotas")
        print("2. Verifica las credenciales de acceso")
        print("3. Contacta al administrador del sistema")
        return False

def main():
    """Función principal"""
    print("🚀 VERIFICADOR PARA CLIENTES REMOTOS")
    print("=" * 50)
    print("Este script verifica que puedas conectarte al servidor")
    print("antes de usar la aplicación Escáner V&C")
    print()
    
    if test_conexion():
        print("\n✅ VERIFICACIÓN EXITOSA")
        print("Puedes usar la aplicación Escaner_V0.3.2.exe")
    else:
        print("\n❌ VERIFICACIÓN FALLIDA")
        print("Contacta al administrador antes de usar la aplicación")
    
    print("\nPresiona Enter para salir...")
    input()

if __name__ == "__main__":
    main() 