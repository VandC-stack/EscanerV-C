"""
Gestor de base de datos para la aplicación
"""
import psycopg2
import psycopg2.extras
from datetime import datetime
from typing import Optional, List, Dict, Any
import hashlib
import json
import os

class DatabaseManager:
    """Gestor de base de datos PostgreSQL"""
    
    def __init__(self, host: str = None, port: int = None, 
                 user: str = None, password: str = None, 
                 database: str = None):
        """
        Inicializa el gestor de base de datos
        
        Args:
            host: Host de la base de datos
            port: Puerto de la base de datos
            user: Usuario de la base de datos
            password: Contraseña de la base de datos
            database: Nombre de la base de datos
        """
        # Cargar configuración desde archivo o usar valores por defecto
        self.config = self._load_database_config()
        
        # Sobrescribir con parámetros proporcionados
        if host:
            self.config["host"] = host
        if port:
            self.config["port"] = port
        if user:
            self.config["user"] = user
        if password:
            self.config["password"] = password
        if database:
            self.config["database"] = database
            
        self.connection = None
    
    def _load_database_config(self) -> Dict:
        """
        Carga la configuración de la base de datos desde archivo
        
        Returns:
            Dict: Configuración de la base de datos
        """
        config_file = "database_config.json"
        default_config = {
            "host": "localhost",
            "port": 5432,
            "user": "postgres",
            "password": "ubuntu",
            "database": "Escaner"
        }
        
        try:
            if os.path.exists(config_file):
                # Intentar leer con diferentes codificaciones
                for encoding in ['utf-8', 'latin1', 'cp1252']:
                    try:
                        with open(config_file, 'r', encoding=encoding) as f:
                            file_config = json.load(f)
                            # Limpiar valores de configuración
                            cleaned_config = {}
                            for key, value in file_config.items():
                                if isinstance(value, str):
                                    cleaned_config[key] = self._clean_connection_param(value)
                                else:
                                    cleaned_config[key] = value
                            
                            # Combinar configuración por defecto con archivo limpio
                            default_config.update(cleaned_config)
                            print(f"Configuración cargada desde {config_file} con encoding {encoding}")
                            break
                    except Exception as read_error:
                        print(f"Error leyendo con {encoding}: {str(read_error)}")
                        continue
                else:
                    # Si todos los encodings fallaron, crear nuevo archivo
                    print("No se pudo leer el archivo de configuración. Creando nuevo...")
                    self._create_default_config(config_file, default_config)
            else:
                # Crear archivo de configuración por defecto
                self._create_default_config(config_file, default_config)
                print(f"Archivo de configuración creado: {config_file}")
                
        except Exception as e:
            print(f"Error cargando configuración: {str(e)}")
            print("Usando configuración por defecto")
        
        return default_config
    
    def _create_default_config(self, config_file: str, config: Dict):
        """
        Crea un archivo de configuración por defecto
        
        Args:
            config_file: Nombre del archivo de configuración
            config: Configuración por defecto
        """
        try:
            # Limpiar configuración antes de guardar
            cleaned_config = {}
            for key, value in config.items():
                if isinstance(value, str):
                    cleaned_config[key] = self._clean_connection_param(value)
                else:
                    cleaned_config[key] = value
            
            with open(config_file, 'w', encoding='utf-8') as f:
                json.dump(cleaned_config, f, indent=4, ensure_ascii=True)
            print(f"Archivo de configuración limpio creado: {config_file}")
        except Exception as e:
            print(f"Error creando archivo de configuración: {str(e)}")
    
    def connect(self) -> bool:
        """
        Establece conexión con la base de datos
        
        Returns:
            bool: True si la conexión fue exitosa
        """
        try:
            # Configuración específica para manejar el error 0xab
            connection_params = self.config.copy()
            
            # Limpiar parámetros de conexión de caracteres problemáticos
            for key, value in connection_params.items():
                if isinstance(value, str):
                    connection_params[key] = self._clean_connection_param(value)
            
            # Usar Latin1 que es más permisivo con caracteres problemáticos
            connection_params['client_encoding'] = 'LATIN1'
            
            print(f"Intentando conexión con encoding LATIN1...")
            
            self.connection = psycopg2.connect(**connection_params)
            
            # Una vez conectado, intentar cambiar a UTF8
            try:
                self.connection.set_client_encoding('UTF8')
                print("Codificación cambiada a UTF8 exitosamente")
            except Exception as encoding_error:
                print(f"No se pudo cambiar a UTF8: {str(encoding_error)}")
                # Mantener LATIN1 si no se puede cambiar
                pass
            
            print("Conexión exitosa")
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
            
            # Manejar parámetros con codificación segura
            if params:
                # Convertir parámetros a UTF-8 si son strings
                safe_params = []
                for param in params:
                    if isinstance(param, str):
                        try:
                            # Intentar múltiples codificaciones para limpiar caracteres problemáticos
                            safe_param = self._clean_string(param)
                            safe_params.append(safe_param)
                        except Exception as clean_error:
                            print(f"Error limpiando parámetro: {clean_error}")
                            safe_params.append(param)
                    else:
                        safe_params.append(param)
                cursor.execute(query, tuple(safe_params))
            else:
                cursor.execute(query)
            
            if fetch:
                result = cursor.fetchall()
                # Limpiar resultados de caracteres problemáticos
                cleaned_result = []
                for row in result:
                    cleaned_row = {}
                    for key, value in row.items():
                        if isinstance(value, str):
                            try:
                                cleaned_value = self._clean_string(value)
                                cleaned_row[key] = cleaned_value
                            except Exception as clean_error:
                                print(f"Error limpiando resultado: {clean_error}")
                                cleaned_row[key] = value
                        else:
                            cleaned_row[key] = value
                    cleaned_result.append(cleaned_row)
                return cleaned_result
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
                    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    ultimo_acceso TIMESTAMP
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
            
            # Tabla de items
            items_query = """
                CREATE TABLE IF NOT EXISTS items (
                    id SERIAL PRIMARY KEY,
                    item VARCHAR(20) UNIQUE NOT NULL,
                    resultado TEXT,
                    fecha_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """
            
            # Tabla de códigos de barra
            codigos_barras_query = """
                CREATE TABLE IF NOT EXISTS codigos_barras (
                    id SERIAL PRIMARY KEY,
                    codigo_barras VARCHAR(50) UNIQUE NOT NULL,
                    item_id INTEGER NOT NULL REFERENCES items(id)
                )
            """
            
            # Tabla de consultas
            consultas_query = """
                CREATE TABLE IF NOT EXISTS consultas (
                    id SERIAL PRIMARY KEY,
                    usuario VARCHAR(50) NOT NULL,
                    codigo_barras VARCHAR(50) NOT NULL,
                    item_id INTEGER,
                    fecha_hora TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    resultado TEXT
                )
            """
            
            # Tabla de cargas de CLP
            clp_cargas_query = """
                CREATE TABLE IF NOT EXISTS clp_cargas (
                    id SERIAL PRIMARY KEY,
                    archivo VARCHAR(255) NOT NULL,
                    usuario VARCHAR(50) NOT NULL,
                    fecha_carga TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    codigos_agregados INTEGER DEFAULT 0
                )
            """
            
            # Ejecutar consultas
            self.execute_query(usuarios_query, fetch=False)
            self.execute_query(codigos_items_query, fetch=False)
            self.execute_query(capturas_query, fetch=False)
            self.execute_query(configuracion_query, fetch=False)
            self.execute_query(logs_query, fetch=False)
            self.execute_query(items_query, fetch=False)
            self.execute_query(codigos_barras_query, fetch=False)
            self.execute_query(consultas_query, fetch=False)
            self.execute_query(clp_cargas_query, fetch=False)
            
            # Agregar columna ultimo_acceso si no existe
            try:
                self.execute_query("ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS ultimo_acceso TIMESTAMP", fetch=False)
            except Exception as e:
                print(f"Advertencia: No se pudo agregar columna ultimo_acceso: {str(e)}")
            
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
    
    def _clean_connection_param(self, text: str) -> str:
        """
        Limpia parámetros de conexión de caracteres problemáticos
        
        Args:
            text: Texto a limpiar
            
        Returns:
            str: Texto limpio
        """
        if not isinstance(text, str):
            return text
            
        try:
            # Método más agresivo para parámetros de conexión
            # Convertir a bytes y filtrar caracteres problemáticos
            text_bytes = text.encode('latin1', errors='ignore')
            
            # Solo mantener caracteres ASCII seguros para conexión
            safe_bytes = bytearray()
            for byte in text_bytes:
                if byte in range(32, 127):  # Solo ASCII imprimible
                    safe_bytes.append(byte)
            
            # Convertir de vuelta a string
            cleaned = safe_bytes.decode('ascii', errors='ignore')
            return cleaned
            
        except Exception as e:
            print(f"Error limpiando parámetro de conexión: {str(e)}")
            return text
    
    def _clean_string(self, text: str) -> str:
        """
        Limpia una cadena de texto de caracteres problemáticos
        
        Args:
            text: Texto a limpiar
            
        Returns:
            str: Texto limpio
        """
        if not isinstance(text, str):
            return text
            
        try:
            # Solo limpiar caracteres específicamente problemáticos
            problematic_chars = {
                '\xab': '',  # Left-pointing double angle quotation mark
                '\xbb': '',  # Right-pointing double angle quotation mark
                '\xbf': '',  # Inverted question mark
                '\xef': '',  # Latin small letter i with diaeresis
                '\xbb': '',  # Right-pointing double angle quotation mark
                '\xbf': '',  # Inverted question mark
            }
            
            cleaned = text
            for char, replacement in problematic_chars.items():
                cleaned = cleaned.replace(char, replacement)
            
            # Si no hay cambios, devolver el texto original
            if cleaned == text:
                return text
            
            # Verificar que el texto limpio sea válido UTF-8
            try:
                cleaned.encode('utf-8')
                return cleaned
            except UnicodeEncodeError:
                # Si aún hay problemas, usar método más conservador
                return text.encode('utf-8', errors='ignore').decode('utf-8', errors='ignore')
            
        except Exception as e:
            print(f"Error limpiando string: {str(e)}")
            return text  # Devolver original si hay error
    
    def fix_encoding_issues(self) -> bool:
        """
        Intenta arreglar problemas de codificación en la base de datos
        
        Returns:
            bool: True si se pudo arreglar
        """
        try:
            if not self.connect():
                return False
            
            # Verificar codificación actual
            cursor = self.connection.cursor()
            cursor.execute("SHOW client_encoding")
            current_encoding = cursor.fetchone()[0]
            print(f"Codificación actual del cliente: {current_encoding}")
            
            cursor.execute("SHOW server_encoding")
            server_encoding = cursor.fetchone()[0]
            print(f"Codificación del servidor: {server_encoding}")
            
            # Solo limpiar si hay problemas específicos de codificación
            if self._detect_encoding_problems():
                print("Problemas de codificación detectados. Iniciando limpieza...")
                self._clean_database_data()
            else:
                print("No se detectaron problemas de codificación. Saltando limpieza.")
            
            cursor.close()
            return True
            
        except Exception as e:
            print(f"Error arreglando codificación: {str(e)}")
            return False
        finally:
            if self.connection:
                self.disconnect()
    
    def _detect_encoding_problems(self) -> bool:
        """
        Detecta si hay problemas de codificación en la base de datos
        
        Returns:
            bool: True si se detectan problemas
        """
        try:
            cursor = self.connection.cursor()
            
            # Buscar caracteres problemáticos específicos
            problematic_chars = ['\xab', '\xbb', '\xbf', '\xef']  # Caracteres problemáticos comunes
            
            for char in problematic_chars:
                # Buscar en tablas principales
                tables_to_check = ['codigos_items', 'capturas', 'usuarios']
                
                for table in tables_to_check:
                    try:
                        cursor.execute(f"SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = '{table}')")
                        if cursor.fetchone()[0]:
                            # Buscar columnas de texto
                            cursor.execute(f"""
                                SELECT column_name 
                                FROM information_schema.columns 
                                WHERE table_name = '{table}' 
                                AND data_type IN ('character varying', 'text', 'character')
                            """)
                            columns = cursor.fetchall()
                            
                            for (column_name,) in columns:
                                # Buscar caracteres problemáticos
                                cursor.execute(f"SELECT COUNT(*) FROM {table} WHERE {column_name} LIKE %s", (f'%{char}%',))
                                count = cursor.fetchone()[0]
                                if count > 0:
                                    print(f"Problema detectado: {count} registros con caracteres problemáticos en {table}.{column_name}")
                                    return True
                    except Exception:
                        continue
            
            return False
            
        except Exception as e:
            print(f"Error detectando problemas de codificación: {str(e)}")
            return False
    
    def _clean_database_data(self):
        """
        Limpia datos problemáticos en la base de datos
        """
        try:
            print("Limpiando datos problemáticos en la base de datos...")
            
            # Tablas a limpiar
            tables_to_clean = [
                'codigos_items',
                'capturas', 
                'usuarios',
                'configuracion',
                'logs_aplicacion',
                'items',
                'codigos_barras',
                'consultas'
            ]
            
            for table in tables_to_clean:
                try:
                    # Verificar si la tabla existe
                    cursor = self.connection.cursor()
                    cursor.execute(f"SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = '{table}')")
                    table_exists = cursor.fetchone()[0]
                    
                    if table_exists:
                        print(f"Limpiando tabla: {table}")
                        # Obtener columnas de texto
                        cursor.execute(f"""
                            SELECT column_name, data_type 
                            FROM information_schema.columns 
                            WHERE table_name = '{table}' 
                            AND data_type IN ('character varying', 'text', 'character')
                        """)
                        text_columns = cursor.fetchall()
                        
                        for column_name, data_type in text_columns:
                            try:
                                # Limpiar datos en esta columna
                                cursor.execute(f"SELECT id, {column_name} FROM {table} WHERE {column_name} IS NOT NULL")
                                rows = cursor.fetchall()
                                
                                for row_id, text_value in rows:
                                    if text_value and isinstance(text_value, str):
                                        cleaned_value = self._clean_string(text_value)
                                        if cleaned_value != text_value:
                                            cursor.execute(f"UPDATE {table} SET {column_name} = %s WHERE id = %s", 
                                                         (cleaned_value, row_id))
                                            print(f"  Limpiado registro {row_id} en columna {column_name}")
                                
                            except Exception as col_error:
                                print(f"  Error limpiando columna {column_name}: {str(col_error)}")
                                continue
                        
                        self.connection.commit()
                        print(f"Tabla {table} limpiada")
                    
                except Exception as table_error:
                    print(f"Error limpiando tabla {table}: {str(table_error)}")
                    continue
            
            print("Limpieza de base de datos completada")
            
        except Exception as e:
            print(f"Error en limpieza de base de datos: {str(e)}")
            if self.connection:
                self.connection.rollback() 