import customtkinter as ct
from tkinter import StringVar, messagebox, filedialog
from PIL import Image
import os
import gspread
from oauth2client.service_account import ServiceAccountCredentials
import tempfile
import threading
from datetime import datetime
import time
from googleapiclient.errors import HttpError
import json
import logging
from typing import Dict, List, Optional
import backoff
from gspread.exceptions import APIError
import pandas as pd
import re
import math

ct.set_appearance_mode("dark")
ct.set_default_color_theme("dark-blue")

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class Configuracion:
    def __init__(self):
        self.credenciales_json = CREDENCIALES_JSON
        self.spreadsheet_id_codigos = SPREADSHEET_ID_CODIGOS
        self.spreadsheet_id_items = SPREADSHEET_ID_ITEMS
        if not all([self.credenciales_json, self.spreadsheet_id_codigos, self.spreadsheet_id_items]):
            raise ValueError("Faltan credenciales necesarias")

class GoogleSheetsManager:
    def __init__(self, config: Configuracion):
        self.config = config
        self.client = None
        self._conectar()

    @backoff.on_exception(
        backoff.expo,
        (gspread.exceptions.APIError, HttpError),
        max_tries=3
    )
    def _conectar(self):
        try:
            scope = ['https://spreadsheets.google.com/feeds']
            with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as temp_cred:
                temp_cred.write(self.config.credenciales_json.encode('utf-8'))
                cred_path = temp_cred.name
            creds = ServiceAccountCredentials.from_json_keyfile_name(cred_path, scope)
            self.client = gspread.authorize(creds)
            os.remove(cred_path)
            logger.info("Conexión exitosa con Google Sheets")
        except Exception as e:
            logger.error(f"Error al conectar con Google Sheets: {str(e)}")
            raise

    def obtener_hoja(self, spreadsheet_id: str, worksheet_id: Optional[int] = None) -> gspread.Worksheet:
        try:
            spreadsheet = self.client.open_by_key(spreadsheet_id)
            if worksheet_id:
                return spreadsheet.get_worksheet_by_id(worksheet_id)
            return spreadsheet.sheet1
        except gspread.exceptions.WorksheetNotFound:
            logger.error(f"No se encontró la hoja en el spreadsheet {spreadsheet_id}")
            raise
        except Exception as e:
            logger.error(f"Error al obtener hoja: {str(e)}")
            raise

    def obtener_todas_hojas(self, spreadsheet_id: str) -> List[gspread.Worksheet]:
        try:
            spreadsheet = self.client.open_by_key(spreadsheet_id)
            return spreadsheet.worksheets()
        except Exception as e:
            logger.error(f"Error al obtener hojas: {str(e)}")
            raise

class LoginWindow:
    def __init__(self, master, on_success):
        self.master = master
        self.on_success = on_success
        self.attempts_left = 3
        self.frame = ct.CTkFrame(self.master)
        self.frame.pack(fill="both", expand=True, padx=20, pady=20)
        self.label_title = ct.CTkLabel(self.frame, text="Iniciar sesión", font=("Segoe UI", 18, "bold"))
        self.label_title.pack(pady=(0, 16))
        self.user_var = StringVar()
        self.pass_var = StringVar()
        self.label_user = ct.CTkLabel(self.frame, text="Usuario:")
        self.label_user.pack(anchor="w")
        self.entry_user = ct.CTkEntry(self.frame, textvariable=self.user_var)
        self.entry_user.pack(fill="x", pady=(0, 8))
        self.label_pass = ct.CTkLabel(self.frame, text="Contraseña:")
        self.label_pass.pack(anchor="w")
        # Frame horizontal para contraseña y botón
        self.pass_row = ct.CTkFrame(self.frame)
        self.pass_row.pack(fill="x", pady=(0, 8))
        self.entry_pass = ct.CTkEntry(self.pass_row, textvariable=self.pass_var, show="*")
        self.entry_pass.pack(side="left", fill="x", expand=True)
        self.login_button = ct.CTkButton(self.pass_row, text="Entrar", command=self.try_login, width=100)
        self.login_button.pack(side="right", padx=(8, 0))
        self.error_label = ct.CTkLabel(self.frame, text="", text_color="#FF3333", font=("Segoe UI", 11, "bold"))
        self.error_label.pack(pady=(0, 8))
        self.entry_user.bind("<Return>", lambda e: self.entry_pass.focus_set())
        self.entry_pass.bind("<Return>", lambda e: self.try_login())
        self.entry_user.focus_set()

    def try_login(self):
        usuario = self.user_var.get().strip()
        contrasena = self.pass_var.get().strip()
        if not usuario or not contrasena:
            self._safe_configure(self.error_label, text="Ingrese usuario y contraseña.")
            return
        self._safe_configure(self.login_button, state="disabled", text="Verificando...")
        threading.Thread(target=self._verificar_credenciales, args=(usuario, contrasena), daemon=True).start()

    def _verificar_credenciales(self, usuario, contrasena):
        try:
            scope = ['https://spreadsheets.google.com/feeds']
            with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as temp_cred:
                temp_cred.write(CREDENCIALES_JSON.encode('utf-8'))
                cred_path = temp_cred.name
            creds = ServiceAccountCredentials.from_json_keyfile_name(cred_path, scope)
            client = gspread.authorize(creds)
            os.remove(cred_path)
            sheet = client.open_by_key("1IbUHKUFbSQZY9ZPfwIKFGE5dZ-2zDVqDdn8UvVThExQ").sheet1
            data = sheet.get_all_records()
            for row in data:
                if str(row.get("usuario", "")).strip() == usuario and str(row.get("contraseña", "")).strip() == contrasena:
                    rol = str(row.get("rol", "")).strip()
                    self.master.after(0, self._login_exitoso, usuario, rol)
                    return
            self.attempts_left -= 1
            if self.attempts_left > 0:
                self.master.after(0, lambda: self._safe_configure(self.error_label, text=f"Usuario o contraseña incorrectos. Intentos restantes: {self.attempts_left}"))
                self.master.after(0, lambda: self._safe_configure(self.login_button, state="normal", text="Entrar"))
            else:
                self.master.after(0, lambda: self._safe_configure(self.error_label, text="Demasiados intentos fallidos. Reinicie la aplicación para volver a intentar."))
                self.master.after(0, lambda: self._safe_configure(self.login_button, state="disabled", text="Bloqueado"))
        except Exception as e:
            self.master.after(0, lambda e=e: self._safe_configure(self.error_label, text=f"Error de conexión: {str(e)}"))
            self.master.after(0, lambda: self._safe_configure(self.login_button, state="normal", text="Entrar"))

    def _login_exitoso(self, usuario, rol):
        for w in self.master.winfo_children():
            w.destroy()
        self.on_success(usuario, rol)

    def _safe_configure(self, widget, **kwargs):
        if widget.winfo_exists():
            widget.configure(**kwargs)

