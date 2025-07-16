"""
Modelo de código_item para la aplicación
"""
import pandas as pd
import re
from typing import Optional, List, Dict
import os

class CodigoItem:
    """Modelo para manejar items y códigos de barra"""
    
    def __init__(self, db_manager):
        """
        Inicializa el modelo de código_item
        
        Args:
            db_manager: Instancia del gestor de base de datos
        """
        self.db = db_manager
    
    def buscar_codigo(self, codigo_barras: str) -> Optional[Dict]:
        """
        Busca un código de barras y devuelve el item y resultado usando la relación correcta
        """
        try:
            codigo_limpio = self.limpiar_codigo_barras(codigo_barras)
            query = """
                SELECT i.item, i.resultado, i.fecha_actualizacion
                FROM codigos_barras cb
                JOIN items i ON cb.item_id = i.id
                WHERE cb.codigo_barras = %s
            """
            resultado = self.db.execute_query(query, (codigo_limpio,))
            if resultado:
                return resultado[0]
            return None
        except Exception as e:
            print(f"Error buscando código: {str(e)}")
            return None
    
    def buscar_item(self, item: str) -> Optional[Dict]:
        """
        Busca un item por su código
        
        Args:
            item: Código del item a buscar
            
        Returns:
            Optional[Dict]: Información del item encontrado
        """
        try:
            # Limpiar item
            item_limpio = self.limpiar_item_code(item)
            
            # Buscar en la base de datos
            query = """
                SELECT codigo_barras, item, resultado, fecha_actualizacion
                FROM codigos_items 
                WHERE item = %s
            """
            resultado = self.db.execute_query(query, (item_limpio,))
            
            if resultado:
                return resultado[0]
            
            return None
            
        except Exception as e:
            print(f"Error buscando item: {str(e)}")
            return None
    
    def cargar_desde_excel(self, ruta_contenedor: str) -> Dict:
        """
        Carga datos desde un archivo Excel de contenedor (CLP) usando la estructura normalizada correcta
        
        Args:
            ruta_contenedor: Ruta al archivo de contenedor
            
        Returns:
            Dict: Resultado de la carga
        """
        try:
            # Leer archivo de contenedor
            df_contenedor = pd.read_excel(ruta_contenedor, sheet_name=0, dtype=str)
            
            registros_procesados = 0
            items_insertados = 0
            codigos_insertados = 0
            
            for idx, fila in df_contenedor.iterrows():
                item_code = self.limpiar_item_code(fila.iloc[0]) if len(fila) > 0 else ""
                codigo_barras = str(fila.iloc[5]).strip() if len(fila) > 5 else ""
                
                # Forzar código de barras a string sin notación científica, te odio microsoft
                if codigo_barras:
                    try:
                        if 'e' in codigo_barras.lower():
                            codigo_barras = '{0:.0f}'.format(float(codigo_barras))
                    except Exception:
                        pass
                
                if item_code and codigo_barras:
                    registros_procesados += 1
                    
                    # El resultado se deja vacío o como 'pendiente' según tu lógica
                    resultado = "pendiente"
                    
                    # 1. Verificar si el item ya existe
                    existing_item = self.db.execute_query(
                        "SELECT id FROM items WHERE item = %s",
                        (item_code,)
                    )
                    
                    item_id = None
                    if existing_item:
                        item_id = existing_item[0]['id']
                        # No se actualiza resultado aquí, solo si lo necesitas
                    else:
                        # Insertar nuevo item
                        item_data = {
                            "item": item_code,
                            "resultado": resultado,
                            "fecha_actualizacion": pd.Timestamp.now()
                        }
                        item_id = self.db.insert_one("items", item_data)
                        if item_id:
                            items_insertados += 1
                    
                    # 2. Verificar si el código de barras ya existe
                    if item_id:
                        existing_codigo = self.db.execute_query(
                            "SELECT id FROM codigos_barras WHERE codigo_barras = %s",
                            (codigo_barras,)
                        )
                        
                        if not existing_codigo:
                            # Insertar nuevo código de barras
                            codigo_data = {
                                "codigo_barras": codigo_barras,
                                "item_id": item_id
                            }
                            if self.db.insert_one("codigos_barras", codigo_data):
                                codigos_insertados += 1
            
            return {
                "procesados": registros_procesados,
                "items_insertados": items_insertados,
                "codigos_insertados": codigos_insertados
            }
            
        except Exception as e:
            print(f"Error cargando desde Excel: {str(e)}")
            return {
                "procesados": 0,
                "items_insertados": 0,
                "codigos_insertados": 0,
                "error": str(e)
            }
    
    def exportar_a_excel(self, ruta_archivo: str) -> bool:
        """
        Exporta los códigos e items a un archivo Excel
        
        Args:
            ruta_archivo: Ruta donde guardar el archivo
            
        Returns:
            bool: True si se exportó exitosamente
        """
        try:
            # Obtener todos los códigos
            query = """
                SELECT codigo_barras, item, resultado, fecha_actualizacion
                FROM codigos_items 
                ORDER BY item
            """
            codigos = self.db.execute_query(query)
            
            if not codigos:
                return False
            
            # Crear DataFrame
            df = pd.DataFrame(codigos)
            
            # Renombrar columnas
            df.columns = ['Código de Barras', 'Item', 'Resultado', 'Fecha Actualización']
            
            # Guardar archivo
            df.to_excel(ruta_archivo, index=False)
            return True
            
        except Exception as e:
            print(f"Error exportando códigos: {str(e)}")
            return False
    
    def obtener_estadisticas(self) -> Dict:
        """
        Obtiene estadísticas de los códigos e items usando la estructura normalizada
        
        Returns:
            Dict: Estadísticas
        """
        try:
            # Total de códigos de barras
            total_codigos_query = "SELECT COUNT(*) as total FROM codigos_barras"
            total_codigos_result = self.db.execute_query(total_codigos_query)
            total_codigos = total_codigos_result[0]['total'] if total_codigos_result else 0
            
            # Total de items
            total_items_query = "SELECT COUNT(*) as total FROM items"
            total_items_result = self.db.execute_query(total_items_query)
            total_items = total_items_result[0]['total'] if total_items_result else 0
            
            # Items con resultado
            con_resultado_query = "SELECT COUNT(*) as con_resultado FROM items WHERE resultado != '' AND resultado IS NOT NULL"
            con_resultado_result = self.db.execute_query(con_resultado_query)
            con_resultado = con_resultado_result[0]['con_resultado'] if con_resultado_result else 0
            
            # Items sin resultado
            sin_resultado = total_items - con_resultado
            
            # Última actualización
            ultima_actualizacion_query = "SELECT MAX(fecha_actualizacion) as ultima FROM items"
            ultima_result = self.db.execute_query(ultima_actualizacion_query)
            ultima_actualizacion = ultima_result[0]['ultima'] if ultima_result and ultima_result[0]['ultima'] else 'Nunca'
            
            return {
                'total_codigos': total_codigos,
                'total_items': total_items,
                'con_resultado': con_resultado,
                'sin_resultado': sin_resultado,
                'ultima_actualizacion': ultima_actualizacion
            }
            
        except Exception as e:
            print(f"Error obteniendo estadísticas: {str(e)}")
            return {
                'total_codigos': 0,
                'total_items': 0,
                'con_resultado': 0,
                'sin_resultado': 0,
                'ultima_actualizacion': 'Nunca'
            }
    
    def limpiar_codigo_barras(self, codigo: str) -> str:
        """
        Limpia un código de barras
        
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
    
    def limpiar_item_code(self, item: str) -> str:
        """
        Limpia un código de item
        
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
    
    def actualizar_resultado(self, codigo_barras: str, resultado: str) -> bool:
        """
        Actualiza el resultado de un código
        
        Args:
            codigo_barras: Código de barras
            resultado: Nuevo resultado
            
        Returns:
            bool: True si se actualizó exitosamente
        """
        try:
            data = {
                "resultado": resultado,
                "fecha_actualizacion": pd.Timestamp.now()
            }
            condition = {"codigo_barras": codigo_barras}
            
            self.db.update_one("codigos_items", data, condition)
            return True
            
        except Exception as e:
            print(f"Error actualizando resultado: {str(e)}")
            return False
    
    def buscar_por_patron(self, patron: str) -> List[Dict]:
        """
        Busca códigos que coincidan con un patrón
        
        Args:
            patron: Patrón de búsqueda
            
        Returns:
            List[Dict]: Lista de códigos que coinciden
        """
        try:
            query = """
                SELECT codigo_barras, item, resultado, fecha_actualizacion
                FROM codigos_items 
                WHERE codigo_barras LIKE %s OR item LIKE %s OR resultado LIKE %s
                ORDER BY item
                LIMIT 100
            """
            patron_like = f"%{patron}%"
            return self.db.execute_query(query, (patron_like, patron_like, patron_like))
            
        except Exception as e:
            print(f"Error buscando por patrón: {str(e)}")
            return []
    
    def cargar_clp(self, ruta_clp: str) -> dict:
        """Carga el archivo CLP y actualiza la relación código ↔ item en la base de datos, usando codigos_items como histórico. No modifica el resultado si el item ya existe."""
        import pandas as pd
        import re
        resultado = {
            'nuevos_registros': 0,
            'total_codigos': 0,
            'total_procesados': 0
        }
        try:
            # Leer CLP
            df_clp = pd.read_excel(ruta_clp, sheet_name=0, dtype=str)
            resultado['total_codigos'] = len(df_clp)
            for idx, fila in df_clp.iterrows():
                item_code = re.sub(r'\D', '', str(fila.iloc[0])) if len(fila) > 0 else ""
                codigo_barras = str(fila.iloc[5]).strip() if len(fila) > 5 else ""
                if codigo_barras and item_code:
                    resultado['total_procesados'] += 1
                    # Buscar si el item ya existe
                    existing = self.db.execute_query(
                        "SELECT id, codigo_barras, resultado FROM codigos_items WHERE item = %s",
                        (item_code,)
                    )
                    if existing:
                        # Solo actualizar el código de barras si es diferente, NO tocar resultado
                        if existing[0]['codigo_barras'] != codigo_barras:
                            self.db.update_one(
                                "codigos_items",
                                {"codigo_barras": codigo_barras, "fecha_actualizacion": pd.Timestamp.now()},
                                {"id": existing[0]['id']}
                            )
                    else:
                        # Insertar nuevo registro con resultado vacío
                        self.db.insert_one("codigos_items", {
                            "codigo_barras": codigo_barras,
                            "item": item_code,
                            "resultado": "pendiente",
                            "fecha_actualizacion": pd.Timestamp.now()
                        })
                        resultado['nuevos_registros'] += 1
            return resultado
        except Exception as e:
            print(f"Error cargando CLP: {str(e)}")
            return resultado

    def actualizar_resultado_historico(self, item: str, resultado: str):
        """Actualiza el resultado del histórico para un item"""
        try:
            query = """
                UPDATE codigos_items SET resultado = %s, fecha_actualizacion = NOW()
                WHERE item = %s
            """
            self.db.execute_query(query, (resultado, item), fetch=False)
        except Exception as e:
            print(f"Error actualizando resultado histórico: {str(e)}")

    def limpiar_base_datos(self):
        try:
            self.db.execute_query("DELETE FROM codigos_items", fetch=False)
            self.db.execute_query("DELETE FROM capturas", fetch=False)
            return True
        except Exception as e:
            print(f"Error limpiando base de datos: {str(e)}")
            return False 

    def cargar_varios_clp(self, rutas_clp: list, usuario: str) -> dict:
        import pandas as pd
        procesados = 0
        nuevos_items = 0
        nuevos_codigos = 0
        clp_registros = []
        for ruta in rutas_clp:
            df = pd.read_excel(ruta, sheet_name=0, dtype=str)
            codigos_agregados = 0
            # Registrar la carga de este CLP y obtener el id
            clp_carga_id = self.registrar_carga_clp(ruta, usuario, 0, return_id=True)
            for idx, fila in df.iterrows():
                item_code = self.limpiar_item_code(fila.iloc[0]) if len(fila) > 0 else ""
                codigo_barras = str(fila.iloc[5]).strip() if len(fila) > 5 else ""
                if item_code and codigo_barras:
                    procesados += 1
                    # Insertar item si no existe
                    item_id = None
                    res = self.db.execute_query("SELECT id FROM items WHERE item = %s", (item_code,))
                    if res:
                        item_id = res[0]['id']
                    else:
                        item_id = self.db.insert_one("items", {"item": item_code})
                        nuevos_items += 1
                    if item_id is not None:
                        res = self.db.execute_query("SELECT id FROM codigos_barras WHERE codigo_barras = %s", (codigo_barras,))
                        if not res:
                            self.db.insert_one("codigos_barras", {"codigo_barras": codigo_barras, "item_id": item_id})
                            nuevos_codigos += 1
                        # Registrar detalle de carga
                        self.db.insert_one("clp_carga_detalle", {"clp_carga_id": clp_carga_id, "codigo_barras": codigo_barras, "item_id": item_id})
            # Actualizar la cantidad de códigos agregados en la carga
            self.db.execute_query("UPDATE clp_cargas SET codigos_agregados = %s WHERE id = %s", (codigos_agregados, clp_carga_id), fetch=False)
            clp_registros.append({"archivo": ruta, "usuario": usuario, "codigos_agregados": codigos_agregados})
        return {"procesados": procesados, "nuevos_items": nuevos_items, "nuevos_codigos": nuevos_codigos, "clp_registros": clp_registros}

    def registrar_carga_clp(self, archivo: str, usuario: str, codigos_agregados: int, return_id: bool = False):
        import pandas as pd
        import datetime
        nombre_archivo = os.path.basename(archivo)
        fecha_carga = pd.Timestamp.now() if hasattr(pd, 'Timestamp') else datetime.datetime.now()
        try:
            if return_id:
                return self.db.insert_one("clp_cargas", {
                    "archivo": nombre_archivo,
                    "usuario": usuario,
                    "fecha_carga": fecha_carga,
                    "codigos_agregados": codigos_agregados
                })
            else:
                self.db.insert_one("clp_cargas", {
                    "archivo": nombre_archivo,
                    "usuario": usuario,
                    "fecha_carga": fecha_carga,
                    "codigos_agregados": codigos_agregados
                })
        except Exception as e:
            print(f"Error registrando carga de CLP: {str(e)}") 

    def eliminar_item(self, codigo_barras: str) -> bool:
        """
        Elimina un ítem y su código de barras asociado de la base de datos
        Args:
            codigo_barras: Código de barras del ítem a eliminar
        Returns:
            bool: True si se eliminó exitosamente
        """
        try:
            # Buscar el item_id asociado al código de barras
            res = self.db.execute_query(
                "SELECT item_id FROM codigos_items WHERE codigo_barras = %s",
                (codigo_barras,)
            )
            if not res:
                return False
            item_id = res[0]['item_id']
            # Eliminar el código de barras
            self.db.execute_query(
                "DELETE FROM codigos_items WHERE codigo_barras = %s",
                (codigo_barras,),
                fetch=False
            )
            # Eliminar el ítem si no tiene más códigos asociados
            otros_codigos = self.db.execute_query(
                "SELECT COUNT(*) as count FROM codigos_items WHERE item_id = %s",
                (item_id,)
            )
            if otros_codigos and otros_codigos[0]['count'] == 0:
                self.db.execute_query(
                    "DELETE FROM items WHERE id = %s",
                    (item_id,),
                    fetch=False
                )
            return True
        except Exception as e:
            print(f"Error eliminando ítem: {str(e)}")
            return False 