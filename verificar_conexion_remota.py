#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Script para verificar conexión remota a PostgreSQL
Después de aplicar la configuración de autenticación
"""
import socket
import subprocess
import sys
import time

def hacer_ping(host):
    """Hace ping a un host"""
    try:
        result = subprocess.run(['ping', '-n', '1', host], 
                              capture_output=True, text=True, timeout=10)
        return result.returncode == 0
    except:
        return False

def verificar_puerto(host, puerto):
    """Verifica si un puerto está abierto"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        result = sock.connect_ex((host, puerto))
        sock.close()
        return result == 0
    except:
        return False

def probar_conexion_postgresql():
    """Prueba conexión a PostgreSQL"""
    try:
        import psycopg2
        
        config = {
            "host": "192.168.1.167",
            "port": 5432,
            "user": "postgres",
            "password": "ubuntu",
            "database": "Escaner",
            "client_encoding": "UTF8",
            "connect_timeout": 10
        }
        
        print(f"🔌 Conectando a {config['host']}:{config['port']}...")
        conn = psycopg2.connect(**config)
        cursor = conn.cursor()
        
        # Probar consultas básicas
        cursor.execute("SELECT version();")
        version = cursor.fetchone()
        print(f"✅ Conexión exitosa!")
        print(f"📊 Versión PostgreSQL: {version[0]}")
        
        cursor.execute("SELECT current_user;")
        usuario = cursor.fetchone()
        print(f"👤 Usuario conectado: {usuario[0]}")
        
        cursor.execute("SELECT current_database();")
        db = cursor.fetchone()
        print(f"🗄️  Base de datos: {db[0]}")
        
        # Verificar tablas
        cursor.execute("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")
        num_tablas = cursor.fetchone()
        print(f"📋 Número de tablas: {num_tablas[0]}")
        
        # Verificar tabla usuarios
        cursor.execute("SELECT COUNT(*) FROM usuarios;")
        num_usuarios = cursor.fetchone()
        print(f"👥 Usuarios en sistema: {num_usuarios[0]}")
        
        conn.close()
        return True
        
    except ImportError:
        print("❌ psycopg2 no está instalado")
        print("Instala con: pip install psycopg2-binary")
        return False
    except Exception as e:
        print(f"❌ Error de conexión: {e}")
        return False

def verificar_red():
    """Verifica conectividad de red"""
    print("🌐 Verificando conectividad de red...")
    
    # Obtener IP local
    try:
        hostname = socket.gethostname()
        ip_local = socket.gethostbyname(hostname)
        print(f"📍 IP local: {ip_local}")
    except:
        print("❌ No se pudo obtener IP local")
        return False
    
    # Verificar conectividad al servidor
    servidor = "192.168.1.167"
    print(f"🎯 Servidor objetivo: {servidor}")
    
    # Ping al servidor
    print(f"📡 Ping a {servidor}: ", end="")
    if hacer_ping(servidor):
        print("✅ Conectividad OK")
    else:
        print("❌ Sin conectividad")
        return False
    
    # Verificar puerto PostgreSQL
    print(f"🔌 Puerto 5432 en {servidor}: ", end="")
    if verificar_puerto(servidor, 5432):
        print("✅ Puerto abierto")
    else:
        print("❌ Puerto cerrado")
        return False
    
    return True

def mostrar_diagnostico():
    """Muestra diagnóstico completo"""
    print("\n🔍 DIAGNÓSTICO DE CONEXIÓN REMOTA")
    print("=" * 50)
    
    # Verificar red
    if not verificar_red():
        print("\n❌ PROBLEMAS DE RED DETECTADOS")
        print("Soluciones:")
        print("1. Verifica que el servidor esté encendido")
        print("2. Verifica la conectividad de red")
        print("3. Verifica el firewall del servidor")
        print("4. Verifica el reenvío de puertos en el router")
        return False
    
    # Probar conexión PostgreSQL
    print("\n🗄️  Probando conexión PostgreSQL...")
    if probar_conexion_postgresql():
        print("\n✅ CONEXIÓN REMOTA FUNCIONANDO CORRECTAMENTE")
        print("🎉 Tu aplicación .exe debería funcionar sin problemas")
        return True
    else:
        print("\n❌ PROBLEMAS DE CONEXIÓN POSTGRESQL")
        print("Posibles causas:")
        print("1. PostgreSQL no está configurado para conexiones remotas")
        print("2. Problemas de autenticación (md5 vs scram-sha-256)")
        print("3. Usuario o contraseña incorrectos")
        print("4. Base de datos no existe")
        print("\nSoluciones:")
        print("1. Ejecuta arreglar_autenticacion_postgresql.py en el servidor")
        print("2. Reinicia el servicio PostgreSQL")
        print("3. Verifica las credenciales")
        print("4. Crea la base de datos si no existe")
        return False

def main():
    """Función principal"""
    print("🔍 VERIFICADOR DE CONEXIÓN REMOTA POSTGRESQL")
    print("=" * 60)
    print("Este script verifica que la conexión remota funcione")
    print("después de configurar PostgreSQL para conexiones remotas")
    print()
    
    # Ejecutar diagnóstico
    if mostrar_diagnostico():
        print("\n🎯 RESULTADO: Conexión remota OK")
        print("Tu aplicación está lista para distribuir")
    else:
        print("\n⚠️  RESULTADO: Problemas detectados")
        print("Revisa las soluciones sugeridas arriba")

if __name__ == "__main__":
    main() 