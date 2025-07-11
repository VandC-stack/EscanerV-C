#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Script para arreglar la configuración de autenticación de PostgreSQL
Soluciona el conflicto entre md5 y scram-sha-256 para conexiones remotas
"""
import os
import shutil
import subprocess
import sys
from datetime import datetime

def encontrar_postgresql():
    """Encuentra la instalación de PostgreSQL"""
    rutas_posibles = [
        "C:\\Program Files\\PostgreSQL\\17\\data\\",
        "C:\\Program Files\\PostgreSQL\\16\\data\\",
        "C:\\Program Files\\PostgreSQL\\15\\data\\",
        "C:\\Program Files\\PostgreSQL\\14\\data\\",
        "C:\\Program Files\\PostgreSQL\\13\\data\\"
    ]
    
    for ruta in rutas_posibles:
        if os.path.exists(ruta):
            return ruta
    
    return None

def arreglar_pg_hba_conf():
    """Arregla la configuración de pg_hba.conf para usar scram-sha-256"""
    print("🔧 Arreglando configuración de autenticación PostgreSQL")
    print("=" * 60)
    
    # Encontrar instalación de PostgreSQL
    data_dir = encontrar_postgresql()
    if not data_dir:
        print("❌ No se encontró instalación de PostgreSQL")
        print("Verifica que PostgreSQL esté instalado")
        return False
    
    pg_hba_path = os.path.join(data_dir, "pg_hba.conf")
    postgresql_conf_path = os.path.join(data_dir, "postgresql.conf")
    
    if not os.path.exists(pg_hba_path):
        print(f"❌ No se encontró pg_hba.conf en: {pg_hba_path}")
        return False
    
    print(f"📁 Directorio de datos: {data_dir}")
    print(f"📄 Archivo pg_hba.conf: {pg_hba_path}")
    
    # Crear backup
    backup_path = f"{pg_hba_path}.backup.{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    shutil.copy2(pg_hba_path, backup_path)
    print(f"💾 Backup creado: {backup_path}")
    
    # Leer configuración actual
    with open(pg_hba_path, 'r', encoding='utf-8') as f:
        contenido = f.read()
    
    print("\n📋 Configuración actual de pg_hba.conf:")
    print("-" * 40)
    for i, linea in enumerate(contenido.split('\n'), 1):
        if linea.strip() and not linea.startswith('#'):
            print(f"{i:2d}: {linea}")
    
    # Configuración corregida
    configuracion_corregida = '''# PostgreSQL Client Authentication Configuration File
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
# Permitir conexiones desde cualquier IP usando scram-sha-256
host    all             all             0.0.0.0/0               scram-sha-256
'''
    
    # Escribir nueva configuración
    with open(pg_hba_path, 'w', encoding='utf-8') as f:
        f.write(configuracion_corregida)
    
    print("\n✅ pg_hba.conf actualizado correctamente")
    print("🔑 Método de autenticación cambiado a: scram-sha-256")
    
    # Verificar postgresql.conf
    if os.path.exists(postgresql_conf_path):
        with open(postgresql_conf_path, 'r', encoding='utf-8') as f:
            postgresql_content = f.read()
        
        if "listen_addresses = '*'" not in postgresql_content:
            print("\n⚠️  Configurando postgresql.conf...")
            
            # Hacer backup
            backup_postgresql = f"{postgresql_conf_path}.backup.{datetime.now().strftime('%Y%m%d_%H%M%S')}"
            shutil.copy2(postgresql_conf_path, backup_postgresql)
            
            # Cambiar listen_addresses
            if 'listen_addresses' in postgresql_content:
                postgresql_content = postgresql_content.replace(
                    'listen_addresses = \'localhost\'',
                    'listen_addresses = \'*\''
                )
                postgresql_content = postgresql_content.replace(
                    'listen_addresses = \'127.0.0.1\'',
                    'listen_addresses = \'*\''
                )
            else:
                postgresql_content += "\nlisten_addresses = '*'"
            
            with open(postgresql_conf_path, 'w', encoding='utf-8') as f:
                f.write(postgresql_content)
            
            print("✅ postgresql.conf configurado para escuchar en todas las interfaces")
    
    return True

def reiniciar_postgresql():
    """Reinicia el servicio PostgreSQL"""
    print("\n🔄 Reiniciando servicio PostgreSQL...")
    
    try:
        # Detener servicio
        print("⏹️  Deteniendo servicio...")
        result = subprocess.run([
            'net', 'stop', 'postgresql-x64-17'
        ], capture_output=True, text=True, shell=True)
        
        if result.returncode != 0:
            # Intentar con otros nombres de servicio
            servicios = ['postgresql-x64-16', 'postgresql-x64-15', 'postgresql-x64-14']
            for servicio in servicios:
                result = subprocess.run([
                    'net', 'stop', servicio
                ], capture_output=True, text=True, shell=True)
                if result.returncode == 0:
                    break
        
        # Iniciar servicio
        print("▶️  Iniciando servicio...")
        result = subprocess.run([
            'net', 'start', 'postgresql-x64-17'
        ], capture_output=True, text=True, shell=True)
        
        if result.returncode != 0:
            # Intentar con otros nombres de servicio
            servicios = ['postgresql-x64-16', 'postgresql-x64-15', 'postgresql-x64-14']
            for servicio in servicios:
                result = subprocess.run([
                    'net', 'start', servicio
                ], capture_output=True, text=True, shell=True)
                if result.returncode == 0:
                    break
        
        if result.returncode == 0:
            print("✅ Servicio PostgreSQL reiniciado correctamente")
            return True
        else:
            print("⚠️  No se pudo reiniciar automáticamente")
            print("Reinicia manualmente el servicio PostgreSQL desde el Administrador de Servicios")
            return False
            
    except Exception as e:
        print(f"❌ Error reiniciando servicio: {e}")
        print("Reinicia manualmente el servicio PostgreSQL")
        return False

def verificar_conexion():
    """Verifica que la conexión funcione correctamente"""
    print("\n🔍 Verificando conexión...")
    
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
        
        # Verificar versión
        cursor.execute("SELECT version();")
        version = cursor.fetchone()
        print(f"✅ Conexión local exitosa")
        print(f"📊 Versión PostgreSQL: {version[0]}")
        
        # Verificar configuración de autenticación
        cursor.execute("SHOW password_encryption;")
        encryption = cursor.fetchone()
        print(f"🔐 Método de encriptación: {encryption[0]}")
        
        # Verificar usuarios
        cursor.execute("SELECT usename, passwd FROM pg_shadow LIMIT 3;")
        usuarios = cursor.fetchall()
        print(f"👥 Usuarios en el sistema: {len(usuarios)}")
        
        conn.close()
        return True
        
    except ImportError:
        print("❌ psycopg2 no está instalado")
        print("Instala con: pip install psycopg2-binary")
        return False
    except Exception as e:
        print(f"❌ Error de conexión: {e}")
        return False

def mostrar_instrucciones():
    """Muestra instrucciones adicionales"""
    print("\n📋 INSTRUCCIONES ADICIONALES:")
    print("=" * 50)
    print("1. Si el reinicio automático falló, reinicia manualmente:")
    print("   - Abre 'Servicios' (services.msc)")
    print("   - Busca 'postgresql-x64-17' (o la versión que tengas)")
    print("   - Haz clic derecho → Reiniciar")
    print()
    print("2. Verifica el firewall de Windows:")
    print("   - Abre 'Firewall de Windows Defender'")
    print("   - Permite PostgreSQL a través del firewall")
    print("   - O desactiva temporalmente para pruebas")
    print()
    print("3. Si usas un router, configura reenvío de puertos:")
    print("   - Puerto externo: 5432")
    print("   - IP interna: 192.168.1.167")
    print("   - Puerto interno: 5432")
    print("   - Protocolo: TCP")
    print()
    print("4. Para probar conexión remota desde otro equipo:")
    print("   psql -h 192.168.1.167 -U postgres -d Escaner")
    print()
    print("5. Si persisten problemas de autenticación:")
    print("   ALTER USER postgres WITH PASSWORD 'nueva_contraseña';")

def main():
    """Función principal"""
    print("🚀 ARREGLANDO CONFIGURACIÓN DE AUTENTICACIÓN POSTGRESQL")
    print("=" * 70)
    print("Este script soluciona el conflicto entre md5 y scram-sha-256")
    print("para conexiones remotas a PostgreSQL")
    print()
    
    # Arreglar configuración
    if arreglar_pg_hba_conf():
        # Reiniciar servicio
        if reiniciar_postgresql():
            # Verificar conexión
            verificar_conexion()
        else:
            print("\n⚠️  IMPORTANTE: Reinicia PostgreSQL manualmente")
        
        # Mostrar instrucciones
        mostrar_instrucciones()
        
        print("\n✅ Proceso completado")
        print("🎯 Tu servidor PostgreSQL ahora debería aceptar conexiones remotas")
        print("🌐 IP del servidor: 192.168.1.167")
        print("🔌 Puerto: 5432")
        
    else:
        print("\n❌ No se pudo completar la configuración")
        print("Verifica los permisos y la instalación de PostgreSQL")

if __name__ == "__main__":
    main() 