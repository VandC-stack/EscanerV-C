#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Configura PostgreSQL para aceptar conexiones remotas
"""
import os
import subprocess
import sys

def configurar_postgres_remoto():
    """Configura PostgreSQL para aceptar conexiones remotas"""
    print("=== Configurando PostgreSQL para conexiones remotas ===")
    
    # 1. Configurar postgresql.conf
    print("1. Configurando postgresql.conf...")
    postgresql_conf = r"C:\Program Files\PostgreSQL\17\data\postgresql.conf"
    
    if not os.path.exists(postgresql_conf):
        print(f"❌ No se encontró: {postgresql_conf}")
        print("Busca el archivo postgresql.conf en tu instalación de PostgreSQL")
        return False
    
    # Leer configuración actual
    with open(postgresql_conf, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Cambiar listen_addresses
    if 'listen_addresses' in content:
        content = content.replace(
            'listen_addresses = \'localhost\'',
            'listen_addresses = \'*\''
        )
    else:
        content += "\nlisten_addresses = '*'"
    
    # Guardar cambios
    with open(postgresql_conf, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print("✓ postgresql.conf configurado")
    
    # 2. Configurar pg_hba.conf
    print("2. Configurando pg_hba.conf...")
    pg_hba_conf = r"C:\Program Files\PostgreSQL\17\data\pg_hba.conf"
    
    if not os.path.exists(pg_hba_conf):
        print(f"❌ No se encontró: {pg_hba_conf}")
        return False
    
    # Leer configuración actual
    with open(pg_hba_conf, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Agregar línea para permitir conexiones remotas
    if 'host    all             all             0.0.0.0/0               md5' not in content:
        content += "\nhost    all             all             0.0.0.0/0               md5"
    
    # Guardar cambios
    with open(pg_hba_conf, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print("✓ pg_hba.conf configurado")
    
    # 3. Reiniciar servicio
    print("3. Reiniciando servicio PostgreSQL...")
    try:
        subprocess.run([
            'net', 'stop', 'postgresql-x64-17'
        ], check=True, capture_output=True)
        
        subprocess.run([
            'net', 'start', 'postgresql-x64-17'
        ], check=True, capture_output=True)
        
        print("✓ Servicio reiniciado")
    except subprocess.CalledProcessError as e:
        print(f"⚠️  Error reiniciando servicio: {e}")
        print("Reinicia manualmente el servicio PostgreSQL")
    
    print("\n✅ Configuración completada")
    print("Tu servidor PostgreSQL ahora acepta conexiones remotas")
    print("IP del servidor: 192.168.1.167")
    print("Puerto: 5432")
    
    return True

if __name__ == "__main__":
    configurar_postgres_remoto() 