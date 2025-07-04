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
        # Asegura que las tablas tengan las columnas correctas
        self.db.create_tables()
    
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
            # Si el resultado es CUMPLE o NO CUMPLE, actualizar el histórico
            if cumple.strip().upper() in ["CUMPLE", "NO CUMPLE"]:
                from models.codigo_item import CodigoItem
                codigo_model = CodigoItem(self.db)
                codigo_model.actualizar_resultado_historico(item, cumple.strip().upper())
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
    
    def procesar_historico(self) -> Dict:
        """
        Procesa el histórico de capturas para actualizar resultados
        
        Returns:
            Dict: Resultado del procesamiento
        """
        try:
            # Obtener todas las capturas
            capturas = self.obtener_todas_capturas()
            
            procesados = 0
            actualizados = 0
            
            for captura in capturas:
                procesados += 1
                
                # Aquí se procesaría cada captura para actualizar resultados
                # Por ahora solo simulamos el procesamiento
                
                # Actualizar resultado en la tabla de códigos/items
                if captura['cumple'] == 'CUMPLE':
                    # Buscar el item en la tabla de códigos
                    codigo_item = self.db.execute_query(
                        "SELECT id FROM codigos_items WHERE item = %s",
                        (captura['item'],)
                    )
                    
                    if codigo_item:
                        # Actualizar resultado
                        data = {"resultado": "CUMPLE"}
                        condition = {"item": captura['item']}
                        self.db.update_one("codigos_items", data, condition)
                        actualizados += 1
            
            return {
                'procesados': procesados,
                'actualizados': actualizados
            }
            
        except Exception as e:
            print(f"Error procesando histórico: {str(e)}")
            return {
                'procesados': 0,
                'actualizados': 0
            }
    
    def limpiar_capturas(self, confirmar: bool = False) -> bool:
        """
        Limpia todas las capturas
        
        Args:
            confirmar: Si se debe confirmar la acción
            
        Returns:
            bool: True si se limpiaron exitosamente
        """
        if not confirmar:
            return False
        
        try:
            # Eliminar todas las capturas
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
            Optional[Dict]: Captura encontrada
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
        Mueve solo las capturas seleccionadas al histórico (actualiza codigos_items y elimina de capturas)
        Args:
            ids (list): Lista de IDs de capturas a procesar
        Returns:
            dict: {'procesados': int, 'actualizados': int}
        """
        from models.codigo_item import CodigoItem
        codigo_model = CodigoItem(self.db)
        procesados = 0
        actualizados = 0
        for id_captura in ids:
            captura = self.db.execute_query("SELECT * FROM capturas WHERE id = %s", (id_captura,))
            if captura:
                captura = captura[0]
                codigo_barras = captura.get('codigo')
                item = captura.get('item')
                resultado = captura.get('cumple')
                # Buscar si el item ya existe
                existing = self.db.execute_query(
                    "SELECT id, codigo_barras, resultado FROM codigos_items WHERE item = %s",
                    (item,)
                )
                if existing:
                    # Actualizar resultado y código de barras si es diferente
                    update_data = {"resultado": resultado, "fecha_actualizacion": datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
                    if existing[0]['codigo_barras'] != codigo_barras:
                        update_data["codigo_barras"] = codigo_barras
                    self.db.update_one("codigos_items", update_data, {"id": existing[0]['id']})
                    actualizados += 1
                else:
                    # Si no existe, crearlo
                    self.db.insert_one("codigos_items", {
                        "codigo_barras": codigo_barras,
                        "item": item,
                        "resultado": resultado,
                        "fecha_actualizacion": datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                    })
                    actualizados += 1
                # Eliminar la captura de la tabla de capturas
                self.db.execute_query("DELETE FROM capturas WHERE id = %s", (id_captura,), fetch=False)
                procesados += 1
        return {'procesados': procesados, 'actualizados': actualizados} 
