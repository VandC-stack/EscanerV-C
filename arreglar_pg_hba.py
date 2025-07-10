#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Script para arreglar la configuración de pg_hba.conf
"""
import os
import shutil
from datetime import datetime

def arreglar_pg_hba():
    """Arregla la configuración de pg_hba.conf"""
    
    # Rutas posibles de PostgreSQL
    rutas_postgresql = [
        "C:\\Program Files\\PostgreSQL\\17\\data\\",
        "C:\\Program Files\\PostgreSQL\\16\\data\\",
        "C:\\Program Files\\PostgreSQL\\15\\data\\",
        "C:\\Program Files\\PostgreSQL\\14\\data\\"
    ]
    
    pg_hba_path = None
    
    # Buscar el archivo pg_hba.conf
    for ruta in rutas_postgresql:
        if os.path.exists(ruta):
            pg_hba_path = os.path.join(ruta, "pg_hba.conf")
            if os.path.exists(pg_hba_path):
                print(f"Encontrado pg_hba.conf en: {pg_hba_path}")
                break
    
    if not pg_hba_path or not os.path.exists(pg_hba_path):
        print("ERROR - No se encontró pg_hba.conf")
        return False
    
    # Hacer backup del archivo original
    backup_path = f"{pg_hba_path}.backup.{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    shutil.copy2(pg_hba_path, backup_path)
    print(f"Backup creado: {backup_path}")
    
    # Leer el archivo actual
    with open(pg_hba_path, 'r', encoding='utf-8') as f:
        contenido = f.read()
    
    # Configuración correcta para conexiones remotas
    configuracion_correcta = '''# PostgreSQL Client Authentication Configuration File
# ===================================================

# TYPE  DATABASE        USER            ADDRESS                 METHOD

# "local" is for Unix domain socket connections only
local   all             all                                     scram-sha-256

# IPv4 local connections:
host    all             all             127.0.0.1/32            scram-sha-256

# IPv6 local connections:
host    all             all             ::1/128                 scram-sha-256

# Allow replication connections from localhost, by a user with the
# replication privilege.
local   replication     all                                     scram-sha-256
host    replication     all             127.0.0.1/32            scram-sha-256
host    replication     all             ::1/128                 scram-sha-256

# CONFIGURACIÓN PARA CONEXIONES REMOTAS
# Permitir conexiones desde cualquier IP (para uso en redes corporativas)
host    all             all             0.0.0.0/0               md5
'''
    
    # Escribir la nueva configuración
    with open(pg_hba_path, 'w', encoding='utf-8') as f:
        f.write(configuracion_correcta)
    
    print("OK - pg_hba.conf actualizado correctamente")
    print("IMPORTANTE: Reinicia PostgreSQL para aplicar los cambios")
    
    return True

def reiniciar_postgresql():
    """Reinicia PostgreSQL"""
    import subprocess
    
    print("\n=== Reiniciando PostgreSQL ===")
    
    try:
        # Detener el servicio
        subprocess.run(["net", "stop", "postgresql-x64-17"], check=True)
        print("OK - Servicio detenido")
        
        # Iniciar el servicio
        subprocess.run(["net", "start", "postgresql-x64-17"], check=True)
        print("OK - Servicio iniciado")
        
        return True
        
    except subprocess.CalledProcessError as e:
        print(f"ERROR - No se pudo reiniciar automáticamente: {e}")
        print("Reinicia manualmente desde Servicios de Windows")
        return False

def verificar_conexion():
    """Verifica que la conexión funcione correctamente"""
    print("\n=== Verificando conexión ===")
    
    try:
        import psycopg2
        
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
        cursor.execute("SELECT version();")
        version = cursor.fetchone()
        
        conn.close()
        
        print("OK - Conexión local exitosa")
        print(f"Versión: {version[0]}")
        return True
        
    except Exception as e:
        print(f"ERROR - Problema con conexión local: {e}")
        return False

def main():
    """Función principal"""
    print("🔧 Arreglando configuración de PostgreSQL")
    print("="*50)
    
    # Arreglar pg_hba.conf
    if arreglar_pg_hba():
        # Reiniciar PostgreSQL
        if reiniciar_postgresql():
            # Verificar conexión
            verificar_conexion()
        else:
            print("ADVERTENCIA - Reinicia PostgreSQL manualmente y luego verifica la conexión")
    else:
        print("ERROR - No se pudo arreglar la configuración")

if __name__ == "__main__":
    main() 