#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Script para probar conexión remota a PostgreSQL
"""
import psycopg2
import json
import socket

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

def probar_conexion_remota():
    """Prueba conexión remota al servidor PostgreSQL"""
    try:
        # Cargar configuración
        with open("database_config_cliente.json", "r") as f:
            config = json.load(f)
        
        ip_cliente = obtener_ip_local()
        print(f"IP del cliente: {ip_cliente}")
        print(f"Probando conexión a {config['host']}:{config['port']}...")
        
        # Intentar conexión
        conn = psycopg2.connect(**config)
        print("OK - Conexión remota exitosa!")
        
        # Probar consulta simple
        cursor = conn.cursor()
        cursor.execute("SELECT version();")
        version = cursor.fetchone()
        print(f"OK - Versión de PostgreSQL: {version[0]}")
        
        # Probar consulta a la base de datos específica
        cursor.execute("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")
        num_tablas = cursor.fetchone()
        print(f"OK - Número de tablas en la base de datos: {num_tablas[0]}")
        
        conn.close()
        return True
        
    except FileNotFoundError:
        print("ERROR - No se encontró database_config_cliente.json")
        print("Asegúrate de que el archivo esté en el mismo directorio")
        return False
    except Exception as e:
        print(f"ERROR - Error de conexión remota: {e}")
        print("\nPosibles soluciones:")
        print("1. Verifica que el servidor esté encendido")
        print("2. Verifica que la IP del servidor sea correcta")
        print("3. Verifica que el firewall permita conexiones al puerto 5432")
        print("4. Verifica que PostgreSQL esté configurado para conexiones remotas")
        return False

if __name__ == "__main__":
    print("🔍 Probando conexión remota a PostgreSQL")
    print("="*50)
    probar_conexion_remota() 