class BuscadorApp:
    def __init__(self, root, usuario, rol):
        try:
            self.root = root
            self.usuario = usuario
            self.rol = rol
            self.logo_path = os.path.join(os.path.dirname(__file__), 'resources', 'Logo (2).png')
            self.indice_codigos = {}
            self.indice_resultados = {}
            self.config_data = self.cargar_config()
            self.tabview = ct.CTkTabview(self.root, fg_color="#000000")
            self.tabview.pack(fill="both", expand=True, padx=40, pady=20)
            
            # Crear pestañas según el rol
            self.tabview.add("Escáner")
            self._configurar_interfaz(parent=self.tabview.tab("Escáner"))
            
            # Solo el rol 'captura' puede ver las pestañas de captura y configuración
            if self.rol == "captura":
                self.tabview.add("Captura de Datos")
                self._configurar_captura(parent=self.tabview.tab("Captura de Datos"))
            self.tabview.add("Configuración")
            self._configurar_configuracion(parent=self.tabview.tab("Configuración"))
            
            self.tabview.set("Escáner")
            self.cargar_indice_local()
        except Exception as e:
            import traceback
            error_text = f"ERROR EN BuscadorApp:\n{e}\n{traceback.format_exc()}"
            ct.CTkLabel(self.root, text=error_text, font=("Segoe UI", 16, "bold"), text_color="#FF3333").pack(pady=40)

    def cargar_config(self):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {"contenedor": "", "modelos": ""}

    def guardar_config(self):
        try:
            # Crear el directorio si no existe
            config_dir = os.path.dirname(CONFIG_PATH)
            if not os.path.exists(config_dir):
                os.makedirs(config_dir, exist_ok=True)
            
            with open(CONFIG_PATH, "w", encoding="utf-8") as f:
                json.dump(self.config_data, f)
        except Exception as e:
            logger.error(f"Error al guardar configuración: {str(e)}")
            messagebox.showerror("Error", f"No se pudo guardar la configuración: {str(e)}")

    def _configurar_interfaz(self, parent=None):
        frame = parent
        # Frame horizontal para dividir en dos columnas
        main_hframe = ct.CTkFrame(frame, fg_color="#000000")
        main_hframe.pack(fill="both", expand=True, padx=40, pady=40)
        # Columna izquierda: logo, título, estado, entrada, botones, resultados
        left_col = ct.CTkFrame(main_hframe, fg_color="#000000")
        left_col.pack(side="left", fill="y", expand=True, padx=(0,40))
        logo_visible = False
        if os.path.exists(self.logo_path):
            try:
                logo_img = ct.CTkImage(light_image=Image.open(self.logo_path), dark_image=Image.open(self.logo_path), size=(90, 90))
                self.logo_label = ct.CTkLabel(left_col, image=logo_img, text="", fg_color="#000000")
                self.logo_label.pack(pady=(10, 10))
                logo_visible = True
            except Exception as e:
                ct.CTkLabel(left_col, text=f"[Error al cargar logo]", font=("Segoe UI", 18, "bold"), text_color="#00FFAA", fg_color="#000000").pack(pady=(10, 10))
        if not logo_visible:
            ct.CTkLabel(left_col, text="V&C", font=("Segoe UI", 28, "bold"), text_color="#00FFAA", fg_color="#000000").pack(pady=(10, 10))
        self.title_label = ct.CTkLabel(left_col, text="Escáner de Códigos", font=("Segoe UI", 22, "bold"), text_color="#00FFAA", fg_color="#000000")
        self.title_label.pack(pady=(0, 8))
        self.codigo_var = StringVar()
        self.codigo_entry = ct.CTkEntry(left_col, textvariable=self.codigo_var, font=("Segoe UI", 15), width=400, height=36, corner_radius=12, border_width=2, border_color="#00FFAA", fg_color="#000000", text_color="#00FFAA", placeholder_text="Código de barras")
        self.codigo_entry.pack(pady=(0, 18))
        self.codigo_entry.bind("<Return>", lambda e: self.buscar_codigo())
        self.botones_frame = ct.CTkFrame(left_col, fg_color="#000000")
        self.botones_frame.pack(pady=(0, 10))
        self.search_button = ct.CTkButton(self.botones_frame, text="Buscar", font=("Segoe UI", 14, "bold"), fg_color="#000000", hover_color="#111111", border_width=2, border_color="#00FFAA", text_color="#00FFAA", corner_radius=12, width=160, height=36, command=self.buscar_codigo)
        self.search_button.pack(side="left", padx=(0, 8))
        self.clear_index_button = ct.CTkButton(self.botones_frame, text="Borrar Índice", font=("Segoe UI", 12), fg_color="#000000", hover_color="#333333", border_width=2, border_color="#FF5555", text_color="#FF5555", corner_radius=12, width=160, height=36, command=self.borrar_indice)
        self.clear_index_button.pack(side="left")
        self.clave_valor = ct.CTkLabel(left_col, text="ITEM: ", font=("Segoe UI", 13, "bold"), text_color="#00FFAA", fg_color="#000000")
        self.clave_valor.pack(pady=(10, 0))
        self.resultado_valor = ct.CTkLabel(left_col, text="RESULTADO: ", font=("Segoe UI", 12), text_color="#00FFAA", fg_color="#000000", wraplength=500)
        self.resultado_valor.pack(pady=(0, 0))
        self.nom_valor = ct.CTkLabel(left_col, text="NOM: ", font=("Segoe UI", 12, "italic"), text_color="#55DDFF", fg_color="#000000", wraplength=500)
        self.nom_valor.pack(pady=(0, 10))
        # Columna derecha: totales, última actualización, botones índice
        right_col = ct.CTkFrame(main_hframe, fg_color="#000000")
        right_col.pack(side="right", fill="y", expand=True, padx=(40,0))
        self.estado_actualizacion_label = ct.CTkLabel(right_col, text="", font=("Segoe UI", 11, "bold"), text_color="#00FFAA", fg_color="#000000")
        self.progress_bar = ct.CTkProgressBar(right_col, width=400, height=16, corner_radius=8, progress_color="#00FFAA")
        self.progress_bar.set(0)
        self.progress_label = ct.CTkLabel(right_col, text="", font=("Segoe UI", 10), text_color="#00FFAA", fg_color="#000000")
        self.cancel_button = ct.CTkButton(right_col, text="Cancelar", font=("Segoe UI", 12, "bold"), fg_color="#330000", hover_color="#550000", border_width=2, border_color="#FF5555", text_color="#FF5555", corner_radius=12, width=200, height=32, command=self.cancelar_actualizacion, state="disabled")
        self.total_codigos_label = ct.CTkLabel(right_col, text="Total de códigos: 0", font=("Segoe UI", 11), text_color="#00FFAA", fg_color="#000000")
        self.total_codigos_label.pack(pady=(0, 2))
        self.ultima_actualizacion_label = ct.CTkLabel(right_col, text="Última actualización: Nunca", font=("Segoe UI", 11), text_color="#00FFAA", fg_color="#000000")
        self.ultima_actualizacion_label.pack(pady=(0, 8))
        self.update_button = ct.CTkButton(right_col, text="Actualizar Índice", font=("Segoe UI", 12, "bold"), fg_color="#000000", hover_color="#111111", border_width=2, border_color="#00FFAA", text_color="#00FFAA", corner_radius=12, width=200, height=32, command=self.actualizar_indice)
        self.update_button.pack(pady=(0, 18))
        self.verificar_button = ct.CTkButton(right_col, text="Verificar Índice", font=("Segoe UI", 12), fg_color="#000000", hover_color="#333333", border_width=2, border_color="#00FFAA", text_color="#00FFAA", corner_radius=12, width=200, height=32, command=self.verificar_indice)
        self.verificar_button.pack(pady=(0, 8))
        if hasattr(self, 'conexion_exitosa') and not self.conexion_exitosa:
            self.update_button.configure(state="disabled")
            self.verificar_button.configure(state="disabled")
            self.search_button.configure(state="disabled")
            self.clear_index_button.configure(state="disabled")

    def mostrar_barra_progreso(self):
        self.progress_bar.pack(pady=(2, 2))
        self.progress_label.pack(pady=(0, 8))
        self.update_button.pack_forget()
        self.cancel_button.pack(pady=(0, 18))
        self.cancel_button.configure(state="normal")

    def ocultar_barra_progreso(self):
        self.progress_bar.pack_forget()
        self.progress_label.pack_forget()
        self.cancel_button.pack_forget()
        self.cancel_button.configure(state="disabled")
        self.update_button.pack(pady=(0, 18))

    def cancelar_actualizacion(self):
        self.cancelar_actualizacion_flag = True
        self.estado_actualizacion_label.configure(text="Cancelando actualización...")
        self.progress_label.configure(text="Cancelando...")

    def actualizar_indice(self):
        try:
            contenedor_path = self.config_data.get("contenedor", "")
            if not contenedor_path:
                messagebox.showerror("Error", "Debes cargar el archivo de contenedor en Configuración.")
                return
            
            # Leer archivo de contenedor (primera hoja)
            df_contenedor = pd.read_excel(contenedor_path, sheet_name=0, dtype=str)
            if df_contenedor.empty or df_contenedor.shape[1] < 6:
                messagebox.showerror("Error", "El archivo de contenedor está vacío o no tiene suficientes columnas (mínimo 6).")
                return

            # Leer archivo histórico (archivo de modelos)
            modelos_path = self.config_data.get("modelos", "")
            if not modelos_path:
                messagebox.showerror("Error", "Debes cargar el archivo histórico (Modelos) en Configuración.")
                return
            
            try:
                df_historico = pd.read_excel(modelos_path, sheet_name=0, dtype=str)
                logger.info(f"Archivo histórico leído: {len(df_historico)} filas")
                logger.info(f"Columnas del histórico: {list(df_historico.columns)}")
            except Exception as e:
                messagebox.showerror("Error", f"No se pudo leer el archivo histórico: {str(e)}")
                return

            def limpiar_item(valor):
                # Quita espacios, ceros a la izquierda, y deja solo números
                return re.sub(r'\D', '', str(valor)).lstrip('0')

            # Limpiar y crear el diccionario de resultados del histórico
            historico_dict = {}
            for idx, row in df_historico.iterrows():
                item = limpiar_item(row.iloc[0]) if len(row) > 0 and pd.notnull(row.iloc[0]) else ""
                valor_raw = row.iloc[1] if len(row) > 1 else ""
                resultado = str(valor_raw).strip() if pd.notnull(valor_raw) else ""
                if resultado.strip().lower() in ["nan", "none", ""]:
                    resultado = ""
                if item and item.lower() != "item":
                    historico_dict[item] = resultado

            logger.info(f"Items en histórico: {len(historico_dict)}")

            # Construir índice con clave compuesta
            datos_indice = []
            items_contenedor = []
            items_con_resultado = 0
            items_sin_resultado_en_contenedor = []
            
            for idx, fila in df_contenedor.iterrows():
                item_code = limpiar_item(fila.iloc[0]) if len(fila) > 0 else ""
                codigo_barras = str(fila.iloc[5]).strip() if len(fila) > 5 else ""
                # Forzar código de barras a string sin notación científica
                if codigo_barras:
                    try:
                        if 'e' in codigo_barras.lower():
                            codigo_barras = '{0:.0f}'.format(float(codigo_barras))
                    except Exception:
                        pass
                if item_code and codigo_barras:
                    items_contenedor.append(item_code)
                    resultado = historico_dict.get(item_code, "")
                    if resultado != "":
                        items_con_resultado += 1
                    else:
                        items_sin_resultado_en_contenedor.append(item_code)
                    clave = f"{codigo_barras}|{item_code}"
                    datos_indice.append([clave, codigo_barras, item_code, resultado])

            logger.info(f"Items en contenedor: {len(items_contenedor)}")
            logger.info(f"Items con resultado encontrado: {items_con_resultado}")
            logger.info(f"Items sin resultado en contenedor: {len(items_sin_resultado_en_contenedor)}")

            df_indice = pd.DataFrame(datos_indice, columns=["CLAVE", "CODIGO", "ITEM", "RESULTADO"])
            
            # Crear el directorio si no existe
            indice_dir = os.path.dirname(INDICE_PATH)
            if not os.path.exists(indice_dir):
                os.makedirs(indice_dir, exist_ok=True)
                
            df_indice.to_csv(INDICE_PATH, index=False, encoding="utf-8")
            self.cargar_indice_local()
            
            # Mostrar estadísticas en el mensaje de éxito
            mensaje = f"Índice actualizado localmente.\nRegistros: {len(df_indice)}\nItems con resultado: {items_con_resultado}\nItems sin resultado: {len(items_sin_resultado_en_contenedor)}"
            messagebox.showinfo("Éxito", mensaje)
        except Exception as e:
            import traceback
            messagebox.showerror("Error", f"Error al actualizar el índice local: {str(e)}\n\n{traceback.format_exc()}")

    def verificar_indice(self):
        try:
            df = pd.read_csv(INDICE_PATH, encoding="utf-8")
            num_registros = len(df)
            if num_registros > 0:
                # Verificar específicamente el item 2454981
                item_especifico = df[df['ITEM'] == '2454981']
                if not item_especifico.empty:
                    resultado_2454981 = item_especifico.iloc[0]['RESULTADO']
                    logger.info(f"Item 2454981 encontrado con resultado: '{resultado_2454981}'")
                else:
                    logger.warning("Item 2454981 no encontrado en el índice")
                
                # Verificar otros items problemáticos mencionados
                items_problematicos = ['1681557', '2016115', '2454981', '2505147', '2562325']
                for item in items_problematicos:
                    item_encontrado = df[df['ITEM'] == item]
                    if not item_encontrado.empty:
                        resultado = item_encontrado.iloc[0]['RESULTADO']
                        logger.info(f"Item {item} encontrado con resultado: '{resultado}'")
                    else:
                        logger.warning(f"Item {item} no encontrado en el índice")
                
                messagebox.showinfo("Verificar Índice", f"El índice local existe.\nRegistros: {num_registros}")
            else:
                messagebox.showwarning("Verificar Índice", "El índice local está vacío.")
        except Exception as e:
            messagebox.showerror("Error", f"Error al verificar el índice local: {str(e)}")

    def borrar_indice(self):
        try:
            # Crear el directorio si no existe
            indice_dir = os.path.dirname(INDICE_PATH)
            if not os.path.exists(indice_dir):
                os.makedirs(indice_dir, exist_ok=True)
                
            # Crear un CSV vacío 
            with open(INDICE_PATH, "w", encoding="utf-8") as f:
                f.write("CLAVE,CODIGO,ITEM,RESULTADO\n")
            self.indice_codigos.clear()
            self.indice_resultados.clear()
            self.clave_valor.configure(text="")
            self.resultado_valor.configure(text="")
            self.nom_valor.configure(text="")
            self.total_codigos_label.configure(text="Total de códigos: 0")
            self.ultima_actualizacion_label.configure(text="Última actualización: Nunca")
            messagebox.showinfo("Éxito", "Índice local borrado completamente.")
        except Exception as e:
            messagebox.showerror("Error", f"Error al borrar el índice local: {str(e)}")

    def cargar_indice_local(self):
        try:
            df = pd.read_csv(INDICE_PATH, encoding="utf-8")
            self.indice_codigos = {str(row["CLAVE"]): str(row["ITEM"]) for _, row in df.iterrows()}
            self.indice_resultados = {str(row["CLAVE"]): str(row["RESULTADO"]) for _, row in df.iterrows()}
            self.total_codigos_label.configure(text=f"Total de códigos: {len(self.indice_codigos)}")
        except Exception:
            self.indice_codigos = {}
            self.indice_resultados = {}
            self.total_codigos_label.configure(text="Total de códigos: 0")

    def buscar_codigo(self):
        codigo = self.codigo_var.get().strip()
        if not codigo:
            self.resultado_valor.configure(text="Ingrese un código válido")
            self.clave_valor.configure(text="")
            self.codigo_var.set("")
            self.codigo_entry.focus_set()
            return
        if not self.indice_codigos or not self.indice_resultados:
            self.resultado_valor.configure(text="El índice no está cargado. Por favor, actualice el índice.")
            self.clave_valor.configure(text="")
            self.codigo_var.set("")
            self.codigo_entry.focus_set()
            return
        self.search_button.configure(state="disabled")
        self.search_button.configure(text="Buscando...")
        self.root.update()
        try:
            codigo_limpio = str(codigo).strip()  # No eliminar ceros a la izquierda
            logger.info(f"Buscando código: {codigo_limpio}")
            encontrado = False
            for clave in self.indice_codigos:
                clave_codigo_barras = clave.split("|")[0]
                if clave_codigo_barras == codigo_limpio:
                    item_code = self.indice_codigos[clave]
                    resultado = self.indice_resultados.get(clave, "")
                    self.clave_valor.configure(text=f"ITEM: {item_code}")
                    self.resultado_valor.configure(text=f"RESULTADO: {resultado}")
                    encontrado = True
                    break
            if not encontrado:
                logger.info(f"Código no encontrado: {codigo_limpio}")
                self.clave_valor.configure(text="")
                self.resultado_valor.configure(text="Código no encontrado")
        except Exception as e:
            logger.error(f"Error al buscar código: {str(e)}")
            self.clave_valor.configure(text="")
            self.resultado_valor.configure(text="Error al buscar código")
        finally:
            self.search_button.configure(text="Buscar")
            self.search_button.configure(state="normal")
            self.codigo_var.set("")
            self.codigo_entry.focus_set()

    def _configurar_captura(self, parent=None):
        frame = parent
        frame.configure(fg_color="#000000")
        label = ct.CTkLabel(frame, text="Captura de cumplimientos", font=("Segoe UI", 15, "bold"), text_color="#00FFAA", fg_color="#000000")
        label.pack(pady=10)
        
        # Variables
        codigo_var = StringVar()
        item_var = StringVar()
        motivo_var = StringVar(value="Instrucciones de cuidado")
        cumple_var = StringVar(value="NO CUMPLE")  # Nuevo: variable para Cumple/No cumple
        usuario = self.usuario
        
        # Campos de entrada
        ct.CTkLabel(frame, text="Código de barras:", text_color="#00FFAA", font=("Segoe UI", 13, "bold"), fg_color="#000000").pack(anchor="w", padx=10)
        codigo_entry = ct.CTkEntry(frame, textvariable=codigo_var, font=("Segoe UI", 13), width=400, height=36, corner_radius=12, border_width=2, border_color="#00FFAA", fg_color="#000000", text_color="#00FFAA")
        codigo_entry.pack(fill="x", padx=10, pady=(0, 8))
        
        ct.CTkLabel(frame, text="Item:", text_color="#00FFAA", font=("Segoe UI", 13, "bold"), fg_color="#000000").pack(anchor="w", padx=10)
        item_entry = ct.CTkEntry(frame, textvariable=item_var, font=("Segoe UI", 13), width=400, height=36, corner_radius=12, border_width=2, border_color="#00FFAA", fg_color="#000000", text_color="#00FFAA")
        item_entry.pack(fill="x", padx=10, pady=(0, 8))
        
        ct.CTkLabel(frame, text="Motivo:", text_color="#00FFAA", font=("Segoe UI", 13, "bold"), fg_color="#000000").pack(anchor="w", padx=10)
        motivo_options = [
            "Instrucciones de cuidado",
            "Insumos",
            "Pais de origen",
            "Talla",
            "Importador",
            "Marca"
        ]
        motivo_menu = ct.CTkOptionMenu(
            frame,
            variable=motivo_var,
            values=motivo_options,
            fg_color="#000000",
            text_color="#00FFAA",
            font=("Segoe UI", 13),
            width=400,
            height=36
        )
        motivo_menu.pack(fill="x", padx=10, pady=(0, 8))
        
        # Nuevo: Menú Cumple/No cumple
        ct.CTkLabel(frame, text="¿Cumple?", text_color="#00FFAA", font=("Segoe UI", 13, "bold"), fg_color="#000000").pack(anchor="w", padx=10)
        cumple_menu = ct.CTkOptionMenu(
            frame,
            variable=cumple_var,
            values=["CUMPLE", "NO CUMPLE"],
            fg_color="#000000",
            text_color="#00FFAA",
            font=("Segoe UI", 13),
            width=400,
            height=36
        )
        cumple_menu.pack(fill="x", padx=10, pady=(0, 8))
        
        ct.CTkLabel(frame, text="Usuario:", text_color="#00FFAA", font=("Segoe UI", 13, "bold"), fg_color="#000000").pack(anchor="w", padx=10)
        usuario_entry = ct.CTkEntry(frame, state="readonly", font=("Segoe UI", 13), width=400, height=36, corner_radius=12, border_width=2, border_color="#00FFAA", fg_color="#000000", text_color="#00FFAA")
        usuario_entry.insert(0, usuario)
        usuario_entry.pack(fill="x", padx=10, pady=(0, 8))
        
        # Estado label
        estado_label = ct.CTkLabel(frame, text="", text_color="#FF3333", font=("Segoe UI", 11, "bold"), fg_color="#000000")
        estado_label.pack(pady=(4, 8))
        
        def guardar_motivo():
            codigo = codigo_var.get().strip()
            item = item_var.get().strip()
            motivo = motivo_var.get().strip()
            cumple = cumple_var.get().strip()  # Nuevo: obtener valor del menú
            if not codigo or not item or not motivo or not cumple:
                estado_label.configure(text="Todos los campos excepto 'Usuario' son obligatorios.", text_color="#FF3333")
                return
            try:
                # Conectar a Google Sheets
                scope = ['https://spreadsheets.google.com/feeds']
                with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as temp_cred:
                    temp_cred.write(CREDENCIALES_JSON.encode('utf-8'))
                    cred_path = temp_cred.name
                creds = ServiceAccountCredentials.from_json_keyfile_name(cred_path, scope)
                client = gspread.authorize(creds)
                os.remove(cred_path)
                # Abrir el spreadsheet y la hoja "CAPTURA DE DATOS"
                spreadsheet = client.open_by_key("1IbUHKUFbSQZY9ZPfwIKFGE5dZ-2zDVqDdn8UvVThExQ")
                try:
                    worksheet = spreadsheet.worksheet("CAPTURA DE DATOS")
                except gspread.exceptions.WorksheetNotFound:
                    estado_label.configure(text="Error: No se encontró la hoja 'CAPTURA DE DATOS' en el spreadsheet.", text_color="#FF3333")
                    return
                encabezado = ["Código", "Item", "Cumple", "Motivo", "Usuario", "Fecha/Hora"]
                # Verificar si la hoja está vacía o la primera fila no es encabezado
                existing_data = worksheet.get_all_values()
                if not existing_data or existing_data[0] != encabezado:
                    if not existing_data:
                        worksheet.insert_row(encabezado, 1)
                    else:
                        worksheet.insert_row(encabezado, 1)
                # Preparar los datos
                from datetime import datetime
                fila = [codigo, item, cumple, motivo, usuario, datetime.now().strftime('%Y-%m-%d %H:%M:%S')]
                worksheet.append_row(fila)
                estado_label.configure(text="¡Motivo guardado en Google Sheets!", text_color="#00FFAA")
                codigo_var.set("")
                item_var.set("")
            except Exception as e:
                estado_label.configure(text=f"Error al guardar en Google Sheets: {str(e)}", text_color="#FF3333")
        
        def descargar_datos():
            try:
                # Conectar a Google Sheets
                scope = ['https://spreadsheets.google.com/feeds']
                with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as temp_cred:
                    temp_cred.write(CREDENCIALES_JSON.encode('utf-8'))
                    cred_path = temp_cred.name
                creds = ServiceAccountCredentials.from_json_keyfile_name(cred_path, scope)
                client = gspread.authorize(creds)
                os.remove(cred_path)
                
                # Abrir el spreadsheet y la hoja "CAPTURA DE DATOS"
                spreadsheet = client.open_by_key("1IbUHKUFbSQZY9ZPfwIKFGE5dZ-2zDVqDdn8UvVThExQ")
                
                try:
                    worksheet = spreadsheet.worksheet("CAPTURA DE DATOS")
                except gspread.exceptions.WorksheetNotFound:
                    estado_label.configure(text="Error: No se encontró la hoja 'CAPTURA DE DATOS' en el spreadsheet.", text_color="#FF3333")
                    return
                
                # Obtener todos los datos
                data = worksheet.get_all_records()
                
                if not data:
                    estado_label.configure(text="No hay datos para descargar en la hoja 'CAPTURA DE DATOS'.", text_color="#FF3333")
                    return
                
                # Crear DataFrame y guardar como Excel
                df = pd.DataFrame(data)
                
                # Solicitar ubicación de guardado
                ruta_guardado = filedialog.asksaveasfilename(
                    defaultextension=".xlsx",
                    filetypes=[("Archivos Excel", "*.xlsx")],
                    title="Guardar Datos Capturados",
                    initialfile="Datos capturados.xlsx"
                )
                
                if ruta_guardado:
                    df.to_excel(ruta_guardado, index=False)
                    estado_label.configure(text=f"¡Datos descargados exitosamente! ({len(data)} registros)", text_color="#00FFAA")
                else:
                    estado_label.configure(text="Descarga cancelada.", text_color="#FF3333")
                    
            except Exception as e:
                estado_label.configure(text=f"Error al descargar datos: {str(e)}", text_color="#FF3333")
        
        # Frame para botones
        botones_frame = ct.CTkFrame(frame, fg_color="#000000")
        botones_frame.pack(pady=20)
        
        # Botón guardar
        guardar_btn = ct.CTkButton(
            botones_frame, 
            text="Guardar motivo", 
            command=guardar_motivo, 
            font=("Segoe UI", 14, "bold"), 
            fg_color="#000000", 
            hover_color="#111111", 
            border_width=2, 
            border_color="#00FFAA", 
            text_color="#00FFAA", 
            corner_radius=12, 
            width=200, 
            height=36
        )
        guardar_btn.pack(side="left", padx=(0, 10))
        
        # Botón descargar (solo para rol captura)
        descargar_btn = ct.CTkButton(
            botones_frame, 
            text="Descargar Datos", 
            command=descargar_datos, 
            font=("Segoe UI", 14, "bold"), 
            fg_color="#000000", 
            hover_color="#111111", 
            border_width=2, 
            border_color="#55DDFF", 
            text_color="#55DDFF", 
            corner_radius=12, 
            width=200, 
            height=36
        )
        descargar_btn.pack(side="left")

        # Botón borrar datos (solo para rol captura)
        if self.rol == "captura":
            def borrar_datos():
                respuesta = messagebox.askyesno(
                    "Confirmar Borrado",
                    "¿Estás dispuesto a borrar TODOS los datos capturados?\nEsta acción no se puede deshacer."
                )
                if not respuesta:
                    estado_label.configure(text="Borrado cancelado.", text_color="#FF3333")
                    return
                try:
                    # Conectar a Google Sheets
                    scope = ['https://spreadsheets.google.com/feeds']
                    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as temp_cred:
                        temp_cred.write(CREDENCIALES_JSON.encode('utf-8'))
                        cred_path = temp_cred.name
                    creds = ServiceAccountCredentials.from_json_keyfile_name(cred_path, scope)
                    client = gspread.authorize(creds)
                    os.remove(cred_path)

                    # Abrir el spreadsheet y la hoja "CAPTURA DE DATOS"
                    spreadsheet = client.open_by_key("1IbUHKUFbSQZY9ZPfwIKFGE5dZ-2zDVqDdn8UvVThExQ")
                    worksheet = spreadsheet.worksheet("CAPTURA DE DATOS")

                    # Borrar todas las filas excepto la cabecera
                    worksheet.resize(rows=1)  # Deja solo la primera fila
                    encabezado = ["Código", "Item", "Cumple", "Motivo", "Usuario", "Fecha/Hora"]
                    worksheet.update('A1:F1', [encabezado])
                    estado_label.configure(text="¡Todos los datos capturados han sido borrados!", text_color="#00FFAA")
                except Exception as e:
                    estado_label.configure(text=f"Error al borrar datos: {str(e)}", text_color="#FF3333")

            borrar_btn = ct.CTkButton(
                botones_frame,
                text="Borrar Datos",
                command=borrar_datos,
                font=("Segoe UI", 14, "bold"),
                fg_color="#000000",
                hover_color="#111111",
                border_width=2,
                border_color="#FF3333",
                text_color="#FF3333",
                corner_radius=12,
                width=200,
                height=36
            )
            borrar_btn.pack(side="left", padx=(10, 0))

    def _configurar_configuracion(self, parent=None):
        frame = parent
        frame.configure(fg_color="#000000")
        ct.CTkLabel(frame, text="Configuración de Archivos", font=("Segoe UI", 18, "bold"), text_color="#00FFAA", fg_color="#000000").pack(pady=(20, 10))
        self.ruta_contenedor_var = StringVar(value=self.config_data.get("contenedor", ""))
        self.ruta_modelos_var = StringVar(value=self.config_data.get("modelos", ""))
        ct.CTkLabel(frame, text="CLP:", text_color="#00FFAA", font=("Segoe UI", 14, "bold"), fg_color="#000000").pack(anchor="w", padx=20, pady=(10,0))
        self.ruta_contenedor_label = ct.CTkLabel(frame, textvariable=self.ruta_contenedor_var, text_color="#55DDFF", wraplength=600, fg_color="#000000")
        self.ruta_contenedor_label.pack(anchor="w", padx=20)
        ct.CTkButton(frame, text="Cargar/Actualizar CLP", command=self.cargar_archivo_contenedor, font=("Segoe UI", 13, "bold"), fg_color="#000000", hover_color="#111111", border_width=2, border_color="#00FFAA", text_color="#00FFAA", corner_radius=12, width=260, height=36).pack(pady=5, padx=20, anchor="w")
        ct.CTkLabel(frame, text="Histórico:", text_color="#00FFAA", font=("Segoe UI", 14, "bold"), fg_color="#000000").pack(anchor="w", padx=20, pady=(10,0))
        self.ruta_modelos_label = ct.CTkLabel(frame, textvariable=self.ruta_modelos_var, text_color="#55DDFF", wraplength=600, fg_color="#000000")
        self.ruta_modelos_label.pack(anchor="w", padx=20)
        ct.CTkButton(frame, text="Cargar/Actualizar Histórico", command=self.cargar_archivo_modelos, font=("Segoe UI", 13, "bold"), fg_color="#000000", hover_color="#111111", border_width=2, border_color="#00FFAA", text_color="#00FFAA", corner_radius=12, width=260, height=36).pack(pady=5, padx=20, anchor="w")

    def cargar_archivo_contenedor(self):
        ruta = filedialog.askopenfilename(filetypes=[("Archivos Excel", "*.xls;*.xlsx"), ("Todos", "*.*")])
        if ruta:
            self.config_data["contenedor"] = ruta
            self.ruta_contenedor_var.set(ruta)
            self.guardar_config()

    def cargar_archivo_modelos(self):
        ruta = filedialog.askopenfilename(filetypes=[("Archivos Excel", "*.xls;*.xlsx"), ("Todos", "*.*")])
        if ruta:
            self.config_data["modelos"] = ruta
            self.ruta_modelos_var.set(ruta)
        self.guardar_config()

