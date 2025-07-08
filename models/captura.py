"""
Modelo de captura para la aplicación
"""
import pandas as pd
from datetime import datetime
from typing import Optional, List, Dict

class Captura:
    """Modelo para manejar capturas de la aplicación"""
    
    def __init__(self, db_manager):
        """
        Inicializa el modelo de captura
        
        Args:
            db_manager: Instancia del gestor de base de datos
        """
        self.db = db_manager
    
    def guardar_captura(self, codigo: str, item: str, motivo: str, cumple: str, usuario: str) -> bool:
        """
        Guarda una nueva captura
        
        Args:
            codigo: Código de barras
            item: Código de item
            motivo: Motivo de la captura
            cumple: Si cumple o no
            usuario: Usuario que realiza la captura
            
        Returns:
            bool: True si se guardó exitosamente
        """
        try:
            # Guardar la captura
            query = """
                INSERT INTO capturas (codigo, item, motivo, cumple, usuario, fecha)
                VALUES (%s, %s, %s, %s, %s, NOW())
                ON CONFLICT (codigo, item) DO UPDATE SET
                    motivo = EXCLUDED.motivo,
                    cumple = EXCLUDED.cumple,
                    usuario = EXCLUDED.usuario,
                    fecha = EXCLUDED.fecha
            """
            self.db.execute_query(query, (codigo, item, motivo, cumple, usuario), fetch=False)
            return True
        except Exception as e:
            print(f"Error guardando captura: {str(e)}")
            return False
    
    def obtener_capturas_usuario(self, usuario: str) -> List[Dict]:
        """
        Obtiene las capturas de un usuario específico
        
        Args:
            usuario: Nombre del usuario
            
        Returns:
            List[Dict]: Lista de capturas del usuario
        """
        try:
            query = """
                SELECT id, codigo, item, motivo, cumple, fecha
                FROM capturas 
                WHERE usuario = %s
                ORDER BY fecha DESC
            """
            return self.db.execute_query(query, (usuario,))
            
        except Exception as e:
            print(f"Error obteniendo capturas: {str(e)}")
            return []
    
    def obtener_todas_capturas(self) -> List[Dict]:
        """
        Obtiene todas las capturas
        
        Returns:
            List[Dict]: Lista de todas las capturas
        """
        try:
            query = """
                SELECT id, codigo, item, motivo, cumple, usuario, fecha
                FROM capturas 
                ORDER BY fecha DESC
            """
            return self.db.execute_query(query)
            
        except Exception as e:
            print(f"Error obteniendo capturas: {str(e)}")
            return []
    
    def exportar_capturas_excel(self, ruta_archivo: str, usuario: Optional[str] = None) -> bool:
        """
        Exporta las capturas a un archivo Excel
        
        Args:
            ruta_archivo: Ruta donde guardar el archivo
            usuario: Usuario específico (opcional)
            
        Returns:
            bool: True si se exportó exitosamente
        """
        try:
            # Obtener capturas
            if usuario:
                capturas = self.obtener_capturas_usuario(usuario)
            else:
                capturas = self.obtener_todas_capturas()
            
            if not capturas:
                return False
            
            # Crear DataFrame
            df = pd.DataFrame(capturas)
            
            # Reordenar columnas
            columnas = ['codigo', 'item', 'motivo', 'cumple', 'usuario', 'fecha']
            df = df[columnas]
            
            # Renombrar columnas
            df.columns = ['Código', 'Item', 'Motivo', 'Cumple', 'Usuario', 'Fecha']
            
            # Guardar archivo
            df.to_excel(ruta_archivo, index=False)
            return True
            
        except Exception as e:
            print(f"Error exportando capturas: {str(e)}")
            return False
    
    def obtener_estadisticas_capturas(self) -> Dict:
        """
        Obtiene estadísticas de las capturas
        
        Returns:
            Dict: Estadísticas de capturas
        """
        try:
            # Total de capturas
            total_query = "SELECT COUNT(*) as total FROM capturas"
            total_result = self.db.execute_query(total_query)
            total_capturas = total_result[0]['total'] if total_result else 0
            
            # Capturas que cumplen
            cumple_query = "SELECT COUNT(*) as cumple FROM capturas WHERE cumple = 'CUMPLE'"
            cumple_result = self.db.execute_query(cumple_query)
            cumple = cumple_result[0]['cumple'] if cumple_result else 0
            
            # Capturas que no cumplen
            no_cumple_query = "SELECT COUNT(*) as no_cumple FROM capturas WHERE cumple = 'NO CUMPLE'"
            no_cumple_result = self.db.execute_query(no_cumple_query)
            no_cumple = no_cumple_result[0]['no_cumple'] if no_cumple_result else 0
            
            return {
                'total_capturas': total_capturas,
                'cumple': cumple,
                'no_cumple': no_cumple
            }
            
        except Exception as e:
            print(f"Error obteniendo estadísticas: {str(e)}")
            return {
                'total_capturas': 0,
                'cumple': 0,
                'no_cumple': 0
            }
    
    def limpiar_capturas(self, confirmar: bool = False) -> bool:
        """
        Limpia todas las capturas (solo para desarrollo)
        
        Args:
            confirmar: Si se debe confirmar la limpieza
            
        Returns:
            bool: True si se limpiaron exitosamente
        """
        if not confirmar:
            return False
        
        try:
            self.db.execute_query("DELETE FROM capturas", fetch=False)
            return True
        except Exception as e:
            print(f"Error limpiando capturas: {str(e)}")
            return False
    
    def buscar_captura(self, codigo: str, item: str) -> Optional[Dict]:
        """
        Busca una captura específica
        
        Args:
            codigo: Código de barras
            item: Código de item
            
        Returns:
            Optional[Dict]: Captura encontrada o None
        """
        try:
            query = """
                SELECT id, codigo, item, motivo, cumple, usuario, fecha
                FROM capturas 
                WHERE codigo = %s AND item = %s
            """
            resultado = self.db.execute_query(query, (codigo, item))
            
            if resultado:
                return resultado[0]
            
            return None
            
        except Exception as e:
            print(f"Error buscando captura: {str(e)}")
            return None
    
    def mover_capturas_a_historico(self, ids: list) -> dict:
        """
        Mueve capturas seleccionadas al histórico (codigos_items)
        
        Args:
            ids: Lista de IDs de capturas a mover
            
        Returns:
            dict: Resultado del proceso
        """
        try:
            procesados = 0
            actualizados = 0
            
            for id_captura in ids:
                # Obtener la captura
                captura_query = "SELECT codigo, item, cumple FROM capturas WHERE id = %s"
                captura_result = self.db.execute_query(captura_query, (id_captura,))
                
                if not captura_result:
                    continue
                
                captura = captura_result[0]
                procesados += 1
                
                # Buscar si existe en codigos_items
                existing_query = """
                    SELECT id FROM codigos_items 
                    WHERE codigo_barras = %s OR item = %s
                """
                existing_result = self.db.execute_query(existing_query, (captura['codigo'], captura['item']))
                
                if existing_result:
                    # Actualizar resultado existente
                    update_query = """
                        UPDATE codigos_items 
                        SET resultado = %s, fecha_actualizacion = NOW()
                        WHERE codigo_barras = %s OR item = %s
                    """
                    self.db.execute_query(update_query, (captura['cumple'], captura['codigo'], captura['item']), fetch=False)
                    actualizados += 1
                else:
                    # Insertar nuevo registro
                    insert_query = """
                        INSERT INTO codigos_items (codigo_barras, item, resultado, fecha_actualizacion)
                        VALUES (%s, %s, %s, NOW())
                    """
                    self.db.execute_query(insert_query, (captura['codigo'], captura['item'], captura['cumple']), fetch=False)
                    actualizados += 1
                
                # Eliminar la captura
                self.db.execute_query("DELETE FROM capturas WHERE id = %s", (id_captura,), fetch=False)
            
            return {
                'procesados': procesados,
                'actualizados': actualizados
            }
            
        except Exception as e:
            print(f"Error moviendo capturas: {str(e)}")
            return {
                'procesados': 0,
                'actualizados': 0
            }
    
    def registrar_consulta(self, usuario: str, codigo_barras: str, item_id: int, resultado: str):
        """
        Registra una consulta de usuario
        Args:
            usuario: Usuario que realizó la consulta
            codigo_barras: Código de barras consultado
            item_id: ID del item (opcional)
            resultado: Resultado de la consulta
        """
        try:
            # Sugerencia: la tabla 'consultas' debe tener los campos: id, usuario, codigo_barras, item_id, resultado, fecha_hora
            query = """
                INSERT INTO consultas (usuario, codigo_barras, item_id, resultado, fecha_hora)
                VALUES (%s, %s, %s, %s, NOW())
            """
            self.db.execute_query(query, (usuario, codigo_barras, item_id, resultado), fetch=False)
        except Exception as e:
            print(f"Error registrando consulta: {str(e)}") 