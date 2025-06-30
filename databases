"""
Gestor de base de datos para la aplicación
"""
import psycopg2
import psycopg2.extras
from datetime import datetime
from typing import Optional, List, Dict, Any
import hashlib

class DatabaseManager:
    """Gestor de base de datos PostgreSQL"""
    
    def __init__(self, host: str = "localhost", port: int = 5432, 
                 user: str = "postgres", password: str = "ubuntu", 
                 database: str = "Escaner"):
        """
        Inicializa el gestor de base de datos
        
        Args:
            host: Host de la base de datos
            port: Puerto de la base de datos
            user: Usuario de la base de datos
            password: Contraseña de la base de datos
            database: Nombre de la base de datos
        """
        self.config = {
            "host": host,
            "port": port,
            "user": user,
            "password": password,
            "database": database
        }
        self.connection = None
    
    def connect(self) -> bool:
        """
        Establece conexión con la base de datos
        
        Returns:
            bool: True si la conexión fue exitosa
        """
        try:
            self.connection = psycopg2.connect(**self.config)
            return True
        except Exception as e:
            print(f"Error conectando a la base de datos: {str(e)}")
            return False
    
    def disconnect(self):
        """Cierra la conexión con la base de datos"""
        if self.connection:
            self.connection.close()
            self.connection = None
    
    def execute_query(self, query: str, params: tuple = None, fetch: bool = True) -> List[Dict]:
        """
        Ejecuta una consulta SQL
        
        Args:
            query: Consulta SQL
            params: Parámetros de la consulta
            fetch: Si se debe obtener el resultado
            
        Returns:
            List[Dict]: Resultado de la consulta
        """
        try:
            if not self.connection or self.connection.closed:
                if not self.connect():
                    return []
            
            cursor = self.connection.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
            
            if params:
                cursor.execute(query, params)
            else:
                cursor.execute(query)
            
            if fetch:
                result = cursor.fetchall()
                return [dict(row) for row in result]
            else:
                self.connection.commit()
                return []
                
        except Exception as e:
            print(f"Error ejecutando consulta: {str(e)}")
            if self.connection:
                self.connection.rollback()
            return []
        finally:
            if 'cursor' in locals():
                cursor.close()
    
    def insert_one(self, table: str, data: Dict) -> Optional[int]:
        """
        Inserta un registro en una tabla
        
        Args:
            table: Nombre de la tabla
            data: Datos a insertar
            
        Returns:
            Optional[int]: ID del registro insertado
        """
        try:
            if not self.connection or self.connection.closed:
                if not self.connect():
                    return None
            
            cursor = self.connection.cursor()
            
            # Construir consulta de inserción
            columns = list(data.keys())
            values = list(data.values())
            placeholders = ['%s'] * len(values)
            
            query = f"""
                INSERT INTO {table} ({', '.join(columns)})
                VALUES ({', '.join(placeholders)})
                RETURNING id
            """
            
            cursor.execute(query, values)
            result = cursor.fetchone()
            
            self.connection.commit()
            
            return result[0] if result else None
            
        except Exception as e:
            print(f"Error insertando registro: {str(e)}")
            if self.connection:
                self.connection.rollback()
            return None
        finally:
            if 'cursor' in locals():
                cursor.close()
    
    def update_one(self, table: str, data: Dict, condition: Dict) -> bool:
        """
        Actualiza un registro en una tabla
        
        Args:
            table: Nombre de la tabla
            data: Datos a actualizar
            condition: Condición para la actualización
            
        Returns:
            bool: True si la actualización fue exitosa
        """
        try:
            if not self.connection or self.connection.closed:
                if not self.connect():
                    return False
            
            cursor = self.connection.cursor()
            
            # Construir consulta de actualización
            set_clause = ', '.join([f"{key} = %s" for key in data.keys()])
            where_clause = ' AND '.join([f"{key} = %s" for key in condition.keys()])
            
            query = f"""
                UPDATE {table}
                SET {set_clause}
                WHERE {where_clause}
            """
            
            values = list(data.values()) + list(condition.values())
            
            cursor.execute(query, values)
            rows_affected = cursor.rowcount
            
            self.connection.commit()
            
            return rows_affected > 0
            
        except Exception as e:
            print(f"Error actualizando registro: {str(e)}")
            if self.connection:
                self.connection.rollback()
            return False
        finally:
            if 'cursor' in locals():
                cursor.close()
    
    def delete_one(self, table: str, condition: Dict) -> bool:
        """
        Elimina un registro de una tabla
        
        Args:
            table: Nombre de la tabla
            condition: Condición para la eliminación
            
        Returns:
            bool: True si la eliminación fue exitosa
        """
        try:
            if not self.connection or self.connection.closed:
                if not self.connect():
                    return False
            
            cursor = self.connection.cursor()
            
            # Construir consulta de eliminación
            where_clause = ' AND '.join([f"{key} = %s" for key in condition.keys()])
            
            query = f"""
                DELETE FROM {table}
                WHERE {where_clause}
            """
            
            values = list(condition.values())
            
            cursor.execute(query, values)
            rows_affected = cursor.rowcount
            
            self.connection.commit()
            
            return rows_affected > 0
            
        except Exception as e:
            print(f"Error eliminando registro: {str(e)}")
            if self.connection:
                self.connection.rollback()
            return False
        finally:
            if 'cursor' in locals():
                cursor.close()
    
    def create_tables(self):
        """Crea las tablas necesarias si no existen"""
        try:
            # Tabla de usuarios
            usuarios_query = """
                CREATE TABLE IF NOT EXISTS usuarios (
                    id SERIAL PRIMARY KEY,
                    usuario VARCHAR(50) UNIQUE NOT NULL,
                    contraseña VARCHAR(255) NOT NULL,
                    rol VARCHAR(20) DEFAULT 'usuario',
                    activo BOOLEAN DEFAULT TRUE,
                    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """
            
            # Tabla de códigos e items
            codigos_items_query = """
                CREATE TABLE IF NOT EXISTS codigos_items (
                    id SERIAL PRIMARY KEY,
                    codigo_barras VARCHAR(50) NOT NULL,
                    item VARCHAR(20) NOT NULL,
                    resultado TEXT,
                    fecha_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE(codigo_barras, item)
                )
            """
            
            # Tabla de capturas
            capturas_query = """
                CREATE TABLE IF NOT EXISTS capturas (
                    id SERIAL PRIMARY KEY,
                    codigo VARCHAR(50) NOT NULL,
                    item VARCHAR(20) NOT NULL,
                    motivo VARCHAR(100) NOT NULL,
                    cumple VARCHAR(20) NOT NULL,
                    usuario VARCHAR(50) NOT NULL,
                    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE(codigo, item)
                )
            """
            
            # Tabla de configuración
            configuracion_query = """
                CREATE TABLE IF NOT EXISTS configuracion (
                    id SERIAL PRIMARY KEY,
                    clave VARCHAR(100) UNIQUE NOT NULL,
                    valor TEXT,
                    descripcion TEXT,
                    fecha_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """
            
            # Tabla de logs
            logs_query = """
                CREATE TABLE IF NOT EXISTS logs_aplicacion (
                    id SERIAL PRIMARY KEY,
                    nivel VARCHAR(20) NOT NULL,
                    mensaje TEXT NOT NULL,
                    usuario VARCHAR(50),
                    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """
            
            # Ejecutar consultas
            self.execute_query(usuarios_query, fetch=False)
            self.execute_query(codigos_items_query, fetch=False)
            self.execute_query(capturas_query, fetch=False)
            self.execute_query(configuracion_query, fetch=False)
            self.execute_query(logs_query, fetch=False)
            
            print("Tablas creadas exitosamente")
            
        except Exception as e:
            print(f"Error creando tablas: {str(e)}")
    
    def insert_default_data(self):
        """Inserta datos por defecto"""
        try:
            # Hash de la contraseña 'admin123'
            contraseña_hash = hashlib.sha256('admin123'.encode()).hexdigest()
            # Hash de la contraseña para superadmin (elige una contraseña fuerte)
            superadmin_pass = 'SuperAdmin2024!'
            superadmin_hash = hashlib.sha256(superadmin_pass.encode()).hexdigest()
            
            # Insertar usuario administrador por defecto
            admin_query = """
                INSERT INTO usuarios (usuario, contraseña, rol, activo)
                VALUES (%s, %s, 'admin', TRUE)
                ON CONFLICT (usuario) DO UPDATE SET 
                    contraseña = EXCLUDED.contraseña,
                    rol = EXCLUDED.rol,
                    activo = EXCLUDED.activo
            """
            # Insertar usuario superadmin por defecto
            superadmin_query = """
                INSERT INTO usuarios (usuario, contraseña, rol, activo)
                VALUES (%s, %s, 'superadmin', TRUE)
                ON CONFLICT (usuario) DO NOTHING
            """
            # Insertar configuración por defecto
            config_query = """
                INSERT INTO configuracion (clave, valor, descripcion)
                VALUES 
                ('url_actualizaciones', 'http://localhost:8000/updates', 'URL del servidor de actualizaciones'),
                ('auto_actualizar', 'true', 'Habilitar actualizaciones automáticas')
                ON CONFLICT (clave) DO NOTHING
            """
            self.execute_query(admin_query, ('admin', contraseña_hash), fetch=False)
            self.execute_query(superadmin_query, ('superadmin', superadmin_hash), fetch=False)
            self.execute_query(config_query, fetch=False)
            print("Datos por defecto insertados")
            print("Usuario admin creado con contraseña: admin123")
            print("Usuario superadmin creado con contraseña: SuperAdmin2024!")
        except Exception as e:
            print(f"Error insertando datos por defecto: {str(e)}")
    
    def test_connection(self) -> bool:
        """
        Prueba la conexión a la base de datos
        
        Returns:
            bool: True si la conexión es exitosa
        """
        try:
            if self.connect():
                result = self.execute_query("SELECT 1 as test")
                self.disconnect()
                return len(result) > 0
            return False
        except Exception as e:
            print(f"Error probando conexión: {str(e)}")
            return False 
