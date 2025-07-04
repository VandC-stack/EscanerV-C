"""
Modelo de código_item para la aplicación
"""
import pandas as pd
import re
from typing import Optional, List, Dict

class CodigoItem:
    """Modelo para manejar códigos e items de la aplicación"""
    
    def __init__(self, db_manager):
        """
        Inicializa el modelo de código_item
        
        Args:
            db_manager: Instancia del gestor de base de datos
        """
        self.db = db_manager
    
    def buscar_codigo(self, codigo_barras: str) -> Optional[Dict]:
        """
        Busca un código de barras
        
        Args:
            codigo_barras: Código de barras a buscar
            
        Returns:
            Optional[Dict]: Información del código encontrado
        """
        try:
            # Limpiar código
            codigo_limpio = self.limpiar_codigo_barras(codigo_barras)
            
            # Buscar en la base de datos
            query = """
                SELECT codigo_barras, item, resultado, fecha_actualizacion
                FROM codigos_items 
                WHERE codigo_barras = %s
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
    
    def cargar_desde_excel(self, ruta_contenedor: str, ruta_historico: str) -> Dict:
        """
        Carga datos desde archivos Excel
        
        Args:
            ruta_contenedor: Ruta al archivo de contenedor
            ruta_historico: Ruta al archivo histórico
            
        Returns:
            Dict: Resultado de la carga
        """
        try:
            # Leer archivo de contenedor
            df_contenedor = pd.read_excel(ruta_contenedor, sheet_name=0, dtype=str)
            
            # Leer archivo histórico
            df_historico = pd.read_excel(ruta_historico, sheet_name=0, dtype=str)
            
            # Crear diccionario de resultados del histórico
            historico_dict = {}
            for idx, row in df_historico.iterrows():
                item = self.limpiar_item_code(row.iloc[0]) if len(row) > 0 else ""
                valor_raw = row.iloc[1] if len(row) > 1 else ""
                resultado = str(valor_raw).strip() if pd.notnull(valor_raw) else ""
                
                if resultado.strip().lower() in ["nan", "none", ""]:
                    resultado = ""
                
                if item and item.lower() != "item":
                    historico_dict[item] = resultado
            
            # Procesar datos del contenedor
            registros_procesados = 0
            registros_insertados = 0
            
            for idx, fila in df_contenedor.iterrows():
                item_code = self.limpiar_item_code(fila.iloc[0]) if len(fila) > 0 else ""
                codigo_barras = str(fila.iloc[5]).strip() if len(fila) > 5 else ""
                
                # Forzar código de barras a string sin notación científica
                if codigo_barras:
                    try:
                        if 'e' in codigo_barras.lower():
                            codigo_barras = '{0:.0f}'.format(float(codigo_barras))
                    except Exception:
                        pass
                
                if item_code and codigo_barras:
                    registros_procesados += 1
                    
                    # Buscar resultado en histórico
                    resultado = historico_dict.get(item_code, "")
                    
                    # Verificar si ya existe
                    existing = self.db.execute_query(
                        "SELECT id FROM codigos_items WHERE codigo_barras = %s AND item = %s",
                        (codigo_barras, item_code)
                    )
                    
                    if not existing:
                        # Insertar nuevo registro
                        data = {
                            "codigo_barras": codigo_barras,
                            "item": item_code,
                            "resultado": resultado,
                            "fecha_actualizacion": pd.Timestamp.now()
                        }
                        self.db.insert_one("codigos_items", data)
                        registros_insertados += 1
            
            return {
                "procesados": registros_procesados,
                "insertados": registros_insertados,
                "historico_items": len(historico_dict)
            }
            
        except Exception as e:
            print(f"Error cargando desde Excel: {str(e)}")
            return {
                "procesados": 0,
                "insertados": 0,
                "historico_items": 0,
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
        Obtiene estadísticas de los códigos e items
        
        Returns:
            Dict: Estadísticas
        """
        try:
            # Total de registros
            total_query = "SELECT COUNT(*) as total FROM codigos_items"
            total_result = self.db.execute_query(total_query)
            total = total_result[0]['total'] if total_result else 0
            
            # Registros con resultado
            con_resultado_query = "SELECT COUNT(*) as con_resultado FROM codigos_items WHERE resultado != ''"
            con_resultado_result = self.db.execute_query(con_resultado_query)
            con_resultado = con_resultado_result[0]['con_resultado'] if con_resultado_result else 0
            
            # Registros sin resultado
            sin_resultado = total - con_resultado
            
            return {
                'total': total,
                'con_resultado': con_resultado,
                'sin_resultado': sin_resultado
            }
            
        except Exception as e:
            print(f"Error obteniendo estadísticas: {str(e)}")
            return {
                'total': 0,
                'con_resultado': 0,
                'sin_resultado': 0
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