CONFIG_PATH = r"C:/Users/bost2/OneDrive/Documents/Caché/config.json"
INDICE_PATH = r"C:/Users/bost2/OneDrive/Documents/Caché/indice.csv"

CREDENCIALES_JSON = """
{
  "type": "service_account",
  "project_id": "onyx-window-462722-h1",
  "private_key_id": "26ffc309b8152949c428e0c1ab01c89ae318bac3",
  "private_key": "-----BEGIN PRIVATE KEY-----\\nMIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDJtnw2kV+6ofTd\\nsyODHBr6+XieJyhwuFnQf4KHm9ZM97KTcK/f5r13o56eawqa63KcwucAzpZbyaB5\\nAjkI9wnrERB4mcQe4pLe2fLzB5vDdYmvZS9Ujc4/cneSDy7ucaVlfr3Iiaa1cM3k\\nijZLOvjR9svAXkWHRI7Xl/Edhd6WfcCI3N63SMd9zd12/O3e2WbCtLwVXauP0oWD\\n5Q5u9kjdLyGSr+A0/4x+U0iVGJGuQl1CmErOCvIwHM2kl74PPLjfLQdXYFijLYeM\\nPbwTvQNeOn6bZ1rzVemmzj2/F+YgmRn3z/gHVRhfEuf5ZT1sOVyHXzIFl1eplNJT\\nSt+I3PRjAgMBAAECggEAESjVgJzgVxOlAuEqPGKShwGG+clHVEN9MdKka4iIdAFp\\nrxzvJph4oL9fZIb4SX04bE6GRpghzArR0cmByZnzvYwKPyrcN2u7O9BbAxgFb7Ia\\n4DwMM+C2XXO4Pp7NCsV0i7b69R7Z+uXEQNS4fAY3GZbUTCKY6UId9rLlykb+TFtH\\n8TIDX7L6UEXcUEMfuRs7rQ2Wy55BWAYRORZsszxDGrBeZ08QK2f6laGl2maX866G\\nCxgxtWV415tqOUQjsb9cuaKMNOINKPeYdAhLr9Jg/cY4+a4Gx0QvQn4GKO9RiZbZ\\n1Wk3wuOAAc5mtnlHAaTCA7LsiP+bnO7PRAIGMHgE7QKBgQDjTSCGpIVS7rtRhj1U\\nnQTWug7y6g+R26BT9BArwBR6pLcUtM53T8kKdsROaYHZJ46Q6yLX8rDB+DGHFdVX\\nn8cwDPXKdsfO6cXLnOy9PFMzSp8VHLoEhIkGCjLpVEJyBMCnn3nbKHCdpAW6sV16\\nxh3P8JU4MZXlNZ23f+b5jJXnBwKBgQDjLkioiOD63WpsAawLxA43BDRQduQrZmxA\\nzKqBXjqePwtKGQY4upgjMkJXSCrdzIOU68NCCMefa5poGZsqQ+FjpKE1U7crwJw4\\n0WmTDx/Be6O8Fx/d0OPuWTGikk0d7NKx9b+OKxDjBtvGpyZTyKAw7G2/Jgv2/kAm\\nrFysLNV0xQKBgGUqocxrk0+LI+IwHkH3tPyhSSAC3zUrDFvxZ/UhA7xmbXoQ00g1\\nQaSfodXIjduKCKEllpeI0/UxM1INfKwIWE5hplAbt+i3EasDSDcdj2Zn0xBBfeWe\\n26HNjkVdlElNJjY0+7Z4dE8lfstOP+3yGbjAOpoNL8sZpv3SNophcSKnAoGARA2p\\nVlMqkfuh1ZjqoNuqJnDr+u6iix2zb/XfXcGMbbsU9q1oX7YFvQVhOiQ0Mx0AjavS\\nYgWfRvJE3spM4OxUqDS41fCt/j1EjwCsT5FIQf13nvCOazQYE15EsB6DW2OF+ilT\\nqJLeDCQR0gBgStjeo8kvVwNesi6XqP4ZBLqpdsECgYBaSFtEUTwf81hjHtR0KVgc\\n/h66V3MvhGEbEdgqUIXuZdcZtaZqDnUCmhH+lL8hmhHY+ttOYEGyWv2pWZjnXU2Z\\n1TGZPfzPC/WCts4BMTGEM3pB0tnEfl5UsHIZI10Aqv0pVQKivTRUaQJtUj9qW39V\\nERuYTFCpSn3/5bz7H3kHFA==\\n-----END PRIVATE KEY-----\\n",
  "client_email": "v-ccodigo@onyx-window-462722-h1.iam.gserviceaccount.com",
  "client_id": "105084067125623318167",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/v-ccodigo%40onyx-window-462722-h1.iam.gserviceaccount.com",
  "universe_domain": "googleapis.com"
}
"""

SPREADSHEET_ID_CODIGOS = "1gu1mvOLjG8Tt-HbkeG-xn5vLSU1zybEl3nrccbK05cU"
SPREADSHEET_ID_ITEMS = "1y6UeTHnfrhhbsdyV3uR4NRg5bQD1hfqV42p6BNTJYqE"

if __name__ == "__main__":
    root = ct.CTk()
    root.title("Escáner de Códigos V&C")
    root.geometry("900x700")
    root.resizable(True, True)
    def on_login_success(usuario, rol):
        for widget in root.winfo_children():
            widget.destroy()
        app = BuscadorApp(root, usuario, rol)
    login = LoginWindow(root, on_success=on_login_success)
    root.mainloop() 
