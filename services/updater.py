"""
Servicio de actualizaciones para la aplicación
"""
import os
import json
import requests
import zipfile
import shutil
from datetime import datetime
from typing import Dict, List, Optional, Callable
import threading

class UpdaterService:
    """Servicio para manejar actualizaciones de la aplicación"""
    
    def __init__(self, url_base: str = "http://localhost:8000"):
        """
        Inicializa el servicio de actualizaciones
        
        Args:
            url_base: URL base del servidor de actualizaciones
        """
        self.url_base = url_base
        self.cancelar_flag = False
        self.descarga_actual = None
        
    def verificar_actualizacion(self) -> Dict:
        """
        Verifica si hay una actualización disponible
        
        Returns:
            Dict: Información de la actualización
        """
        try:
            # Simular verificación (en producción esto haría una petición HTTP)
            # Por ahora retornamos que no hay actualización
            return {
                'hay_actualizacion': False,
                'version': None,
                'tamaño': None,
                'descripcion': None,
                'url_descarga': None
            }
            
        except Exception as e:
            return {
                'hay_actualizacion': False,
                'error': str(e)
            }
    
    def descargar_actualizacion(self, callback_progreso: Optional[Callable] = None) -> Dict:
        """
        Descarga la actualización
        
        Args:
            callback_progreso: Función para reportar progreso
            
        Returns:
            Dict: Resultado de la descarga
        """
        try:
            self.cancelar_flag = False
            
            if callback_progreso:
                callback_progreso(0.1, "Iniciando descarga...")
            
            # Simular descarga (en producción descargaría el archivo)
            for i in range(1, 11):
                if self.cancelar_flag:
                    return {'exito': False, 'error': 'Descarga cancelada'}
                
                if callback_progreso:
                    progreso = i / 10
                    callback_progreso(progreso, f"Descargando... {i*10}%")
                
                # Simular tiempo de descarga
                import time
                time.sleep(0.5)
            
            if callback_progreso:
                callback_progreso(1.0, "Descarga completada")
            
            return {'exito': True}
            
        except Exception as e:
            return {'exito': False, 'error': str(e)}
    
    def instalar_actualizacion(self) -> Dict:
        """
        Instala la actualización descargada
        
        Returns:
            Dict: Resultado de la instalación
        """
        try:
            # Simular instalación
            # En producción esto:
            # 1. Hace backup de la aplicación actual
            # 2. Extrae la nueva versión
            # 3. Reemplaza archivos
            # 4. Reinicia la aplicación
            
            return {'exito': True}
            
        except Exception as e:
            return {'exito': False, 'error': str(e)}
    
    def cancelar_actualizacion(self):
        """Cancela la actualización en curso"""
        self.cancelar_flag = True
    
    def obtener_historial_actualizaciones(self) -> List[Dict]:
        """
        Obtiene el historial de actualizaciones
        
        Returns:
            List[Dict]: Lista de actualizaciones
        """
        try:
            # Simular historial (en producción obtendría de BD)
            return [
                {
                    'version': '3.0.0',
                    'fecha': '2025-01-28',
                    'estado': 'Instalada',
                    'descripcion': 'Versión inicial de la nueva arquitectura'
                },
                {
                    'version': '2.1.0',
                    'fecha': '2025-01-20',
                    'estado': 'Instalada',
                    'descripcion': 'Mejoras en la interfaz de usuario'
                }
            ]
            
        except Exception as e:
            return []
    
    def hacer_backup(self) -> bool:
        """
        Hace un backup de la aplicación actual
        
        Returns:
            bool: True si el backup fue exitoso
        """
        try:
            # Crear directorio de backups si no existe
            backup_dir = os.path.join(os.path.dirname(__file__), "..", "backups")
            os.makedirs(backup_dir, exist_ok=True)
            
            # Nombre del backup con timestamp
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            backup_name = f"backup_{timestamp}.zip"
            backup_path = os.path.join(backup_dir, backup_name)
            
            # Crear archivo ZIP con la aplicación actual
            with zipfile.ZipFile(backup_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
                # Agregar archivos de la aplicación (excluyendo algunos directorios)
                app_dir = os.path.dirname(__file__)
                for root, dirs, files in os.walk(app_dir):
                    # Excluir directorios específicos
                    dirs[:] = [d for d in dirs if d not in ['__pycache__', 'logs', 'backups']]
                    
                    for file in files:
                        if not file.endswith('.pyc'):
                            file_path = os.path.join(root, file)
                            arcname = os.path.relpath(file_path, app_dir)
                            zipf.write(file_path, arcname)
            
            return True
            
        except Exception as e:
            print(f"Error haciendo backup: {str(e)}")
            return False
    
    def restaurar_backup(self, backup_path: str) -> bool:
        """
        Restaura un backup
        
        Args:
            backup_path: Ruta al archivo de backup
            
        Returns:
            bool: True si la restauración fue exitosa
        """
        try:
            # Extraer backup
            app_dir = os.path.dirname(__file__)
            
            with zipfile.ZipFile(backup_path, 'r') as zipf:
                zipf.extractall(app_dir)
            
            return True
            
        except Exception as e:
            print(f"Error restaurando backup: {str(e)}")
            return False
    
    def obtener_ultima_version(self) -> Optional[str]:
        """
        Obtiene la última versión disponible
        
        Returns:
            Optional[str]: Última versión o None
        """
        try:
            # En producción haría una petición HTTP
            # Por ahora retorna None
            return None
            
        except Exception as e:
            print(f"Error obteniendo última versión: {str(e)}")
            return None
    
    def auto_update_enabled(self, db_manager=None):
        """Lee la configuración de la base de datos para saber si las actualizaciones automáticas están habilitadas"""
        try:
            if db_manager is None:
                return False
            result = db_manager.execute_query(
                "SELECT valor FROM configuracion WHERE clave = 'auto_actualizar'"
            )
            if result and result[0]['valor'].lower() == 'true':
                return True
            return False
        except Exception as e:
            print(f"Error leyendo configuración de auto_actualizar: {str(e)}")
            return False 