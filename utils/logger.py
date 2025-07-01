"""
Logger para la aplicación de escáner
"""
import logging
import os
from datetime import datetime
from typing import Optional

class AppLogger:
    """Clase para manejo de logs de la aplicación"""
    
    def __init__(self, nombre_app: str = "EscanerApp"):
        """
        Inicializa el logger
        
        Args:
            nombre_app: Nombre de la aplicación
        """
        self.nombre_app = nombre_app
        self.logger = logging.getLogger(nombre_app)
        self.logger.setLevel(logging.INFO)
        
        # Crear directorio de logs si no existe
        self.logs_dir = os.path.join(os.path.dirname(__file__), "..", "logs")
        os.makedirs(self.logs_dir, exist_ok=True)
        
        # Configurar handler para archivo
        self._configurar_handler_archivo()
        
        # Configurar handler para consola
        self._configurar_handler_consola()
    
    def _configurar_handler_archivo(self):
        """Configura el handler para escribir en archivo"""
        # Nombre del archivo con fecha
        fecha_actual = datetime.now().strftime("%Y%m%d")
        archivo_log = os.path.join(self.logs_dir, f"escaner_{fecha_actual}.log")
        
        # Crear handler
        file_handler = logging.FileHandler(archivo_log, encoding='utf-8')
        file_handler.setLevel(logging.INFO)
        
        # Formato
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        file_handler.setFormatter(formatter)
        
        # Agregar handler
        self.logger.addHandler(file_handler)
    
    def _configurar_handler_consola(self):
        """Configura el handler para escribir en consola"""
        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.INFO)
        
        # Formato
        formatter = logging.Formatter(
            '%(asctime)s - %(levelname)s - %(message)s'
        )
        console_handler.setFormatter(formatter)
        
        # Agregar handler
        self.logger.addHandler(console_handler)
    
    def info(self, mensaje: str):
        """Registra un mensaje de información"""
        self.logger.info(mensaje)
    
    def error(self, mensaje: str):
        """Registra un mensaje de error"""
        self.logger.error(mensaje)
    
    def warning(self, mensaje: str):
        """Registra un mensaje de advertencia"""
        self.logger.warning(mensaje)
    
    def debug(self, mensaje: str):
        """Registra un mensaje de debug"""
        self.logger.debug(mensaje)
    
    def log_user_action(self, usuario: str, accion: str, detalles: Optional[str] = None):
        """
        Registra una acción del usuario
        
        Args:
            usuario: Nombre del usuario
            accion: Acción realizada
            detalles: Detalles adicionales (opcional)
        """
        mensaje = f"Usuario: {usuario} - Acción: {accion}"
        if detalles:
            mensaje += f" - Detalles: {detalles}"
        
        self.info(mensaje)
    
    def log_login(self, usuario: str, exitoso: bool, ip: Optional[str] = None):
        """
        Registra un intento de login
        
        Args:
            usuario: Nombre del usuario
            exitoso: Si el login fue exitoso
            ip: Dirección IP (opcional)
        """
        estado = "EXITOSO" if exitoso else "FALLIDO"
        mensaje = f"Login {estado} - Usuario: {usuario}"
        if ip:
            mensaje += f" - IP: {ip}"
        
        if exitoso:
            self.info(mensaje)
        else:
            self.warning(mensaje)
    
    def log_error_sistema(self, error: str, contexto: Optional[str] = None):
        """
        Registra un error del sistema
        
        Args:
            error: Descripción del error
            contexto: Contexto adicional (opcional)
        """
        mensaje = f"Error del sistema: {error}"
        if contexto:
            mensaje += f" - Contexto: {contexto}"
        
        self.error(mensaje)
    
    def log_actualizacion(self, version: str, exitoso: bool, detalles: Optional[str] = None):
        """
        Registra una actualización
        
        Args:
            version: Versión de la actualización
            exitoso: Si la actualización fue exitosa
            detalles: Detalles adicionales (opcional)
        """
        estado = "EXITOSA" if exitoso else "FALLIDA"
        mensaje = f"Actualización {estado} - Versión: {version}"
        if detalles:
            mensaje += f" - Detalles: {detalles}"
        
        if exitoso:
            self.info(mensaje)
        else:
            self.error(mensaje) 