"""
Validadores para la aplicación de escáner
"""
import re
import os
import pandas as pd
from typing import Tuple, Dict, Any

class Validators:
    """Clase con métodos de validación para la aplicación"""
    
    @staticmethod
    def validar_codigo_barras(codigo: str) -> Tuple[bool, str]:
        """
        Valida un código de barras
        
        Args:
            codigo: Código de barras a validar
            
        Returns:
            Tuple[bool, str]: (es_válido, mensaje)
        """
        if not codigo:
            return False, "El código de barras no puede estar vacío"
        
        codigo_limpio = str(codigo).strip()
        
        # Verificar longitud mínima
        if len(codigo_limpio) < 8:
            return False, "El código de barras debe tener al menos 8 dígitos"
        
        # Verificar que contenga solo números
        if not codigo_limpio.isdigit():
            return False, "El código de barras debe contener solo números"
        
        return True, "Código de barras válido"
    
    @staticmethod
    def validar_item_code(item: str) -> Tuple[bool, str]:
        """
        Valida un código de item
        
        Args:
            item: Código de item a validar
            
        Returns:
            Tuple[bool, str]: (es_válido, mensaje)
        """
        if not item:
            return False, "El código de item no puede estar vacío"
        
        item_limpio = str(item).strip()
        
        # Verificar longitud mínima
        if len(item_limpio) < 4:
            return False, "El código de item debe tener al menos 4 dígitos"
        
        # Verificar que contenga solo números
        if not item_limpio.isdigit():
            return False, "El código de item debe contener solo números"
        
        return True, "Código de item válido"
    
    @staticmethod
    def validar_usuario(usuario: str) -> Tuple[bool, str]:
        """
        Valida un nombre de usuario
        
        Args:
            usuario: Nombre de usuario a validar
            
        Returns:
            Tuple[bool, str]: (es_válido, mensaje)
        """
        if not usuario:
            return False, "El nombre de usuario no puede estar vacío"
        
        usuario_limpio = str(usuario).strip()
        
        # Verificar longitud
        if len(usuario_limpio) < 3:
            return False, "El nombre de usuario debe tener al menos 3 caracteres"
        
        if len(usuario_limpio) > 20:
            return False, "El nombre de usuario no puede tener más de 20 caracteres"
        
        # Verificar caracteres válidos
        if not re.match(r'^[a-zA-Z0-9_]+$', usuario_limpio):
            return False, "El nombre de usuario solo puede contener letras, números y guiones bajos"
        
        return True, "Nombre de usuario válido"
    
    @staticmethod
    def validar_contraseña(contraseña: str) -> Tuple[bool, str]:
        """
        Valida una contraseña
        
        Args:
            contraseña: Contraseña a validar
            
        Returns:
            Tuple[bool, str]: (es_válido, mensaje)
        """
        if not contraseña:
            return False, "La contraseña no puede estar vacía"
        
        # Verificar longitud mínima
        if len(contraseña) < 6:
            return False, "La contraseña debe tener al menos 6 caracteres"
        
        return True, "Contraseña válida"
    
    @staticmethod
    def validar_archivo_excel(ruta: str) -> Tuple[bool, str]:
        """
        Valida un archivo Excel
        
        Args:
            ruta: Ruta del archivo a validar
            
        Returns:
            Tuple[bool, str]: (es_válido, mensaje)
        """
        if not ruta:
            return False, "La ruta del archivo no puede estar vacía"
        
        # Verificar que el archivo existe
        if not os.path.exists(ruta):
            return False, "El archivo no existe"
        
        # Verificar extensión
        extension = os.path.splitext(ruta)[1].lower()
        if extension not in ['.xls', '.xlsx']:
            return False, "El archivo debe ser un archivo Excel (.xls o .xlsx)"
        
        # Verificar que se puede leer
        try:
            df = pd.read_excel(ruta, nrows=1)
            if df.empty:
                return False, "El archivo está vacío"
        except Exception as e:
            return False, f"No se puede leer el archivo: {str(e)}"
        
        return True, "Archivo Excel válido"
    
    @staticmethod
    def limpiar_codigo_barras(codigo: str) -> str:
        """
        Limpia un código de barras eliminando espacios y caracteres no numéricos
        
        Args:
            codigo: Código de barras a limpiar
            
        Returns:
            str: Código de barras limpio
        """
        if not codigo:
            return ""
        
        # Eliminar espacios y caracteres no numéricos
        codigo_limpio = re.sub(r'\D', '', str(codigo))
        
        return codigo_limpio
    
    @staticmethod
    def limpiar_item_code(item: str) -> str:
        """
        Limpia un código de item eliminando espacios y ceros a la izquierda
        
        Args:
            item: Código de item a limpiar
            
        Returns:
            str: Código de item limpio
        """
        if not item:
            return ""
        
        # Eliminar espacios y caracteres no numéricos
        item_limpio = re.sub(r'\D', '', str(item))
        
        # Eliminar ceros a la izquierda
        item_limpio = item_limpio.lstrip('0')
        
        return item_limpio if item_limpio else "0"
    
    @staticmethod
    def validar_motivo(motivo: str) -> Tuple[bool, str]:
        """Valida un motivo de captura"""
        motivos_validos = [
            "Instrucciones de cuidado",
            "Insumos",
            "Pais de origen",
            "Talla",
            "Importador",
            "Marca",
            "Caracteristícas Electricas",
            "Edad Recomendada",
            "Unidades de Medida"
        ]
        
        if not motivo or not motivo.strip():
            return False, "El motivo no puede estar vacío"
        
        if motivo.strip() not in motivos_validos:
            return False, f"El motivo debe ser uno de: {', '.join(motivos_validos)}"
        
        return True, "Motivo válido"
    
    @staticmethod
    def validar_cumple(cumple: str) -> Tuple[bool, str]:
        """Valida el campo cumple/no cumple"""
        valores_validos = ["CUMPLE", "NO CUMPLE"]
        
        if not cumple or not cumple.strip():
            return False, "El campo cumple no puede estar vacío"
        
        if cumple.strip() not in valores_validos:
            return False, "El valor debe ser 'CUMPLE' o 'NO CUMPLE'"
        
        return True, "Valor válido"
    
    @staticmethod
    def validar_rol(rol: str) -> Tuple[bool, str]:
        """Valida un rol de usuario"""
        roles_validos = ["admin", "captura", "usuario"]
        
        if not rol or not rol.strip():
            return False, "El rol no puede estar vacío"
        
        if rol.strip() not in roles_validos:
            return False, f"El rol debe ser uno de: {', '.join(roles_validos)}"
        
        return True, "Rol válido"
    
    @staticmethod
    def validar_fecha(fecha_str: str) -> Tuple[bool, str]:
        """Valida una fecha en formato string"""
        try:
            datetime.strptime(fecha_str, '%Y-%m-%d')
            return True, "Fecha válida"
        except ValueError:
            return False, "La fecha debe estar en formato YYYY-MM-DD"
    
    # @staticmethod
    # def validar_email(email: str) -> Tuple[bool, str]:
    #     """Valida un email - NO UTILIZADO EN LA APLICACIÓN ACTUAL"""
    #     if not email or not email.strip():
    #         return False, "El email no puede estar vacío"
    #     
    #     email_limpio = email.strip()
    #     
    #     # Patrón básico para validar email
    #     patron = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    #     
    #     if not re.match(patron, email_limpio):
    #         return False, "El formato del email no es válido"
    #     
    #     return True, "Email válido"
    
    @staticmethod
    def validar_configuracion_completa(config: Dict[str, Any]) -> Tuple[bool, str]:
        """Valida que la configuración esté completa - ADAPTADO PARA LA APLICACIÓN ACTUAL"""
        # En la aplicación actual, no hay campos específicos requeridos
        # Esta función se mantiene por compatibilidad pero siempre retorna True
        return True, "Configuración válida" 