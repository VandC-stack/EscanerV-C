#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Script completo de diagnóstico para PostgreSQL
"""
import psycopg2
import json
import socket
import subprocess
import platform
from datetime import datetime

def obtener_ip_local():
    """Obtiene la IP local de la máquina"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip_local = s.getsockname()[0]
        s.close()
        return ip_local
    except Exception:
        return "127.0.0.1"

def verificar_puerto(host, puerto):
    """Verifica si un puerto está abierto"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        resultado = sock.connect_ex((host, puerto))
        sock.close()
        return resultado == 0
    except Exception:
        return False

def hacer_ping(host):
    """Hace ping a un host"""
    try:
        if platform.system().lower() == "windows":
            comando = ["ping", "-n", "1", host]
        else:
            comando = ["ping", "-c", "1", host]
        
        resultado = subprocess.run(comando, capture_output=True, text=True)
        return resultado.returncode == 0
    except Exception:
        return False

def probar_conexion_local():
    """Prueba conexión local"""
    print("=== Probando conexión local ===")
    
    try:
        config = {
            "host": "localhost",
            "port": 5432,
            "user": "postgres",
            "password": "ubuntu",
            "database": "Escaner",
            "client_encoding": "UTF8"
        }
        
        conn = psycopg2.connect(**config)
        cursor = conn.cursor()
        
        # Probar consultas básicas
        cursor.execute("SELECT version();")
        version = cursor.fetchone()
        print(f"✓ Versión PostgreSQL: {version[0]}")
        
        cursor.execute("SELECT current_user;")
        usuario = cursor.fetchone()
        print(f"✓ Usuario actual: {usuario[0]}")
        
        cursor.execute("SELECT current_database();")
        db = cursor.fetchone()
        print(f"✓ Base de datos actual: {db[0]}")
        
        cursor.execute("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")
        num_tablas = cursor.fetchone()
        print(f"✓ Número de tablas: {num_tablas[0]}")
        
        # Probar permisos
        cursor.execute("SELECT has_table_privilege('postgres', 'usuarios', 'SELECT');")
        permiso = cursor.fetchone()
        print(f"✓ Permiso SELECT en tabla usuarios: {permiso[0]}")
        
        conn.close()
        return True
        
    except Exception as e:
        print(f"❌ Error en conexión local: {e}")
        return False

def probar_conexion_remota():
    """Prueba conexión remota"""
    print("\n=== Probando conexión remota ===")
    
    try:
        # Cargar configuración
        with open("database_config_cliente.json", "r") as f:
            config = json.load(f)
        
        ip_cliente = obtener_ip_local()
        print(f"IP del cliente: {ip_cliente}")
        print(f"Conectando a: {config['host']}:{config['port']}")
        
        # Verificar conectividad básica
        print(f"Ping a {config['host']}: {'✓' if hacer_ping(config['host']) else '❌'}")
        print(f"Puerto {config['port']} abierto: {'✓' if verificar_puerto(config['host'], config['port']) else '❌'}")
        
        # Intentar conexión
        conn = psycopg2.connect(**config)
        cursor = conn.cursor()
        
        # Probar consultas básicas
        cursor.execute("SELECT version();")
        version = cursor.fetchone()
        print(f"✓ Versión PostgreSQL: {version[0]}")
        
        cursor.execute("SELECT current_user;")
        usuario = cursor.fetchone()
        print(f"✓ Usuario actual: {usuario[0]}")
        
        cursor.execute("SELECT current_database();")
        db = cursor.fetchone()
        print(f"✓ Base de datos actual: {db[0]}")
        
        # Probar permisos específicos
        cursor.execute("SELECT has_schema_privilege('postgres', 'public', 'USAGE');")
        permiso_schema = cursor.fetchone()
        print(f"✓ Permiso USAGE en schema public: {permiso_schema[0]}")
        
        cursor.execute("SELECT has_table_privilege('postgres', 'usuarios', 'SELECT');")
        permiso_tabla = cursor.fetchone()
        print(f"✓ Permiso SELECT en tabla usuarios: {permiso_tabla[0]}")
        
        # Probar inserción (solo lectura)
        cursor.execute("SELECT COUNT(*) FROM usuarios;")
        count = cursor.fetchone()
        print(f"✓ Número de usuarios en tabla: {count[0]}")
        
        conn.close()
        return True
        
    except FileNotFoundError:
        print("❌ No se encontró database_config_cliente.json")
        return False
    except Exception as e:
        print(f"❌ Error en conexión remota: {e}")
        return False

def verificar_configuracion_postgresql():
    """Verifica la configuración de PostgreSQL"""
    print("\n=== Verificando configuración PostgreSQL ===")
    
    try:
        # Verificar postgresql.conf
        rutas = [
            "C:\\Program Files\\PostgreSQL\\17\\data\\postgresql.conf",
            "C:\\Program Files\\PostgreSQL\\16\\data\\postgresql.conf",
            "C:\\Program Files\\PostgreSQL\\15\\data\\postgresql.conf"
        ]
        
        postgresql_conf = None
        for ruta in rutas:
            if os.path.exists(ruta):
                postgresql_conf = ruta
                break
        
        if postgresql_conf:
            with open(postgresql_conf, 'r', encoding='utf-8') as f:
                contenido = f.read()
            
            if "listen_addresses = '*'" in contenido:
                print("✓ listen_addresses configurado correctamente")
            else:
                print("❌ listen_addresses no está configurado para '*'")
        
        # Verificar pg_hba.conf
        pg_hba_path = postgresql_conf.replace('postgresql.conf', 'pg_hba.conf')
        if os.path.exists(pg_hba_path):
            with open(pg_hba_path, 'r', encoding='utf-8') as f:
                contenido = f.read()
            
            if "host    all             all             0.0.0.0/0               md5" in contenido:
                print("✓ pg_hba.conf permite conexiones remotas")
            else:
                print("❌ pg_hba.conf no permite conexiones remotas")
        
        return True
        
    except Exception as e:
        print(f"❌ Error verificando configuración: {e}")
        return False

def verificar_firewall():
    """Verifica configuración de firewall"""
    print("\n=== Verificando Firewall ===")
    
    try:
        if platform.system().lower() == "windows":
            resultado = subprocess.run(
                ["netsh", "advfirewall", "firewall", "show", "rule", "name=all"],
                capture_output=True, text=True
            )
            
            if "5432" in resultado.stdout or "postgresql" in resultado.stdout.lower():
                print("✓ Reglas de firewall para PostgreSQL encontradas")
            else:
                print("⚠️  No se encontraron reglas específicas para PostgreSQL")
                print("   Considera agregar una regla para el puerto 5432")
        
        return True
        
    except Exception as e:
        print(f"❌ Error verificando firewall: {e}")
        return False

def main():
    """Función principal"""
    print("🔍 DIAGNÓSTICO COMPLETO DE POSTGRESQL")
    print("="*60)
    print(f"Fecha: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Sistema: {platform.system()} {platform.release()}")
    
    # Verificar configuración
    verificar_configuracion_postgresql()
    
    # Verificar firewall
    verificar_firewall()
    
    # Probar conexión local
    conexion_local = probar_conexion_local()
    
    # Probar conexión remota
    conexion_remota = probar_conexion_remota()
    
    # Resumen
    print("\n" + "="*60)
    print("RESUMEN DEL DIAGNÓSTICO")
    print("="*60)
    
    if conexion_local:
        print("✓ Conexión local: FUNCIONA")
    else:
        print("❌ Conexión local: FALLA")
    
    if conexion_remota:
        print("✓ Conexión remota: FUNCIONA")
    else:
        print("❌ Conexión remota: FALLA")
    
    if conexion_local and not conexion_remota:
        print("\n🔧 RECOMENDACIONES:")
        print("1. Verifica que el firewall permita conexiones al puerto 5432")
        print("2. Verifica que las redes estén conectadas")
        print("3. Verifica que la IP del servidor sea accesible desde el cliente")
    
    elif not conexion_local:
        print("\n🔧 RECOMENDACIONES:")
        print("1. Verifica que PostgreSQL esté ejecutándose")
        print("2. Verifica las credenciales en database_config.json")
        print("3. Verifica que la base de datos 'Escaner' exista")

if __name__ == "__main__":
    import os
    main() 