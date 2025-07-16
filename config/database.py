"""
Gestor de base de datos para la aplicación
"""
import psycopg2
import psycopg2.extras
import logging
from typing import Dict, List, Optional, Any
import os
import sys

class DatabaseManager:
    def __init__(self):
        # Configuración hardcodeada del servidor central, si, acabo de aprender ese termino
        self.config = {
            "host": "192.168.1.167",  # IP del servidor central
            "port": 5432,
            "user": "postgres",
            "password": "ubuntu",
            "database": "Escaner"
        }
        
        self.connection = None
        self.logger = logging.getLogger(__name__)
    
    def connect(self) -> bool:
        """Conecta a la base de datos"""
        try:
            self.connection = psycopg2.connect(**self.config)
            self.logger.info("Conexión a base de datos establecida")
            return True
        except Exception as e:
            self.logger.error(f"Error conectando a la base de datos: {str(e)}")
            return False
    
    def disconnect(self):
        """Desconecta de la base de datos"""
        if self.connection:
            self.connection.close()
            self.logger.info("Conexión a base de datos cerrada")
    
    def execute_query(self, query: str, params: tuple = None, fetch: bool = True) -> List[Dict[str, Any]]:
        """Ejecuta una consulta SQL"""
        try:
            if not self.connection or self.connection.closed:
                if not self.connect():
                    return []
            
            cursor = self.connection.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
            cursor.execute(query, params)
            
            if fetch:
                result = cursor.fetchall()
                return [dict(row) for row in result]
            else:
                self.connection.commit()
                return []
                
        except Exception as e:
            self.logger.error(f"Error ejecutando consulta: {str(e)}")
            if self.connection:
                self.connection.rollback()
            return []
        finally:
            if 'cursor' in locals():
                cursor.close()
    
    def create_tables(self):
        """Crea las tablas necesarias"""
        try:
            # Tabla de usuarios
            self.execute_query("""
                CREATE TABLE IF NOT EXISTS usuarios (
                    id SERIAL PRIMARY KEY,
                    usuario VARCHAR(50) UNIQUE NOT NULL,
                    password_hash VARCHAR(255) NOT NULL,
                    rol VARCHAR(20) NOT NULL DEFAULT 'usuario',
                    estado VARCHAR(20) NOT NULL DEFAULT 'activo',
                    ultimo_acceso TIMESTAMP,
                    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """, fetch=False)
            
            # Tabla de items
            self.execute_query("""
                CREATE TABLE IF NOT EXISTS items (
                    id SERIAL PRIMARY KEY,
                    item VARCHAR(255) UNIQUE NOT NULL,
                    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """, fetch=False)
            
            # Tabla de códigos de barras
            self.execute_query("""
                CREATE TABLE IF NOT EXISTS codigos_items (
                    id SERIAL PRIMARY KEY,
                    codigo_barras VARCHAR(100) UNIQUE NOT NULL,
                    item_id INTEGER REFERENCES items(id),
                    resultado VARCHAR(255),
                    fecha_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """, fetch=False)
            
            # Tabla de capturas
            self.execute_query("""
                CREATE TABLE IF NOT EXISTS capturas (
                    id SERIAL PRIMARY KEY,
                    codigo_barras VARCHAR(100) NOT NULL,
                    item VARCHAR(255) NOT NULL,
                    motivo VARCHAR(255),
                    cumple VARCHAR(20) NOT NULL,
                    usuario VARCHAR(50) NOT NULL,
                    fecha_captura TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """, fetch=False)
            
            # Tabla de consultas
            self.execute_query("""
                CREATE TABLE IF NOT EXISTS consultas (
                    id SERIAL PRIMARY KEY,
                    usuario VARCHAR(50) NOT NULL,
                    codigo_barras VARCHAR(100) NOT NULL,
                    item_id INTEGER REFERENCES items(id),
                    resultado VARCHAR(255),
                    fecha_hora TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """, fetch=False)
            
            # Tabla de configuración
            self.execute_query("""
                CREATE TABLE IF NOT EXISTS configuracion (
                    id SERIAL PRIMARY KEY,
                    clave VARCHAR(100) UNIQUE NOT NULL,
                    valor TEXT,
                    fecha_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """, fetch=False)
            
            # Tabla de cargas CLP
            self.execute_query("""
                CREATE TABLE IF NOT EXISTS clp_cargas (
                    id SERIAL PRIMARY KEY,
                    archivo VARCHAR(255) NOT NULL,
                    usuario VARCHAR(50) NOT NULL,
                    fecha_carga TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    codigos_agregados INTEGER DEFAULT 0
                )
            """, fetch=False)
            
            self.logger.info("Tablas creadas correctamente")
            
        except Exception as e:
            self.logger.error(f"Error creando tablas: {str(e)}")
    
    def insert_default_data(self):
        """Inserta datos por defecto"""
        try:
            # Verificar si ya existe el usuario admin
            admin_exists = self.execute_query(
                "SELECT COUNT(*) as count FROM usuarios WHERE usuario = 'admin'"
            )
            
            if admin_exists[0]['count'] == 0:
                # Crear usuario admin por defecto
                self.execute_query("""
                    INSERT INTO usuarios (usuario, password_hash, rol, estado)
                    VALUES ('admin', 'admin123', 'superadmin', 'activo')
                """, fetch=False)
                
                self.logger.info("Usuario admin creado por defecto")
            
            # Verificar si ya existe el usuario superadmin
            superadmin_exists = self.execute_query(
                "SELECT COUNT(*) as count FROM usuarios WHERE usuario = 'superadmin'"
            )
            
            if superadmin_exists[0]['count'] == 0:
                # Crear usuario superadmin por defecto
                self.execute_query("""
                    INSERT INTO usuarios (usuario, password_hash, rol, estado)
                    VALUES ('superadmin', 'superadmin123', 'superadmin', 'activo')
                """, fetch=False)
                
                self.logger.info("Usuario superadmin creado por defecto")
            
        except Exception as e:
            self.logger.error(f"Error insertando datos por defecto: {str(e)}")
    
    def fix_encoding_issues(self) -> bool:
        """Intenta arreglar problemas de codificación"""
        try:
            # Configurar codificación de la conexión
            if self.connection:
                self.connection.set_client_encoding('UTF8')
            
            return True
        except Exception as e:
            self.logger.error(f"Error arreglando codificación: {str(e)}")
            return False 

    def insert_one(self, table: str, data: dict) -> Optional[int]:
        """Inserta un registro en la tabla especificada y retorna el ID insertado."""
        keys = ', '.join(data.keys())
        values = tuple(data.values())
        placeholders = ', '.join(['%s'] * len(data))
        query = f"INSERT INTO {table} ({keys}) VALUES ({placeholders}) RETURNING id"
        try:
            if not self.connection or self.connection.closed:
                if not self.connect():
                    return None
            cursor = self.connection.cursor()
            cursor.execute(query, values)
            inserted_id = cursor.fetchone()[0]
            self.connection.commit()
            return inserted_id
        except Exception as e:
            self.logger.error(f"Error insertando en {table}: {str(e)}")
            if self.connection:
                self.connection.rollback()
            return None
        finally:
            if 'cursor' in locals():
                cursor.close()
    
    def update_one(self, table: str, data: dict, condition: dict) -> bool:
        """Actualiza un registro en la tabla especificada basado en la condición."""
        try:
            if not self.connection or self.connection.closed:
                if not self.connect():
                    return False
            
            # Construir la consulta UPDATE
            set_clause = ', '.join([f"{key} = %s" for key in data.keys()])
            where_clause = ' AND '.join([f"{key} = %s" for key in condition.keys()])
            
            query = f"UPDATE {table} SET {set_clause} WHERE {where_clause}"
            
            # Preparar los valores
            values = tuple(list(data.values()) + list(condition.values()))
            
            cursor = self.connection.cursor()
            cursor.execute(query, values)
            
            # Verificar si se actualizó algún registro
            rows_affected = cursor.rowcount
            self.connection.commit()
            
            return rows_affected > 0
            
        except Exception as e:
            self.logger.error(f"Error actualizando en {table}: {str(e)}")
            if self.connection:
                self.connection.rollback()
            return False
        finally:
            if 'cursor' in locals():
                cursor.close() 