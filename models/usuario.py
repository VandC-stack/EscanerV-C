"""
Modelo de usuario para la aplicación
"""
import hashlib
from datetime import datetime
from typing import Optional, List, Dict

class Usuario:
    """Modelo para manejar usuarios de la aplicación"""
    
    def __init__(self, db_manager):
        """
        Inicializa el modelo de usuario
        
        Args:
            db_manager: Instancia del gestor de base de datos
        """
        self.db = db_manager
    
    def autenticar_usuario(self, usuario: str, contraseña: str) -> Optional[Dict]:
        """
        Autentica un usuario
        
        Args:
            usuario: Nombre de usuario
            contraseña: Contraseña del usuario
            
        Returns:
            Optional[Dict]: Datos del usuario si la autenticación es exitosa
        """
        try:
            # Hash de la contraseña
            contraseña_hash = hashlib.sha256(contraseña.encode()).hexdigest()
            
            # Buscar usuario
            query = """
                SELECT id, usuario, rol, activo, fecha_creacion
                FROM usuarios 
                WHERE usuario = %s AND contraseña = %s AND activo = TRUE
            """
            resultado = self.db.execute_query(query, (usuario, contraseña_hash))
            
            if resultado:
                # Actualizar último acceso
                self.actualizar_ultimo_acceso(usuario)
                return resultado[0]
            
            return None
            
        except Exception as e:
            print(f"Error autenticando usuario: {str(e)}")
            return None
    
    def crear_usuario(self, usuario: str, contraseña: str, rol: str = "usuario", estado: str = "activo") -> bool:
        """
        Crea un nuevo usuario
        Args:
            usuario: Nombre de usuario
            contraseña: Contraseña del usuario
            rol: Rol del usuario
            estado: Estado del usuario ('activo' o 'inactivo')
        Returns:
            bool: True si se creó exitosamente
        """
        try:
            # No permitir crear superadmin desde la interfaz
            if rol == "superadmin":
                return False
            # Verificar que el usuario no exista
            existing = self.db.execute_query(
                "SELECT id FROM usuarios WHERE usuario = %s",
                (usuario,)
            )
            if existing:
                return False
            # Hash de la contraseña
            contraseña_hash = hashlib.sha256(contraseña.encode()).hexdigest()
            # Determinar estado
            activo = True if estado.lower() == "activo" else False
            # Crear usuario
            data = {
                "usuario": usuario,
                "contraseña": contraseña_hash,
                "rol": rol,
                "activo": activo,
                "fecha_creacion": datetime.now()
            }
            self.db.insert_one("usuarios", data)
            return True
        except Exception as e:
            print(f"Error creando usuario: {str(e)}")
            return False
    
    def obtener_usuarios(self) -> List[Dict]:
        """
        Obtiene la lista de usuarios
        
        Returns:
            List[Dict]: Lista de usuarios
        """
        try:
            query = """
                SELECT id, usuario, rol, activo, fecha_creacion, contraseña
                FROM usuarios 
                ORDER BY fecha_creacion DESC
            """
            return self.db.execute_query(query)
            
        except Exception as e:
            print(f"Error obteniendo usuarios: {str(e)}")
            return []
    
    def desactivar_usuario(self, usuario: str) -> bool:
        """
        Desactiva un usuario
        
        Args:
            usuario: Nombre del usuario a desactivar
            
        Returns:
            bool: True si se desactivó exitosamente
        """
        try:
            # No permitir desactivar superadmin
            if usuario == "superadmin":
                return False
            
            # Usar execute_query directamente en lugar de update_one
            self.db.execute_query(
                "UPDATE usuarios SET activo = FALSE WHERE usuario = %s",
                (usuario,),
                fetch=False
            )
            return True
            
        except Exception as e:
            print(f"Error desactivando usuario: {str(e)}")
            return False
    
    def cambiar_contraseña(self, usuario: str, nueva_contraseña: str) -> bool:
        """
        Cambia la contraseña de un usuario
        
        Args:
            usuario: Nombre del usuario
            nueva_contraseña: Nueva contraseña
            
        Returns:
            bool: True si se cambió exitosamente
        """
        try:
            # Hash de la nueva contraseña
            contraseña_hash = hashlib.sha256(nueva_contraseña.encode()).hexdigest()
            
            # Usar execute_query directamente en lugar de update_one
            self.db.execute_query(
                "UPDATE usuarios SET contraseña = %s WHERE usuario = %s",
                (contraseña_hash, usuario),
                fetch=False
            )
            return True
            
        except Exception as e:
            print(f"Error cambiando contraseña: {str(e)}")
            return False
    
    def obtener_usuario_por_id(self, usuario_id: int) -> Optional[Dict]:
        """
        Obtiene un usuario por su ID
        
        Args:
            usuario_id: ID del usuario
            
        Returns:
            Optional[Dict]: Datos del usuario
        """
        try:
            query = """
                SELECT id, usuario, rol, activo, fecha_creacion
                FROM usuarios 
                WHERE id = %s
            """
            resultado = self.db.execute_query(query, (usuario_id,))
            
            if resultado:
                return resultado[0]
            
            return None
            
        except Exception as e:
            print(f"Error obteniendo usuario: {str(e)}")
            return None
    
    def verificar_permiso(self, usuario: str, permiso: str) -> bool:
        """
        Verifica si un usuario tiene un permiso específico
        
        Args:
            usuario: Nombre del usuario
            permiso: Permiso a verificar
            
        Returns:
            bool: True si tiene el permiso
        """
        try:
            # Obtener rol del usuario
            query = "SELECT rol FROM usuarios WHERE usuario = %s AND activo = TRUE"
            resultado = self.db.execute_query(query, (usuario,))
            
            if not resultado:
                return False
            
            rol = resultado[0]['rol']
            
            # Definir permisos por rol
            permisos = {
                "admin": ["admin", "captura", "usuario"],
                "captura": ["captura", "usuario"],
                "usuario": ["usuario"]
            }
            
            return permiso in permisos.get(rol, [])
            
        except Exception as e:
            print(f"Error verificando permiso: {str(e)}")
            return False
    
    def obtener_todos_usuarios(self) -> List[Dict]:
        """
        Obtiene todos los usuarios con información completa para la interfaz de superadmin
        
        Returns:
            List[Dict]: Lista de usuarios con información completa
        """
        try:
            query = """
                SELECT 
                    usuario,
                    rol,
                    CASE WHEN activo THEN 'activo' ELSE 'inactivo' END as estado,
                    COALESCE(ultimo_acceso::text, 'Nunca') as ultimo_acceso
                FROM usuarios 
                ORDER BY usuario
            """
            return self.db.execute_query(query)
            
        except Exception as e:
            print(f"Error obteniendo todos los usuarios: {str(e)}")
            return []
    
    def eliminar_usuario(self, usuario: str) -> bool:
        """
        Elimina un usuario de la base de datos
        
        Args:
            usuario: Nombre del usuario a eliminar
            
        Returns:
            bool: True si se eliminó exitosamente
        """
        try:
            # No permitir eliminar superadmin
            if usuario == "superadmin":
                return False
            
            # Verificar que el usuario existe
            existing = self.db.execute_query(
                "SELECT id FROM usuarios WHERE usuario = %s",
                (usuario,)
            )
            
            if not existing:
                return False
            
            # Eliminar usuario
            self.db.execute_query(
                "DELETE FROM usuarios WHERE usuario = %s",
                (usuario,),
                fetch=False
            )
            return True
            
        except Exception as e:
            print(f"Error eliminando usuario: {str(e)}")
            return False
    
    def cambiar_estado_usuario(self, usuario: str, nuevo_estado: str) -> bool:
        """
        Cambia el estado de un usuario (activo/inactivo)
        
        Args:
            usuario: Nombre del usuario
            nuevo_estado: Nuevo estado ('activo' o 'inactivo')
            
        Returns:
            bool: True si se cambió exitosamente
        """
        try:
            # No permitir cambiar estado de superadmin
            if usuario == "superadmin":
                return False
            
            # Convertir estado a booleano
            activo = nuevo_estado.lower() == "activo"
            
            # Actualizar estado
            self.db.execute_query(
                "UPDATE usuarios SET activo = %s WHERE usuario = %s",
                (activo, usuario),
                fetch=False
            )
            return True
            
        except Exception as e:
            print(f"Error cambiando estado de usuario: {str(e)}")
            return False
    
    def actualizar_ultimo_acceso(self, usuario: str) -> bool:
        """
        Actualiza el último acceso de un usuario
        
        Args:
            usuario: Nombre del usuario
            
        Returns:
            bool: True si se actualizó exitosamente
        """
        try:
            self.db.execute_query(
                "UPDATE usuarios SET ultimo_acceso = NOW() WHERE usuario = %s",
                (usuario,),
                fetch=False
            )
            return True
            
        except Exception as e:
            print(f"Error actualizando último acceso: {str(e)}")
            return False 