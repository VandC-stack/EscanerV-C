import customtkinter as ct
from tkinter import StringVar, messagebox, filedialog, ttk, simpledialog
from PIL import Image
import os
import sys
import threading
from datetime import datetime
import time
import logging
from typing import Dict, List, Optional
import pandas as pd
import re
import math
import hashlib
import json
import subprocess
try:
    from tkcalendar import DateEntry 
except ImportError:
    DateEntry = None

# Configuración de la aplicación
ct.set_appearance_mode("dark")
ct.set_default_color_theme("dark-blue")

# Constantes de versión
VERSION_ACTUAL = "0.3.3"
FECHA_COMPILACION = "2024-07-10"

# Configuración de logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Importar módulos de la nueva arquitectura
from config.database import DatabaseManager
from models.usuario import Usuario
from models.codigo_item import CodigoItem
from models.captura import Captura
from utils.logger import AppLogger
from utils.validators import Validators

print("Default encoding:", sys.getdefaultencoding())
print("Filesystem encoding:", sys.getfilesystemencoding())

# --- FUNCIÓN UTILITARIA PARA ACTUALIZAR WIDGETS DE FORMA SEGURA ---
def safe_configure(widget, **kwargs):
    try:
        if widget and widget.winfo_exists():
            widget.configure(**kwargs)
    except Exception:
        pass  # El widget ya no existe o la ventana fue destruida

class EscanerApp:
    def __init__(self):
        self.root = ct.CTk()
        self.root.title("Escáner V&C v0.3.2")
        self.root.geometry("1000x800")
        self.root.resizable(True, True)
        
        # Inicializar componentes
        self.db_manager = None
        self.logger = None
        self.usuario_model = None
        self.codigo_model = None
        self.captura_model = None
        
        # Variables de estado
        self.usuario_actual = None
        self.rol_actual = None
        self.config_data = {}
        
        # Inicializar aplicación
        self.inicializar_aplicacion()
    
    def inicializar_aplicacion(self):
        """Inicializa todos los componentes de la aplicación"""
        try:
            # Inicializar base de datos
            self.db_manager = DatabaseManager()
            
            # Intentar arreglar problemas de codificación
            try:
                if not self.db_manager.fix_encoding_issues():
                    print("Advertencia: No se pudieron arreglar problemas de codificación")
            except Exception as encoding_error:
                print(f"Error arreglando codificación: {str(encoding_error)}")
            
            # Crear tablas si no existen
            self.db_manager.create_tables()
            
            # Insertar datos por defecto (incluye usuario admin)
            self.db_manager.insert_default_data()
            
            # Inicializar logger
            self.logger = AppLogger("EscanerApp")
            
            # Inicializar modelos
            self.usuario_model = Usuario(self.db_manager)
            self.codigo_model = CodigoItem(self.db_manager)
            self.captura_model = Captura(self.db_manager)
            
            # Cargar configuración
            self.cargar_configuracion()
            
            # Mostrar ventana de login
            self.mostrar_login()
            
            self.logger.info("Aplicación inicializada correctamente")
            
        except Exception as e:
            # Manejar el caso donde el logger no está inicializado
            try:
                if hasattr(self, 'logger') and self.logger:
                    self.logger.error(f"Error inicializando aplicación: {str(e)}")
                else:
                    print(f"Error inicializando aplicación: {str(e)}")
            except:
                print(f"Error inicializando aplicación: {str(e)}")
            
            try:
                messagebox.showerror("Error", f"Error al inicializar la aplicación: {str(e)}")
            except:
                print(f"Error al inicializar la aplicación: {str(e)}")
            
            try:
                self.root.destroy()
            except:
                pass
    
    def cargar_configuracion(self):
        """Carga la configuración desde la base de datos"""
        try:
            result = self.db_manager.execute_query(
                "SELECT clave, valor FROM configuracion"
            )
            
            for row in result:
                self.config_data[row['clave']] = row['valor']
                
        except Exception as e:
            try:
                if hasattr(self, 'logger') and self.logger:
                    self.logger.error(f"Error cargando configuración: {str(e)}")
                else:
                    print(f"Error cargando configuración: {str(e)}")
            except:
                print(f"Error cargando configuración: {str(e)}")
    
    def mostrar_login(self):
        """Muestra la ventana de login"""
        for widget in self.root.winfo_children():
            widget.destroy()
        
        self.login_window = LoginWindow(self.root, self.usuario_model, self.logger, self.on_login_success)
    
    def on_login_success(self, usuario: str, rol: str):
        """Callback cuando el login es exitoso"""
        self.usuario_actual = usuario
        self.rol_actual = rol
        
        try:
            self.logger.log_user_action(usuario, "Login exitoso")
        except Exception as e:
            print(f"Error registrando login: {str(e)}")
        
        # Mostrar ventana principal
        self.mostrar_ventana_principal()
    
    def mostrar_ventana_principal(self):
        """Muestra la ventana principal de la aplicación"""
        try:
            for widget in self.root.winfo_children():
                widget.destroy()
            
            self.main_window = MainWindow(
                self.root, 
                self.usuario_actual, 
                self.rol_actual,
                self.codigo_model,
                self.captura_model,
                self.logger,
                self.config_data,
                self.usuario_model,
                self.db_manager
            )
        except Exception as e:
            try:
                if hasattr(self, 'logger') and self.logger:
                    self.logger.error(f"Error mostrando ventana principal: {str(e)}")
                else:
                    print(f"Error mostrando ventana principal: {str(e)}")
            except:
                print(f"Error mostrando ventana principal: {str(e)}")
            
            try:
                messagebox.showerror("Error", f"Error al mostrar la ventana principal: {str(e)}")
            except:
                print(f"Error al mostrar la ventana principal: {str(e)}")
    
    def ejecutar(self):
        """Ejecuta la aplicación"""
        self.root.mainloop()

    def mostrar_historial_cargas_y_consultas(self):
        import tkinter as tk
        from tkinter import ttk, filedialog
        import customtkinter as ct
        import pandas as pd
        # Crear ventana toplevel
        top = ct.CTkToplevel(self.master)
        top.title("Historial del día")
        top.geometry("700x700")
        top.configure(fg_color="#000000")
        top.lift()
        top.attributes('-topmost', True)
        top.focus_force()

        # Frame principal
        main_frame = ct.CTkFrame(top, fg_color="#000000")
        main_frame.pack(fill="both", expand=True, padx=20, pady=20)

        # Filtro por nombre de archivo
        filtro_var = tk.StringVar()
        def actualizar_cargas(*args):
            filtro = filtro_var.get().strip().lower()
            try:
                if filtro:
                    # Buscar en todo el historial por coincidencia de nombre de archivo
                    query_cargas = "SELECT archivo, usuario, fecha_carga, codigos_agregados FROM clp_cargas WHERE LOWER(archivo) LIKE %s ORDER BY fecha_carga DESC"
                    cargas = self.db_manager.execute_query(query_cargas, (f"%{filtro}%",))
                else:
                    # Solo mostrar las cargas del día actual
                    query_cargas = "SELECT archivo, usuario, fecha_carga, codigos_agregados FROM clp_cargas WHERE fecha_carga::date = CURRENT_DATE ORDER BY fecha_carga DESC"
                    cargas = self.db_manager.execute_query(query_cargas)
            except Exception as e:
                cargas = []
            cargas_text = "Sin cargas."
            if cargas:
                cargas_text = "\n".join([
                    f"{c['fecha_carga']}: {c['archivo']} (Usuario: {c['usuario']}, Códigos: {c['codigos_agregados']})" for c in cargas
                ])
            cargas_label.configure(state="normal")
            cargas_label.delete("1.0", tk.END)
            cargas_label.insert("1.0", cargas_text)
            cargas_label.configure(state="disabled")

        filtro_frame = ct.CTkFrame(main_frame, fg_color="#000000")
        filtro_frame.pack(fill="x", pady=(0, 5))
        ct.CTkLabel(filtro_frame, text="Filtrar por archivo:", text_color="#00FFAA").pack(side="left", padx=(0, 8))
        filtro_entry = ct.CTkEntry(filtro_frame, textvariable=filtro_var, width=200)
        filtro_entry.pack(side="left")
        filtro_var.trace_add('write', lambda *args: actualizar_cargas())

        # Sección de cargas CLP
        ct.CTkLabel(
            main_frame, text="Cargas CLP del día:", font=("Segoe UI", 16, "bold"), text_color="#00FFAA", fg_color="#000000"
        ).pack(anchor="w", pady=(0, 5))
        cargas_label = ct.CTkTextbox(main_frame, width=650, height=60, fg_color="#111111", text_color="#00FFAA", font=("Segoe UI", 12))
        cargas_label.pack(pady=(0, 15))
        actualizar_cargas()

        # Sección de consultas recientes
        ct.CTkLabel(
            main_frame, text="Consultas recientes:", font=("Segoe UI", 16, "bold"), text_color="#00FFAA", fg_color="#000000"
        ).pack(anchor="w", pady=(0, 5))
        try:
            query_consultas = "SELECT fecha_hora, usuario, codigo_barras, resultado FROM consultas WHERE fecha_hora::date = CURRENT_DATE ORDER BY fecha_hora DESC LIMIT 50"
            consultas = self.db_manager.execute_query(query_consultas)
        except Exception as e:
            consultas = []
        # Tabla de consultas
        table_frame = ct.CTkFrame(main_frame, fg_color="#111111")
        table_frame.pack(fill="both", expand=True, pady=(0, 10))
        columns = ("Fecha/Hora", "Usuario", "Código de Barras", "Resultado")
        tree = ttk.Treeview(table_frame, columns=columns, show="headings", height=12)
        for col in columns:
            tree.heading(col, text=col)
        # Estilo ttk para fondo oscuro y tipo Excel
        style = ttk.Style()
        style.theme_use('default')
        style.configure("Treeview",
                        background="#111111",
                        foreground="#00FFAA",
                        rowheight=24,
                        fieldbackground="#111111",
                        font=("Segoe UI", 11),
                        bordercolor="#222222",
                        borderwidth=1)
        style.configure("Treeview.Heading",
                        background="#00FFAA",
                        foreground="#000000",
                        font=("Segoe UI", 13, "bold"),
                        relief="flat")
        style.map('Treeview', background=[('selected', '#222222')])
        style.layout("Treeview", [
            ('Treeview.treearea', {'sticky': 'nswe'})
        ])
        # Ajustar ancho de columnas
        tree.column("Fecha/Hora", width=160, anchor="center")
        tree.column("Usuario", width=100, anchor="center")
        tree.column("Código de Barras", width=220, anchor="center")
        tree.column("Resultado", width=120, anchor="center")
        # Insertar datos con rayado
        for i, c in enumerate(consultas):
            values = (c['fecha_hora'], c['usuario'], c['codigo_barras'], c['resultado'] or "Sin resultado")
            tag = 'evenrow' if i % 2 == 0 else 'oddrow'
            tree.insert("", "end", values=values, tags=(tag,))
        tree.tag_configure('evenrow', background='#181818')
        tree.tag_configure('oddrow', background='#222222')
        # Scrollbar
        scrollbar = ttk.Scrollbar(table_frame, orient="vertical", command=tree.yview)
        tree.configure(yscrollcommand=scrollbar.set)
        tree.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        # Sección de capturas del día
        ct.CTkLabel(
            main_frame, text="Capturas del día:", font=("Segoe UI", 16, "bold"), text_color="#00FFAA", fg_color="#000000"
        ).pack(anchor="w", pady=(10, 5))
        # Tabla de capturas
        capturas_frame = ct.CTkFrame(main_frame, fg_color="#111111")
        capturas_frame.pack(fill="both", expand=True, pady=(0, 10))
        columns = ("Fecha/Hora", "Usuario", "Código", "Item", "Resultado", "Motivo")
        capturas_tree = ttk.Treeview(capturas_frame, columns=columns, show="headings", height=8)
        for col in columns:
            capturas_tree.heading(col, text=col)
        # Estilo ttk para fondo oscuro
        style = ttk.Style()
        style.theme_use('default')
        style.configure("Treeview",
                        background="#111111",
                        foreground="#00FFAA",
                        rowheight=24,
                        fieldbackground="#111111",
                        font=("Segoe UI", 11),
                        bordercolor="#222222",
                        borderwidth=1)
        style.configure("Treeview.Heading",
                        background="#00FFAA",
                        foreground="#000000",
                        font=("Segoe UI", 13, "bold"),
                        relief="flat")
        style.map('Treeview', background=[('selected', '#222222')])
        style.layout("Treeview", [
            ('Treeview.treearea', {'sticky': 'nswe'})
        ])
        # Ajustar ancho de columnas
        capturas_tree.column("Fecha/Hora", width=140, anchor="center")
        capturas_tree.column("Usuario", width=80, anchor="center")
        capturas_tree.column("Código", width=160, anchor="center")
        capturas_tree.column("Item", width=80, anchor="center")
        capturas_tree.column("Resultado", width=100, anchor="center")
        capturas_tree.column("Motivo", width=160, anchor="center")
        # Consultar capturas del día
        try:
            query_capturas = "SELECT fecha, usuario, codigo, item, cumple, motivo FROM capturas WHERE fecha::date = CURRENT_DATE ORDER BY fecha DESC"
            capturas = self.db_manager.execute_query(query_capturas)
        except Exception as e:
            capturas = []
        for i, c in enumerate(capturas):
            values = (
                c['fecha'], c['usuario'], c['codigo'], c['item'], c['cumple'], c['motivo'] or ""
            )
            tag = 'evenrow' if i % 2 == 0 else 'oddrow'
            capturas_tree.insert("", "end", values=values, tags=(tag,))
        capturas_tree.tag_configure('evenrow', background='#181818')
        capturas_tree.tag_configure('oddrow', background='#222222')
        # Scrollbar
        scrollbar = ttk.Scrollbar(capturas_frame, orient="vertical", command=capturas_tree.yview)
        capturas_tree.configure(yscrollcommand=scrollbar.set)
        capturas_tree.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        # Botón cerrar
        cerrar_btn = ct.CTkButton(
            main_frame, text="Cerrar", command=top.destroy,
            font=("Segoe UI", 14, "bold"), fg_color="#00FFAA", text_color="#000000",
            width=200, height=40, corner_radius=12
        )
        cerrar_btn.pack(pady=10)

        # Botón historial del día
        self.historial_button = ct.CTkButton(
            parent,
            text="Ver Historial del Día",
            font=("Segoe UI", 12, "bold"),
            fg_color="#111111",
            hover_color="#55DDFF",
            border_width=2,
            border_color="#55DDFF",
            text_color="#55DDFF",
            corner_radius=12,
            width=200,
            height=32,
            command=self.mostrar_historial_cargas_y_consultas
        )
        self.historial_button.pack(pady=(0, 18))

        # Botón solo para admins: Exportar Reporte del Día
        if self.rol == "admin":
            self.exportar_reporte_button = ct.CTkButton(
                parent,
                text="Exportar Reporte del Día",
                font=("Segoe UI", 12, "bold"),
                fg_color="#111111",
                hover_color="#55DDFF",
                border_width=2,
                border_color="#55DDFF",
                text_color="#55DDFF",
                corner_radius=12,
                width=200,
                height=32,
                command=self.exportar_reporte_dia
            )
            self.exportar_reporte_button.pack(pady=(0, 10))
        else:
            self.exportar_reporte_button = None

        # Botón Exportar Capturas del Día (para todos los roles)
        def exportar_capturas():
            import tkinter as tk
            from tkinter import filedialog, messagebox
            from datetime import datetime
            top = tk.Toplevel(self.master)
            top.title("Seleccionar día para exportar capturas")
            top.geometry("400x220")
            top.configure(bg="#000000")  # Fondo negro

            label = tk.Label(
                top, text="Selecciona la fecha:",
                font=("Segoe UI", 16, "bold"),
                fg="#00FFAA", bg="#000000"
            )
            label.pack(pady=20)

            if DateEntry:
                cal = DateEntry(
                    top, width=18, background='#111111', foreground='#00FFAA',
                    borderwidth=2, date_pattern='yyyy-mm-dd',
                    font=("Segoe UI", 14), headersbackground="#222222", headersforeground="#00FFAA"
                )
                cal.pack(pady=10)
            else:
                tk.Label(
                    top, text="Instala tkcalendar para selector visual",
                    fg="red", bg="#000000", font=("Segoe UI", 12, "bold")
                ).pack(pady=10)
                cal = None

            def exportar():
                fecha = cal.get_date().strftime('%Y-%m-%d') if cal else None
                if not fecha:
                    messagebox.showerror("Error", "Selecciona una fecha válida.")
                    return
                try:
                    query_capturas = "SELECT fecha, usuario, codigo, item, cumple, motivo FROM capturas WHERE fecha::date = %s ORDER BY fecha DESC"
                    capturas = self.db_manager.execute_query(query_capturas, (fecha,))
                except Exception as e:
                    capturas = []
                if not capturas:
                    messagebox.showinfo("Sin datos", f"No hay capturas para el día {fecha}")
                    return
                import pandas as pd
                df = pd.DataFrame(capturas)
                ruta = filedialog.asksaveasfilename(
                    defaultextension=".xlsx",
                    filetypes=[("Archivos Excel", "*.xlsx")],
                    initialfile=f"capturas_{fecha}.xlsx",
                    title="Guardar capturas como..."
                )
                if not ruta:
                    return
                df.to_excel(ruta, index=False)
                messagebox.showinfo("Éxito", f"Capturas exportadas: {ruta}")
                top.destroy()

            export_btn = tk.Button(
                top, text="Exportar", command=exportar,
                font=("Segoe UI", 14, "bold"),
                bg="#00FFAA", fg="#000000", activebackground="#00FFAA", activeforeground="#000000",
                relief="flat", borderwidth=0, width=16, height=2
            )
            export_btn.pack(pady=20)

        self.exportar_capturas_button = ct.CTkButton(
            parent,
            text="Exportar Capturas del Día",
            font=("Segoe UI", 14, "bold"),
            fg_color="#00FFAA",
            text_color="#000000",
            width=200,
            height=40,
            corner_radius=12,
            command=exportar_capturas
        )
        self.exportar_capturas_button.pack(pady=(0, 10))
    
    def exportar_reporte_dia(self):
        import tkinter as tk
        from tkinter import filedialog
        top = tk.Toplevel(self.master)
        top.title("Seleccionar día para reporte")
        top.geometry("400x220")
        top.configure(bg="#000000")  # Fondo negro

        label = tk.Label(
            top, text="Selecciona la fecha:",
            font=("Segoe UI", 16, "bold"),
            fg="#00FFAA", bg="#000000"
        )
        label.pack(pady=20)

        if DateEntry:
            cal = DateEntry(
                top, width=18, background='#111111', foreground='#00FFAA',
                borderwidth=2, date_pattern='yyyy-mm-dd',
                font=("Segoe UI", 14), headersbackground="#222222", headersforeground="#00FFAA"
            )
            cal.pack(pady=10)
        else:
            tk.Label(
                top, text="Instala tkcalendar para selector visual",
                fg="red", bg="#000000", font=("Segoe UI", 12, "bold")
            ).pack(pady=10)
            cal = None

        def exportar():
            fecha = cal.get_date().strftime('%Y-%m-%d') if cal else None
            if not fecha:
                messagebox.showerror("Error", "Selecciona una fecha válida.")
                return
            try:
                query = """
                    SELECT usuario, codigo_barras, item_id, resultado, fecha_hora
                    FROM consultas
                    WHERE fecha_hora::date = %s
                    ORDER BY fecha_hora DESC
                """
                resultados = self.db_manager.execute_query(query, (fecha,))
                if not resultados:
                    messagebox.showinfo("Sin datos", f"No hay consultas para el día {fecha}")
                    return
                df = pd.DataFrame(resultados)
                ruta = filedialog.asksaveasfilename(
                    defaultextension=".xlsx",
                    filetypes=[("Archivos Excel", "*.xlsx")],
                    initialfile=f"reporte_consultas_{fecha}.xlsx",
                    title="Guardar reporte como..."
                )
                if not ruta:
                    return
                df.to_excel(ruta, index=False)
                messagebox.showinfo("Éxito", f"Reporte exportado: {ruta}")
                top.destroy()
            except Exception as e:
                messagebox.showerror("Error", f"Error exportando reporte: {str(e)}")

        export_btn = tk.Button(
            top, text="Exportar", command=exportar,
            font=("Segoe UI", 14, "bold"),
            bg="#00FFAA", fg="#000000", activebackground="#00FFAA", activeforeground="#000000",
            relief="flat", borderwidth=0, width=16, height=2
        )
        export_btn.pack(pady=20)
    
    def cerrar_sesion(self):
        """Cierra la sesión y regresa a la pantalla de login"""
        try:
            self.logger.log_user_action(self.usuario, "Cerrar sesión")
            self.master.destroy()
            app = EscanerApp()
            app.ejecutar()
        except Exception as e:
            print(f"Error al cerrar sesión: {str(e)}")
    
    def buscar_codigo(self):
        import os
        codigo = self.codigo_var.get().strip()
        # Easter egg: si el usuario escribe 'tetris', lanza el minijuego
        if codigo.lower() == 'tetris':
            try:
                subprocess.Popen(['python', os.path.join('tetris', 'tetris.py')])
            except Exception as e:
                messagebox.showerror("Error", f"No se pudo iniciar Tetris: {e}")
            self.codigo_var.set("")
            self.codigo_entry.focus_set()
            return
        es_valido, mensaje = Validators.validar_codigo_barras(codigo)
        if not es_valido:
            self.resultado_valor.configure(text=mensaje)
            self.clave_valor.configure(text="")
            self.codigo_var.set("")
            self.codigo_entry.focus_set()
            return
        codigo_limpio = Validators.limpiar_codigo_barras(codigo)
        self.search_button.configure(state="disabled", text="Buscando...")
        threading.Thread(target=self._ejecutar_busqueda_nueva, args=(codigo_limpio,), daemon=True).start()

    def _ejecutar_busqueda_nueva(self, codigo):
        try:
            resultado = self.codigo_model.buscar_codigo(codigo)
            if resultado:
                self.master.after(0, lambda: self._mostrar_resultado(resultado))
                # Registrar consulta
                item_id = None
                item = resultado.get('item')
                if item:
                    res = self.db_manager.execute_query("SELECT id FROM items WHERE item = %s", (item,))
                    if res:
                        item_id = res[0]['id']
                self.captura_model.registrar_consulta(self.usuario, codigo, item_id, resultado.get('resultado', ''))
                self.logger.log_user_action(self.usuario, f"Búsqueda exitosa: {codigo}")
            else:
                self.master.after(0, lambda: self._mostrar_no_encontrado())
                self.logger.log_user_action(self.usuario, f"Búsqueda sin resultados: {codigo}")
        except Exception as e:
            self.logger.error(f"Error en búsqueda: {str(e)}")
            self.master.after(0, lambda: self._mostrar_error_busqueda(str(e)))
        finally:
            self.master.after(0, lambda: self._restaurar_boton_busqueda())

    def _mostrar_resultado(self, resultado):
        """Muestra el resultado de la búsqueda"""
        self.clave_valor.configure(text=f"ITEM: {resultado.get('item', '')}")
        res = resultado.get('resultado', 'Sin resultado') or 'Sin resultado'
        self.resultado_valor.configure(text=f"RESULTADO: {res}")
        # Mostrar motivo solo si es NO CUMPLE
        if res == 'NO CUMPLE':
            item = resultado.get('item', '')
            item_id_res = self.db_manager.execute_query("SELECT id FROM items WHERE item = %s", (item,))
            if item_id_res:
                item_id = item_id_res[0]['id']
                motivo = self.db_manager.execute_query("SELECT motivo FROM motivos_no_cumplimiento WHERE item_id = %s", (item_id,))
                if motivo and motivo[0].get('motivo'):
                    self.nom_valor.configure(text=motivo[0]['motivo'])
                    return
        self.nom_valor.configure(text="")
    
    def _mostrar_no_encontrado(self):
        """Muestra mensaje de no encontrado"""
        self.clave_valor.configure(text="")
        self.resultado_valor.configure(text="Código no encontrado")
        self.nom_valor.configure(text="")
    
    def _mostrar_error_busqueda(self, error):
        """Muestra error en la búsqueda"""
        self.clave_valor.configure(text="")
        self.resultado_valor.configure(text=f"Error al buscar: {error}")
        self.nom_valor.configure(text="")
    
    def _restaurar_boton_busqueda(self):
        """Restaura el botón de búsqueda"""
        safe_configure(self.search_button, text="Buscar", state="normal")
        self.codigo_var.set("")
        self.codigo_entry.focus_set()
    
    def cargar_estadisticas(self):
        """Carga las estadísticas de la base de datos"""
        try:
            stats = self.codigo_model.obtener_estadisticas()
            if isinstance(stats, dict):
                self.total_codigos_label.configure(text=f"Total de códigos: {stats.get('total_codigos', 0)}")
                self.con_resultado_label.configure(text=f"Items en total: {stats.get('total_items', 0)}")
                self.sin_resultado_label.configure(text=f"Sin resultado: {stats.get('sin_resultado', 0)}")
                self.ultima_actualizacion_label.configure(text=f"Última actualización: {stats.get('ultima_actualizacion', 'Nunca')}")
            else:
                self.total_codigos_label.configure(text="Total de códigos: 0")
                self.con_resultado_label.configure(text="Items en total: 0")
                self.sin_resultado_label.configure(text="Sin resultado: 0")
                self.ultima_actualizacion_label.configure(text="Última actualización: Nunca")
        except Exception as e:
            self.logger.error(f"Error cargando estadísticas: {str(e)}")
            self.total_codigos_label.configure(text="Total de códigos: 0")
            self.con_resultado_label.configure(text="Items en total: 0")
            self.sin_resultado_label.configure(text="Sin resultado: 0")
            self.ultima_actualizacion_label.configure(text="Última actualización: Nunca")
    
    def actualizar_indice(self):
        es_valido, mensaje = Validators.validar_configuracion_completa(self.config_data)
        if not es_valido:
            messagebox.showerror("Error", mensaje)
            return
        rutas = filedialog.askopenfilenames(
            filetypes=[("Archivos Excel", "*.xls;*.xlsx"), ("Todos", "*.*")],
            title="Seleccionar uno o varios archivos CLP"
        )
        if rutas:
            threading.Thread(target=self._ejecutar_actualizacion_varios, args=(rutas,), daemon=True).start()

    def _ejecutar_actualizacion_varios(self, rutas):
        try:
            self.master.after(0, lambda: self.update_button.configure(state="disabled", text="Actualizando..."))
            resultado = self.codigo_model.cargar_varios_clp(rutas, self.usuario_actual)
            if not isinstance(resultado, dict):
                resultado = {'procesados': 0, 'nuevos_items': 0, 'nuevos_codigos': 0, 'clp_registros': []}
            self.master.after(0, lambda: self._mostrar_resultado_actualizacion(resultado))
            cargas = resultado.get('clp_registros', [])
            if cargas:
                msg = '\n'.join([f"Archivo: {os.path.basename(c['archivo'])}, Usuario: {c['usuario']}, Códigos agregados: {c['codigos_agregados']}" for c in cargas])
                print("Cargas CLP del día:\n" + msg)
            self.logger.log_user_action(self.usuario, "Índice actualizado", f"Registros: {resultado.get('procesados', 0)}")
        except Exception as e:
            self.logger.error(f"Error actualizando índice: {str(e)}")
            self.master.after(0, lambda e=e: messagebox.showerror("Error", f"Error al actualizar índice: {str(e)}"))
        finally:
            self.master.after(0, lambda: self.update_button.configure(state="normal", text="Actualizar Índice"))
            self.master.after(0, self.cargar_estadisticas)
    
    def _mostrar_resultado_actualizacion(self, resultado):
        """Muestra el resultado de la actualización del índice"""
        try:
            if isinstance(resultado, dict):
                mensaje = f"Índice actualizado exitosamente.\n"
                mensaje += f"Nuevos registros: {resultado.get('nuevos_items', 0)}\n"
                mensaje += f"Total de códigos: {resultado.get('nuevos_codigos', 0)}\n"
                mensaje += f"Total procesados: {resultado.get('procesados', 0)}\n"
                messagebox.showinfo("Éxito", mensaje)
            else:
                messagebox.showinfo("Éxito", f"Índice actualizado: {resultado}")
        except Exception as e:
            self.logger.error(f"Error mostrando resultado: {str(e)}")
            messagebox.showerror("Error", f"Error al actualizar índice: {str(e)}")
    
    def _configurar_tab_captura(self, parent):
        # Scrollable frame principal con mejor configuración
        main_frame = ct.CTkScrollableFrame(parent, fg_color="#000000", width=800, height=600)
        main_frame.pack(fill="both", expand=True, padx=20, pady=20)
        
        # Título
        ct.CTkLabel(
            main_frame, 
            text="Captura de Cumplimientos", 
            font=("Segoe UI", 18, "bold"), 
            text_color="#00FFAA"
        ).pack(pady=(0, 20))
        
        # Botón para subir capturas pendientes (solo admin y captura) ANTES de los campos
        if self.rol in ["admin", "captura"]:
            self.subir_pendientes_btn = ct.CTkButton(
                main_frame,
                text="Subir capturas pendientes",
                command=self.subir_capturas_offline,
                font=("Segoe UI", 12, "bold"),
                fg_color="#00FFAA",
                text_color="#000000",
                border_width=2,
                border_color="#00FFAA",
                corner_radius=10
            )
            self.subir_pendientes_btn.pack(pady=(0, 10))
            self._actualizar_estado_pendientes()
        
        # Variables
        self.codigo_captura_var = StringVar()
        self.item_captura_var = StringVar()
        self.motivo_captura_var = StringVar(value="Instrucciones de cuidado")
        self.cumple_captura_var = StringVar(value="NO CUMPLE")
        
        # Frame para campos de entrada
        campos_frame = ct.CTkFrame(main_frame, fg_color="#000000")
        campos_frame.pack(fill="x", pady=(0, 20))
        
        # Código de barras
        ct.CTkLabel(
            campos_frame, 
            text="Código de barras:", 
            text_color="#00FFAA", 
            font=("Segoe UI", 13, "bold")
        ).pack(anchor="w", padx=10, pady=(10, 0))
        
        self.codigo_captura_entry = ct.CTkEntry(
            campos_frame, 
            textvariable=self.codigo_captura_var,
            font=("Segoe UI", 13),
            width=400,
            height=36,
            corner_radius=12,
            border_width=2,
            border_color="#00FFAA",
            fg_color="#000000",
            text_color="#00FFAA"
        )
        self.codigo_captura_entry.pack(fill="x", padx=10, pady=(0, 8))
        
        # Evento para buscar automáticamente el item cuando se
        self.codigo_captura_entry.bind("<Return>", lambda e: self._buscar_item_automatico())
        
        # Item
        ct.CTkLabel(
            campos_frame, 
            text="Item:", 
            text_color="#00FFAA", 
            font=("Segoe UI", 13, "bold")
        ).pack(anchor="w", padx=10, pady=(10, 0))
        self.item_captura_entry = ct.CTkEntry(
            campos_frame, 
            textvariable=self.item_captura_var,
            font=("Segoe UI", 13),
            width=400,
            height=36,
            corner_radius=12,
            border_width=2,
            border_color="#00FFAA",
            fg_color="#000000",
            text_color="#00FFAA",
            state="disabled"  # <-- Solo lectura
        )
        self.item_captura_entry.pack(fill="x", padx=10, pady=(0, 8))
        
        # Cumple/No cumple SIEMPRE visible
        ct.CTkLabel(
            campos_frame, 
            text="¿Cumple?", 
            text_color="#00FFAA", 
            font=("Segoe UI", 13, "bold")
        ).pack(anchor="w", padx=10, pady=(10, 0))
        self.cumple_captura_menu = ct.CTkOptionMenu(
            campos_frame,
            variable=self.cumple_captura_var,
            values=["CUMPLE", "NO CUMPLE"],
            fg_color="#000000",
            text_color="#00FFAA",
            font=("Segoe UI", 13),
            width=400,
            height=36
        )
        self.cumple_captura_menu.pack(fill="x", padx=10, pady=(0, 8))

        # Frame para motivo y botón guardar
        motivo_guardar_frame = ct.CTkFrame(campos_frame, fg_color="#000000")
        motivo_guardar_frame.pack(fill="x", pady=(0, 10))

        # Motivo siempre visible, pero desactivado si Cumple es 'CUMPLE'
        motivo_options = [
            "Instrucciones de cuidado",
            "Insumos",
            "Pais de origen",
            "Talla",
            "Importador",
            "Marca"
        ]
        self.motivo_label = ct.CTkLabel(
            motivo_guardar_frame, 
            text="Motivo:", 
            text_color="#00FFAA", 
            font=("Segoe UI", 13, "bold")
        )
        self.motivo_label.pack(anchor="w", padx=10, pady=(10, 0))
        self.motivo_captura_var = StringVar(value=motivo_options[0])
        self.motivo_captura_menu = ct.CTkOptionMenu(
            motivo_guardar_frame,
            variable=self.motivo_captura_var,
            values=motivo_options,
            fg_color="#000000",
            text_color="#00FFAA",
            font=("Segoe UI", 13),
            width=400,
            height=36
        )
        self.motivo_captura_menu.pack(fill="x", padx=10, pady=(0, 8))
        def on_cumple_change(*args):
            if self.cumple_captura_var.get() == "NO CUMPLE":
                self.motivo_captura_menu.configure(state="normal", text_color="#00FFAA")
                self.motivo_label.configure(text_color="#00FFAA")
            else:
                self.motivo_captura_menu.configure(state="disabled", text_color="#888888")
                self.motivo_label.configure(text_color="#888888")
        self.cumple_captura_var.trace_add('write', on_cumple_change)
        on_cumple_change()

        # Botón guardar SIEMPRE al final del frame
        self.guardar_btn = ct.CTkButton(
            motivo_guardar_frame,
            text="Guardar",
            command=self.guardar_captura_offline,
            font=("Segoe UI", 12, "bold"),
            fg_color="#00FFAA",
            text_color="#000000",
            border_width=2,
            border_color="#00FFAA",
            corner_radius=10
        )
        self.guardar_btn.pack(pady=(10, 0))
    
    def guardar_captura_offline(self):
        """Guarda la captura y la inserta/actualiza directamente en la tabla de ítems y en el historial de capturas"""
        codigo = self.codigo_captura_var.get().strip()
        motivo = self.motivo_captura_var.get().strip() if self.cumple_captura_var.get() == "NO CUMPLE" else ""
        cumple = self.cumple_captura_var.get().strip()
        if not codigo or not cumple:
            messagebox.showwarning("Campos vacíos", "Código y cumple son obligatorios")
            return
        # Buscar item_id en codigos_barras
        res = self.codigo_model.db.execute_query(
            "SELECT item_id FROM codigos_barras WHERE codigo_barras = %s", (codigo,))
        if not res:
            messagebox.showerror("Error", "El código no existe en la base de datos. Solo se pueden capturar códigos existentes.")
            return
        item_id = res[0]['item_id']
        # Obtener el nombre del item
        item_res = self.codigo_model.db.execute_query("SELECT item FROM items WHERE id = %s", (item_id,))
        item = item_res[0]['item'] if item_res else ''
        # Actualizar resultado en items
        self.codigo_model.db.execute_query(
            "UPDATE items SET resultado = %s, fecha_actualizacion = NOW() WHERE id = %s",
            (cumple, item_id), fetch=False)
        # Manejo de motivo
        if cumple == "NO CUMPLE":
            self.codigo_model.db.execute_query(
                "INSERT INTO motivos_no_cumplimiento (item_id, motivo) VALUES (%s, %s) ON CONFLICT (item_id) DO UPDATE SET motivo = EXCLUDED.motivo",
                (item_id, motivo), fetch=False)
        else:
            self.codigo_model.db.execute_query(
                "DELETE FROM motivos_no_cumplimiento WHERE item_id = %s", (item_id,), fetch=False)
        # Guardar en historial de capturas
        self.codigo_model.db.execute_query(
            "INSERT INTO capturas (codigo, item, motivo, cumple, usuario, fecha) VALUES (%s, %s, %s, %s, %s, NOW())",
            (codigo, item, motivo, cumple, self.usuario), fetch=False)
        messagebox.showinfo("Éxito", "Captura guardada y actualizada en ítems")
        self.codigo_captura_var.set("")
        self.item_captura_var.set("")
        self.codigo_captura_entry.focus_set()
    
    def subir_capturas_offline(self):
        """Sube las capturas pendientes del archivo local a la base de datos"""
        import os
        ruta = f"capturas_pendientes_{self.usuario}.json"
        if not os.path.exists(ruta):
            messagebox.showinfo("Sin capturas pendientes", "No hay capturas pendientes para subir.")
            return
        try:
            with open(ruta, "r", encoding="utf-8") as f:
                capturas = json.load(f)
            subidas = 0
            for cap in capturas:
                try:
                    if self.captura_model.guardar_captura(cap["codigo"], cap["item"], cap["motivo"], cap["cumple"], cap["usuario"]):
                        subidas += 1
                except Exception as e:
                    self.logger.error(f"Error subiendo captura offline: {str(e)}")
            if subidas > 0:
                os.remove(ruta)
                messagebox.showinfo("Éxito", f"{subidas} capturas subidas correctamente.")
            else:
                messagebox.showwarning("Sin conexión", "No se pudo subir ninguna captura. Intenta de nuevo más tarde.")
        except Exception as e:
            self.logger.error(f"Error leyendo capturas offline: {str(e)}")
            messagebox.showerror("Error", f"Error leyendo capturas pendientes: {str(e)}")
        self._actualizar_estado_pendientes()
    
    def _buscar_item_automatico(self):
        """Busca automáticamente el item cuando se ingresa un código de barras"""
        codigo = self.codigo_captura_var.get().strip()
        
        # Solo buscar si el código tiene al menos 8 caracteres (código de barras mínimo)
        if len(codigo) >= 8:
            # Validar formato del código
            es_valido, _ = Validators.validar_codigo_barras(codigo)
            if es_valido:
                # Limpiar código
                codigo_limpio = Validators.limpiar_codigo_barras(codigo)
                
                # Buscar en hilo separado para no bloquear la interfaz
                threading.Thread(
                    target=self._ejecutar_busqueda_automatica, 
                    args=(codigo_limpio,), 
                    daemon=True
                ).start()
    
    def _ejecutar_busqueda_automatica(self, codigo):
        """Ejecuta la búsqueda automática del item y resultado"""
        try:
            # Buscar item_id y datos del item
            res = self.codigo_model.db.execute_query(
                "SELECT cb.item_id, i.item, i.resultado FROM codigos_barras cb JOIN items i ON cb.item_id = i.id WHERE cb.codigo_barras = %s",
                (codigo,))
            if res:
                item_id = res[0]['item_id']
                item = res[0]['item']
                resultado = res[0]['resultado']
                self.master.after(0, lambda: self.item_captura_var.set(item))
                self.master.after(0, lambda: self.cumple_captura_var.set(resultado))
                # Si el resultado es NO CUMPLE, buscar motivo y mostrarlo
                if resultado == 'NO CUMPLE':
                    motivo = self.codigo_model.db.execute_query(
                        "SELECT motivo FROM motivos_no_cumplimiento WHERE item_id = %s", (item_id,))
                    if motivo and motivo[0].get('motivo'):
                        self.master.after(0, lambda: self.motivo_captura_var.set(motivo[0]['motivo']))
                self.logger.log_user_action(self.usuario, f"Búsqueda automática exitosa: {codigo}")
        except Exception as e:
            self.logger.error(f"Error en búsqueda automática: {str(e)}")
    
    def _actualizar_estado_pendientes(self):
        """Actualiza la visibilidad del botón de subir capturas pendientes"""
        import os
        ruta = f"capturas_pendientes_{self.usuario}.json"
        if hasattr(self, "subir_pendientes_btn"):
            if os.path.exists(ruta):
                try:
                    with open(ruta, "r", encoding="utf-8") as f:
                        capturas = json.load(f)
                    num_capturas = len(capturas)
                    self.subir_pendientes_btn.configure(
                        state="normal", 
                        text=f"Subir capturas pendientes ({num_capturas})"
                    )
                except Exception:
                    self.subir_pendientes_btn.configure(
                        state="normal", 
                        text="Subir capturas pendientes"
                    )
            else:
                self.subir_pendientes_btn.configure(
                    state="disabled", 
                    text="No hay capturas pendientes"
                )

    def _configurar_tab_configuracion(self, parent):
        main_frame = ct.CTkFrame(parent, fg_color="#000000")
        main_frame.pack(fill="both", expand=True, padx=40, pady=40)

        ct.CTkLabel(
            main_frame,
            text="Configuración de Archivos CLP",
            font=("Segoe UI", 18, "bold"),
            text_color="#00FFAA"
        ).pack(pady=(0, 20))

        # Variable para mostrar archivos seleccionados
        self.rutas_clp_var = StringVar(value="No hay archivos seleccionados")

        archivos_frame = ct.CTkFrame(main_frame, fg_color="#000000")
        archivos_frame.pack(fill="x", pady=(0, 20))

        ct.CTkLabel(
            archivos_frame,
            text="Archivos CLP seleccionados:",
            text_color="#00FFAA",
            font=("Segoe UI", 14, "bold")
        ).pack(anchor="w", padx=20, pady=(10, 0))

        self.rutas_clp_label = ct.CTkLabel(
            archivos_frame,
            textvariable=self.rutas_clp_var,
            text_color="#55DDFF",
            wraplength=600,
            fg_color="#000000"
        )
        self.rutas_clp_label.pack(anchor="w", padx=20, pady=(0, 5))

        def seleccionar_archivos():
            rutas = filedialog.askopenfilenames(
                filetypes=[("Archivos Excel", "*.xls;*.xlsx"), ("Todos", "*.*")],
                title="Seleccionar uno o varios archivos CLP"
            )
            if rutas:
                self.rutas_clp_var.set("\n".join(rutas))
                self.rutas_clp = rutas
            else:
                self.rutas_clp_var.set("No hay archivos seleccionados")
                self.rutas_clp = []

        ct.CTkButton(
            archivos_frame,
            text="Seleccionar Archivos CLP",
            command=seleccionar_archivos,
            font=("Segoe UI", 13, "bold"),
            fg_color="#000000",
            hover_color="#111111",
            border_width=2,
            border_color="#00FFAA",
            text_color="#00FFAA",
            corner_radius=12,
            width=260,
            height=36
        ).pack(pady=5, padx=20, anchor="w")

        def cargar_archivos_clp():
            if not hasattr(self, "rutas_clp") or not self.rutas_clp:
                messagebox.showerror("Error", "No hay archivos CLP seleccionados.")
                return
            resultado = self.codigo_model.cargar_varios_clp(self.rutas_clp, self.usuario)
            if not isinstance(resultado, dict):
                resultado = {'procesados': 0, 'nuevos_items': 0, 'nuevos_codigos': 0, 'clp_registros': []}
            mensaje = f"Carga completada.\nNuevos items: {resultado.get('nuevos_items', 0)}\nNuevos códigos: {resultado.get('nuevos_codigos', 0)}\nTotal procesados: {resultado.get('procesados', 0)}"
            messagebox.showinfo("Éxito", mensaje)
            self.rutas_clp_var.set("No hay archivos seleccionados")
            self.rutas_clp = []
            self.cargar_estadisticas()

        ct.CTkButton(
            archivos_frame,
            text="Cargar Archivos CLP",
            command=cargar_archivos_clp,
            font=("Segoe UI", 13, "bold"),
            fg_color="#00FFAA",
            text_color="#000000",
            border_width=2,
            border_color="#00FFAA",
            corner_radius=12,
            width=260,
            height=36
        ).pack(pady=5, padx=20, anchor="w")

class LoginWindow:
    def __init__(self, master, usuario_model, logger, on_success):
        self.master = master
        self.usuario_model = usuario_model
        self.logger = logger
        self.on_success = on_success
        self.attempts_left = 3
        
        self.crear_interfaz()
    
    def crear_interfaz(self):
        """Crea la interfaz de login"""
        self.frame = ct.CTkFrame(self.master)
        self.frame.pack(fill="both", expand=True, padx=20, pady=20)
        
        # Título
        self.label_title = ct.CTkLabel(
            self.frame, 
            text="Iniciar sesión", 
            font=("Segoe UI", 18, "bold")
        )
        self.label_title.pack(pady=(0, 16))
        
        # Variables
        self.user_var = StringVar()
        self.pass_var = StringVar()
        
        # Usuario
        self.label_user = ct.CTkLabel(self.frame, text="Usuario:")
        self.label_user.pack(anchor="w")
        self.entry_user = ct.CTkEntry(self.frame, textvariable=self.user_var)
        self.entry_user.pack(fill="x", pady=(0, 8))
        
        # Contraseña
        self.label_pass = ct.CTkLabel(self.frame, text="Contraseña:")
        self.label_pass.pack(anchor="w")
        
        # Frame horizontal para contraseña y botón
        self.pass_row = ct.CTkFrame(self.frame)
        self.pass_row.pack(fill="x", pady=(0, 8))
        
        self.entry_pass = ct.CTkEntry(
            self.pass_row, 
            textvariable=self.pass_var, 
            show="*"
        )
        self.entry_pass.pack(side="left", fill="x", expand=True)
        
        self.login_button = ct.CTkButton(
            self.pass_row, 
            text="Entrar", 
            command=self.try_login, 
            width=100
        )
        self.login_button.pack(side="right", padx=(8, 0))
        
        # Label de error
        self.error_label = ct.CTkLabel(
            self.frame, 
            text="", 
            text_color="#FF3333", 
            font=("Segoe UI", 11, "bold")
        )
        self.error_label.pack(pady=(0, 8))
        
        # Eventos
        self.entry_user.bind("<Return>", lambda e: self.entry_pass.focus_set())
        self.entry_pass.bind("<Return>", lambda e: self.try_login())
        self.entry_user.focus_set()
    
    def try_login(self):
        """Intenta hacer login"""
        usuario = self.user_var.get().strip()
        contrasena = self.pass_var.get().strip()
        
        # Validar entrada
        if not usuario or not contrasena:
            self.error_label.configure(text="Ingrese usuario y contraseña.")
            return
        
        # Validar formato
        es_valido_usuario, _ = Validators.validar_usuario(usuario)
        es_valido_pass, _ = Validators.validar_contraseña(contrasena)
        
        if not es_valido_usuario or not es_valido_pass:
            self.error_label.configure(text="Formato de usuario o contraseña inválido.")
            return
        
        # Deshabilitar botón durante verificación
        self.login_button.configure(state="disabled", text="Verificando...")
        
        # Ejecutar verificación en hilo separado
        threading.Thread(target=self._verificar_credenciales, args=(usuario, contrasena), daemon=True).start()
    
    def _verificar_credenciales(self, usuario, contrasena):
        """Verifica las credenciales en la base de datos"""
        try:
            resultado = self.usuario_model.autenticar_usuario(usuario, contrasena)
            
            if resultado:
                self.master.after(0, lambda: self._login_exitoso(usuario, resultado['rol']))
            else:
                self.attempts_left -= 1
                if self.attempts_left > 0:
                    self.master.after(0, lambda: self._mostrar_error_intentos())
                else:
                    self.master.after(0, lambda: self._bloquear_login())
                    
        except Exception as e:
            self.logger.error(f"Error en autenticación: {str(e)}")
            self.master.after(0, lambda error=str(e): self._mostrar_error_conexion(error))
        finally:
            self.master.after(0, lambda: self._restaurar_boton())
    
    def _login_exitoso(self, usuario, rol):
        """Maneja el login exitoso"""
        self.on_success(usuario, rol)
    
    def _mostrar_error_intentos(self):
        """Muestra error con intentos restantes"""
        self.error_label.configure(
            text=f"Usuario o contraseña incorrectos. Intentos restantes: {self.attempts_left}"
        )
    
    def _bloquear_login(self):
        """Bloquea el login por demasiados intentos"""
        self.error_label.configure(
            text="Demasiados intentos fallidos. Reinicie la aplicación."
        )
        self.login_button.configure(state="disabled", text="Bloqueado")
    
    def _mostrar_error_conexion(self, error):
        """Muestra error de conexión"""
        self.error_label.configure(text=f"Error de conexión: {error}")
    
    def _restaurar_boton(self):
        """Restaura el botón de login"""
        try:
            safe_configure(self.login_button, state="normal", text="Entrar")
        except:
            pass  # Widget ya destruido

class MainWindow:
    def __init__(self, master, usuario, rol, codigo_model, captura_model, logger, config_data, usuario_model, db_manager):
        self.master = master
        self.usuario = usuario
        self.rol = rol
        self.codigo_model = codigo_model
        self.captura_model = captura_model
        self.logger = logger
        self.config_data = config_data
        self.usuario_model = usuario_model
        self.db_manager = db_manager
        
        try:
            self.crear_interfaz()
            if self.rol != "superadmin":
                self.cargar_estadisticas()
        except Exception as e:
            try:
                if hasattr(self, 'logger') and self.logger:
                    self.logger.error(f"Error creando interfaz principal: {str(e)}")
                else:
                    print(f"Error creando interfaz principal: {str(e)}")
            except:
                print(f"Error creando interfaz principal: {str(e)}")
            
            try:
                messagebox.showerror("Error", f"Error al crear la interfaz principal: {str(e)}")
            except:
                print(f"Error al crear la interfaz principal: {str(e)}")
    
    def crear_interfaz(self):
        """Crea la interfaz principal"""
        try:
            # Crear tabview
            self.tabview = ct.CTkTabview(self.master, fg_color="#000000")
            self.tabview.pack(fill="both", expand=True, padx=40, pady=20)
            
            # Interfaz específica para superadmin
            if self.rol == "superadmin":
                self._crear_interfaz_superadmin()
            else:
                self._crear_interfaz_normal()
            
            # Establecer pestaña inicial
            if self.rol == "superadmin":
                self.tabview.set("Gestión de Usuarios")
            else:
                self.tabview.set("Escáner")
        except Exception as e:
            try:
                if hasattr(self, 'logger') and self.logger:
                    self.logger.error(f"Error creando interfaz: {str(e)}")
                else:
                    print(f"Error creando interfaz: {str(e)}")
            except:
                print(f"Error creando interfaz: {str(e)}")
            raise e
    
    def _crear_interfaz_superadmin(self):
        """Crea la interfaz específica para superadmin"""
        try:
            # Pestaña Gestión de Usuarios
            self.tabview.add("Gestión de Usuarios")
            self._configurar_tab_gestion_usuarios(self.tabview.tab("Gestión de Usuarios"))
            
            # Pestaña Base de Datos
            self.tabview.add("Base de Datos")
            self._configurar_tab_base_datos(self.tabview.tab("Base de Datos"))
        except Exception as e:
            try:
                if hasattr(self, 'logger') and self.logger:
                    self.logger.error(f"Error creando interfaz superadmin: {str(e)}")
                else:
                    print(f"Error creando interfaz superadmin: {str(e)}")
            except:
                print(f"Error creando interfaz superadmin: {str(e)}")
            raise e
    
    def _crear_interfaz_normal(self):
        """Crea la interfaz normal para otros usuarios"""
        # Pestaña Escáner (todos los usuarios)
        self.tabview.add("Escáner")
        self._configurar_tab_escaner(self.tabview.tab("Escáner"))
        
        # Pestaña Captura (solo rol captura y admin)
        if self.rol in ["captura", "admin"]:
            self.tabview.add("Captura de Datos")
            self._configurar_tab_captura(self.tabview.tab("Captura de Datos"))
        
        # Pestaña Configuración (solo admin)
        if self.rol == "admin":
            self.tabview.add("Configuración")
            self._configurar_tab_configuracion(self.tabview.tab("Configuración"))
        
    def _configurar_tab_gestion_usuarios(self, parent):
        """Configura la pestaña de gestión de usuarios para superadmin"""
        main_frame = ct.CTkFrame(parent, fg_color="#000000")
        main_frame.pack(fill="both", expand=True, padx=40, pady=40)
        ct.CTkLabel(
            main_frame, 
            text="Panel de Administración - Gestión de Usuarios", 
            font=("Segoe UI", 18, "bold"), 
            text_color="#00FFAA"
        ).pack(pady=(0, 20))
        # Layout horizontal: formulario a la izquierda, lista a la derecha
        content_frame = ct.CTkFrame(main_frame, fg_color="#000000")
        content_frame.pack(fill="both", expand=True)
        # Formulario de usuario (izquierda)
        self._crear_formulario_usuario(content_frame, side="left")
        # Lista de usuarios (derecha, mejor estilo)
        self._crear_lista_usuarios(content_frame, side="right")
    
    def _configurar_tab_base_datos(self, parent):
        """Configura la pestaña de base de datos para superadmin"""
        try:
            main_frame = ct.CTkFrame(parent, fg_color="#000000")
            main_frame.pack(fill="both", expand=True, padx=40, pady=40)
            ct.CTkLabel(
                main_frame, 
                text="Panel de Administración - Base de Datos", 
                font=("Segoe UI", 18, "bold"), 
                text_color="#00FFAA"
            ).pack(pady=(0, 20))
            # Tabs para cada tabla
            tablas_tabview = ct.CTkTabview(main_frame, fg_color="#111111")
            tablas_tabview.pack(fill="both", expand=True)
            # Usuarios (tabla de solo lectura para visualización)
            tablas_tabview.add("Usuarios")
            self._crear_tabla_usuarios_solo_lectura(tablas_tabview.tab("Usuarios"))
            # Ítems (nueva pestaña)
            tablas_tabview.add("Ítems")
            self._crear_tabla_items(tablas_tabview.tab("Ítems"))
            # Capturas (solo si NO es superadmin)
            if self.rol != "superadmin":
                tablas_tabview.add("Capturas")
                self._configurar_tab_captura(tablas_tabview.tab("Capturas"))
        except Exception as e:
            try:
                if hasattr(self, 'logger') and self.logger:
                    self.logger.error(f"Error configurando tab base de datos: {str(e)}")
                else:
                    print(f"Error configurando tab base de datos: {str(e)}")
            except:
                print(f"Error configurando tab base de datos: {str(e)}")
            raise e
    
    def _crear_tabla_usuarios_solo_lectura(self, parent):
        """Crea una tabla de usuarios de solo lectura para la pestaña Base de Datos"""
        from tkinter import ttk
        
        ct.CTkLabel(
            parent,
            text="Vista de Usuarios (Solo Lectura)",
            font=("Segoe UI", 16, "bold"),
            text_color="#00FFAA"
        ).pack(pady=(20, 20))
        
        table_frame = ct.CTkFrame(parent, fg_color="#000000")
        table_frame.pack(fill="both", expand=True, padx=20, pady=(0, 20))
        
        columns = ("Usuario", "Rol", "Estado", "Último Acceso")
        self.usuarios_tree_db = ttk.Treeview(table_frame, columns=columns, show="headings", height=15, selectmode="none")
        
        for col in columns:
            self.usuarios_tree_db.heading(col, text=col)
            self.usuarios_tree_db.column(col, width=120, anchor="center")
        
        style = ttk.Style()
        style.theme_use('default')
        style.configure("Treeview",
                        background="#000000",
                        foreground="#00FFAA",
                        rowheight=25,
                        fieldbackground="#000000")
        style.configure("Treeview.Heading",
                        background="#111111",
                        foreground="#00FFAA",
                        font=("Segoe UI", 10, "bold"))
        
        scrollbar = ttk.Scrollbar(table_frame, orient="vertical", command=self.usuarios_tree_db.yview)
        self.usuarios_tree_db.configure(yscrollcommand=scrollbar.set)
        self.usuarios_tree_db.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        
        # Cargar datos
        self._cargar_usuarios_en_tabla(self.usuarios_tree_db)
        
        # Botón refrescar
        ct.CTkButton(
            parent,
            text="Refrescar",
            command=lambda: self._cargar_usuarios_en_tabla(self.usuarios_tree_db),
            fg_color="#00AAFF",
            text_color="#FFFFFF",
            width=120,
            height=32
        ).pack(pady=10)

    def _crear_tabla_items(self, parent):
        from tkinter import ttk
        # Limpiar widgets previos
        for widget in parent.winfo_children():
            widget.destroy()
        ct.CTkLabel(
            parent,
            text="Gestión de Ítems",
            font=("Segoe UI", 16, "bold"),
            text_color="#00FFAA"
        ).pack(pady=(20, 20))
        # Buscador
        search_frame = ct.CTkFrame(parent, fg_color="#000000")
        search_frame.pack(fill="x", padx=20, pady=(0, 10))
        self.items_search_var = ct.StringVar()
        ct.CTkLabel(search_frame, text="Buscar por item o resultado:", text_color="#00FFAA").pack(side="left", padx=(0, 8))
        search_entry = ct.CTkEntry(search_frame, textvariable=self.items_search_var, width=200)
        search_entry.pack(side="left")
        search_entry.bind("<Return>", lambda e: self.cargar_items())
        # Frame para la tabla
        table_frame = ct.CTkFrame(parent, fg_color="#000000")
        table_frame.pack(fill="both", expand=True, padx=20, pady=(0, 20))
        columns = ("ID", "Item", "Resultado", "Fecha Actualización")
        self.items_tree = ttk.Treeview(table_frame, columns=columns, show="headings", height=15, selectmode="browse")
        for col in columns:
            self.items_tree.heading(col, text=col)
            self.items_tree.column(col, width=150, anchor="center")
        style = ttk.Style()
        style.theme_use('default')
        style.configure("Treeview",
                        background="#000000",
                        foreground="#00FFAA",
                        rowheight=25,
                        fieldbackground="#000000")
        style.configure("Treeview.Heading",
                        background="#111111",
                        foreground="#00FFAA",
                        font=("Segoe UI", 10, "bold"))
        style.map('Treeview', background=[('selected', '#222222')])
        scrollbar = ttk.Scrollbar(table_frame, orient="vertical", command=self.items_tree.yview)
        self.items_tree.configure(yscrollcommand=scrollbar.set)
        self.items_tree.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        self.cargar_items()
        # Mensaje si no hay ítems
        self.items_empty_label = ct.CTkLabel(parent, text="", text_color="#FF3333", font=("Segoe UI", 13, "bold"))
        self.items_empty_label.pack(pady=(0, 10))
        # Botón refrescar
        action_frame = ct.CTkFrame(parent, fg_color="#111111")
        action_frame.pack(pady=(0, 20))
        ct.CTkButton(
            action_frame,
            text="Refrescar",
            command=self.cargar_items,
            fg_color="#00AAFF",
            text_color="#FFFFFF",
            width=120,
            height=32
        ).pack(side="left", padx=5)

    def cargar_items(self):
        try:
            for item in self.items_tree.get_children():
                self.items_tree.delete(item)
            filtro = self.items_search_var.get().strip()
            if filtro:
                query = "SELECT * FROM items WHERE item ILIKE %s OR resultado ILIKE %s ORDER BY id ASC"
                like = f"%{filtro}%"
                items = self.db_manager.execute_query(query, (like, like))
            else:
                items = self.db_manager.execute_query("SELECT * FROM items ORDER BY id ASC")
            if items:
                for it in items:
                    self.items_tree.insert("", "end", values=(
                        it.get('id', ''),
                        it.get('item', ''),
                        it.get('resultado', ''),
                        it.get('fecha_actualizacion', '')
                    ))
            # No mostrar mensajes de error en la interfaz
        except Exception as e:
            self.logger.error(f"Error cargando ítems: {str(e)}")
            # No mostrar mensajes de error en la interfaz

    def _crear_lista_usuarios(self, parent, side="right"):
        """Crea la tabla principal de usuarios con botones de acción"""
        list_frame = ct.CTkFrame(parent, fg_color="#111111")
        list_frame.pack(side=side, fill="both", expand=True, padx=(10, 0))
        ct.CTkLabel(
            list_frame,
            text="Usuarios Registrados",
            font=("Segoe UI", 16, "bold"),
            text_color="#00FFAA"
        ).pack(pady=(20, 20))
        table_frame = ct.CTkFrame(list_frame, fg_color="#000000")
        table_frame.pack(fill="both", expand=True, padx=20, pady=(0, 20))
        from tkinter import ttk
        columns = ("Usuario", "Rol", "Estado", "Último Acceso")
        self.usuarios_tree = ttk.Treeview(table_frame, columns=columns, show="headings", height=15, selectmode="browse")
        for col in columns:
            self.usuarios_tree.heading(col, text=col)
            self.usuarios_tree.column(col, width=120, anchor="center")
        style = ttk.Style()
        style.theme_use('default')
        style.configure("Treeview",
                        background="#000000",
                        foreground="#00FFAA",
                        rowheight=25,
                        fieldbackground="#000000")
        style.configure("Treeview.Heading",
                        background="#111111",
                        foreground="#00FFAA",
                        font=("Segoe UI", 10, "bold"))
        style.map('Treeview', background=[('selected', '#222222')])
        scrollbar = ttk.Scrollbar(table_frame, orient="vertical", command=self.usuarios_tree.yview)
        self.usuarios_tree.configure(yscrollcommand=scrollbar.set)
        self.usuarios_tree.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        
        # Cargar usuarios en la tabla principal
        self._cargar_usuarios_en_tabla(self.usuarios_tree)
        
        # Configurar eventos para la tabla principal
        self.usuario_seleccionado = None
        self.usuarios_tree.bind("<<TreeviewSelect>>", self.on_usuario_select)
        self.usuarios_tree.bind("<ButtonRelease-1>", self.on_usuario_select)
        
        # Botones de acción para la tabla principal
        action_frame = ct.CTkFrame(list_frame, fg_color="#111111")
        action_frame.pack(pady=(0, 20))
        ct.CTkButton(
            action_frame,
            text="Eliminar Usuario",
            command=self.eliminar_usuario,
            fg_color="#FF3333",
            text_color="#FFFFFF",
            width=120,
            height=32
        ).pack(side="left", padx=5)
        ct.CTkButton(
            action_frame,
            text="Cambiar Estado",
            command=self.cambiar_estado_usuario,
            fg_color="#FFAA00",
            text_color="#000000",
            width=120,
            height=32
        ).pack(side="left", padx=5)
        ct.CTkButton(
            action_frame,
            text="Cambiar Contraseña",
            command=self.cambiar_contraseña_usuario,
            fg_color="#00AA00",
            text_color="#FFFFFF",
            width=120,
            height=32
        ).pack(side="left", padx=5)
        ct.CTkButton(
            action_frame,
            text="Refrescar",
            command=self.cargar_usuarios,
            fg_color="#00AAFF",
            text_color="#FFFFFF",
            width=120,
            height=32
        ).pack(side="left", padx=5)
    
    def _cargar_usuarios_en_tabla(self, tree):
        """Carga los usuarios en una tabla específica"""
        try:
            # Limpiar tabla
            for item in tree.get_children():
                tree.delete(item)
            
            # Obtener usuarios de la base de datos
            usuarios = self.usuario_model.obtener_todos_usuarios()
            
            # Insertar en la tabla
            for usuario in usuarios:
                tree.insert("", "end", values=(
                    usuario.get('usuario', ''),
                    usuario.get('rol', ''),
                    usuario.get('estado', ''),
                    usuario.get('ultimo_acceso', '')
                ))
                
        except Exception as e:
            self.logger.error(f"Error cargando usuarios: {str(e)}")
    
    def _crear_formulario_usuario(self, parent, side="left"):
        form_frame = ct.CTkFrame(parent, fg_color="#111111")
        form_frame.pack(side=side, fill="both", expand=True, padx=(0, 10))
        ct.CTkLabel(
            form_frame,
            text="Crear/Editar Usuario",
            font=("Segoe UI", 16, "bold"),
            text_color="#00FFAA"
        ).pack(pady=(20, 20))
        self.usuario_form_var = StringVar()
        self.password_form_var = StringVar()
        self.rol_form_var = StringVar(value="usuario")
        self.activo_form_var = StringVar(value="activo")
        ct.CTkLabel(form_frame, text="Usuario:", text_color="#00FFAA").pack(anchor="w", padx=20, pady=(0, 5))
        self.usuario_form_entry = ct.CTkEntry(
            form_frame,
            textvariable=self.usuario_form_var,
            width=300,
            height=32
        )
        self.usuario_form_entry.pack(padx=20, pady=(0, 15))
        ct.CTkLabel(form_frame, text="Contraseña:", text_color="#00FFAA").pack(anchor="w", padx=20, pady=(0, 5))
        self.password_form_entry = ct.CTkEntry(
            form_frame,
            textvariable=self.password_form_var,
            show="*",
            width=300,
            height=32
        )
        self.password_form_entry.pack(padx=20, pady=(0, 15))
        ct.CTkLabel(form_frame, text="Rol:", text_color="#00FFAA").pack(anchor="w", padx=20, pady=(0, 5))
        self.rol_form_menu = ct.CTkOptionMenu(
            form_frame,
            variable=self.rol_form_var,
            values=["usuario", "captura", "admin"],
            width=300,
            height=32
        )
        self.rol_form_menu.pack(padx=20, pady=(0, 15))
        ct.CTkLabel(form_frame, text="Estado:", text_color="#00FFAA").pack(anchor="w", padx=20, pady=(0, 5))
        self.activo_form_menu = ct.CTkOptionMenu(
            form_frame,
            variable=self.activo_form_var,
            values=["activo", "inactivo"],
            width=300,
            height=32
        )
        self.activo_form_menu.pack(padx=20, pady=(0, 20))
        buttons_frame = ct.CTkFrame(form_frame, fg_color="#111111")
        buttons_frame.pack(pady=(0, 20))
        ct.CTkButton(
            buttons_frame,
            text="Crear Usuario",
            command=self.crear_usuario,
            fg_color="#00FFAA",
            text_color="#000000",
            width=120,
            height=32
        ).pack(side="left", padx=5)
        ct.CTkButton(
            buttons_frame,
            text="Limpiar",
            command=self.limpiar_formulario_usuario,
            fg_color="#FF3333",
            text_color="#FFFFFF",
            width=120,
            height=32
        ).pack(side="left", padx=5)

    def crear_usuario(self):
        """Crea un nuevo usuario"""
        try:
            usuario = self.usuario_form_var.get().strip()
            password = self.password_form_var.get().strip()
            rol = self.rol_form_var.get()
            activo = self.activo_form_var.get()
            # Validar campos
            if not usuario or not password:
                messagebox.showwarning("Campos vacíos", "Usuario y contraseña son obligatorios")
                return
            # Proteger superadmin
            if usuario == "superadmin" or rol == "superadmin":
                messagebox.showwarning("Prohibido", "No puedes crear ni modificar el usuario superadmin desde la interfaz.")
                return
            # Validar formato
            es_valido_usuario, _ = Validators.validar_usuario(usuario)
            es_valido_pass, _ = Validators.validar_contraseña(password)
            if not es_valido_usuario or not es_valido_pass:
                messagebox.showwarning("Formato inválido", "Formato de usuario o contraseña inválido")
                return
            # Crear usuario
            resultado = self.usuario_model.crear_usuario(usuario, password, rol, activo)
            if resultado:
                messagebox.showinfo("Éxito", "Usuario creado correctamente")
                self.limpiar_formulario_usuario()
                self.cargar_usuarios()
                # Seleccionar automáticamente el nuevo usuario después de un breve delay
                self.master.after(200, lambda: self._seleccionar_usuario_en_tabla(usuario))
                self.logger.log_user_action(self.usuario, f"Usuario creado: {usuario}")
            else:
                messagebox.showerror("Error", "No se pudo crear el usuario. Verifica que no sea superadmin o que el usuario ya exista.")
        except Exception as e:
            self.logger.error(f"Error creando usuario: {str(e)}")
            messagebox.showerror("Error", f"Error al crear usuario: {str(e)}")
    
    def cargar_usuarios(self):
        """Carga los usuarios en la tabla principal"""
        self._cargar_usuarios_en_tabla(self.usuarios_tree)
    
    def on_usuario_select(self, event=None):
        selection = self.usuarios_tree.selection()
        print("SELECCIÓN:", selection)  # Debug
        if selection:
            item = self.usuarios_tree.item(selection[0])
            values = item['values']
            if values:
                self.usuario_form_var.set(values[0])  # Usuario
                self.rol_form_var.set(values[1])      # Rol
                self.activo_form_var.set(values[2])   # Estado
                self.password_form_var.set("")        # No mostrar contraseña
                self.usuario_seleccionado = values
        else:
            self.usuario_seleccionado = None

    def eliminar_usuario(self):
        selection = self.usuarios_tree.selection()
        if not selection:
            self.usuarios_tree.focus_set()
            messagebox.showwarning("Sin selección", "Selecciona un usuario para eliminar")
            return
        item = self.usuarios_tree.item(selection[0])
        values = item['values']
        if not values:
            messagebox.showwarning("Sin selección", "Selecciona un usuario para eliminar")
            return
        usuario = values[0]
        if usuario == self.usuario:
            messagebox.showwarning("Error", "No puedes eliminar tu propio usuario")
            return
        if usuario == "superadmin":
            messagebox.showwarning("Prohibido", "No puedes eliminar el usuario superadmin.")
            return
        if messagebox.askyesno("Confirmar", f"¿Estás seguro de eliminar al usuario '{usuario}'?"):
            try:
                resultado = self.usuario_model.eliminar_usuario(usuario)
                if resultado:
                    messagebox.showinfo("Éxito", "Usuario eliminado correctamente")
                    self.cargar_usuarios()
                    self.limpiar_formulario_usuario()
                    self.usuarios_tree.selection_remove(self.usuarios_tree.selection())
                    self.logger.log_user_action(self.usuario, f"Usuario eliminado: {usuario}")
                else:
                    messagebox.showerror("Error", "No se pudo eliminar el usuario")
            except Exception as e:
                self.logger.error(f"Error eliminando usuario: {str(e)}")
                messagebox.showerror("Error", f"Error al eliminar usuario: {str(e)}")

    def cambiar_estado_usuario(self):
        selection = self.usuarios_tree.selection()
        if not selection:
            self.usuarios_tree.focus_set()
            messagebox.showwarning("Sin selección", "Selecciona un usuario para cambiar su estado")
            return
        item = self.usuarios_tree.item(selection[0])
        values = item['values']
        if not values:
            messagebox.showwarning("Sin selección", "Selecciona un usuario para cambiar su estado")
            return
        usuario = values[0]
        estado_actual = values[2]
        if usuario == "superadmin":
            messagebox.showwarning("Prohibido", "No puedes cambiar el estado del usuario superadmin.")
            return
        nuevo_estado = "inactivo" if estado_actual == "activo" else "activo"
        try:
            resultado = self.usuario_model.cambiar_estado_usuario(usuario, nuevo_estado)
            if resultado:
                messagebox.showinfo("Éxito", f"Estado cambiado a {nuevo_estado}")
                self.cargar_usuarios()
                self.usuarios_tree.selection_remove(self.usuarios_tree.selection())
                self.logger.log_user_action(self.usuario, f"Estado cambiado para {usuario}: {nuevo_estado}")
            else:
                messagebox.showerror("Error", "No se pudo cambiar el estado")
        except Exception as e:
            self.logger.error(f"Error cambiando estado: {str(e)}")
            messagebox.showerror("Error", f"Error al cambiar estado: {str(e)}")

    def cambiar_contraseña_usuario(self):
        selection = self.usuarios_tree.selection()
        if not selection:
            self.usuarios_tree.focus_set()
            messagebox.showwarning("Sin selección", "Selecciona un usuario para cambiar su contraseña")
            return
        item = self.usuarios_tree.item(selection[0])
        values = item['values']
        if not values:
            messagebox.showwarning("Sin selección", "Selecciona un usuario para cambiar su contraseña")
            return
        usuario = values[0]
        if usuario == "superadmin":
            messagebox.showwarning("Prohibido", "No puedes cambiar la contraseña del usuario superadmin.")
            return
        if messagebox.askyesno("Confirmar", f"¿Estás seguro de cambiar la contraseña del usuario '{usuario}'?"):
            try:
                nueva_contraseña = simpledialog.askstring("Cambiar Contraseña", "Ingrese la nueva contraseña:")
                if nueva_contraseña:
                    # Validar formato de contraseña
                    es_valido_pass, mensaje = Validators.validar_contraseña(nueva_contraseña)
                    if not es_valido_pass:
                        messagebox.showwarning("Formato inválido", mensaje)
                        return
                    
                    resultado = self.usuario_model.cambiar_contraseña(usuario, nueva_contraseña)
                    if resultado:
                        messagebox.showinfo("Éxito", f"Contraseña cambiada correctamente para el usuario '{usuario}'")
                        self.cargar_usuarios()
                        self.usuarios_tree.selection_remove(self.usuarios_tree.selection())
                        self.logger.log_user_action(self.usuario, f"Contraseña cambiada para usuario: {usuario}")
                    else:
                        messagebox.showerror("Error", "No se pudo cambiar la contraseña")
                else:
                    messagebox.showwarning("Cancelado", "Cambio de contraseña cancelado")
            except Exception as e:
                self.logger.error(f"Error cambiando contraseña: {str(e)}")
                messagebox.showerror("Error", f"Error al cambiar contraseña: {str(e)}")

    def limpiar_formulario_usuario(self):
        self.usuario_form_var.set("")
        self.password_form_var.set("")
        self.rol_form_var.set("usuario")
        self.activo_form_var.set("activo")
        self.usuario_seleccionado = None
        self.usuarios_tree.selection_remove(self.usuarios_tree.selection())

    def _seleccionar_usuario_en_tabla(self, usuario_nombre):
        """Selecciona automáticamente un usuario en la tabla después de crearlo"""
        try:
            for item_id in self.usuarios_tree.get_children():
                values = self.usuarios_tree.item(item_id)["values"]
                if values and values[0] == usuario_nombre:
                    self.usuarios_tree.selection_set(item_id)
                    self.usuarios_tree.focus(item_id)
                    self.usuarios_tree.see(item_id)
                    self.on_usuario_select()  # Llama el evento para activar botones
                    print(f"Usuario seleccionado automáticamente: {usuario_nombre}")
                    break
        except Exception as e:
            self.logger.error(f"Error seleccionando usuario en tabla: {str(e)}")
    
    def _configurar_tab_escaner(self, parent):
        """Configura la pestaña del escáner"""
        # Frame principal
        main_frame = ct.CTkFrame(parent, fg_color="#000000")
        main_frame.pack(fill="both", expand=True, padx=40, pady=40)
        
        # Columna izquierda
        left_col = ct.CTkFrame(main_frame, fg_color="#000000")
        left_col.pack(side="left", fill="y", expand=True, padx=(0, 40))
        
        # Logo y título
        self._crear_header(left_col)
        
        # Entrada de código
        self.codigo_var = StringVar()
        self.codigo_entry = ct.CTkEntry(
            left_col, 
            textvariable=self.codigo_var,
            font=("Segoe UI", 15),
            width=400,
            height=36,
            corner_radius=12,
            border_width=2,
            border_color="#00FFAA",
            fg_color="#000000",
            text_color="#00FFAA",
            placeholder_text="Código de barras"
        )
        self.codigo_entry.pack(pady=(0, 18))
        self.codigo_entry.bind("<Return>", lambda e: self.buscar_codigo())
        
        # Botones
        self._crear_botones_escaner(left_col)
        
        # Resultados
        self._crear_resultados_escaner(left_col)
        
        # Columna derecha
        right_col = ct.CTkFrame(main_frame, fg_color="#000000")
        right_col.pack(side="right", fill="y", expand=True, padx=(40, 0))
        
        # Estadísticas
        self._crear_estadisticas_escaner(right_col)
    
    def _crear_header(self, parent):
        """Crea el header con logo y título"""
        # Logo
        logo_path = os.path.join(os.path.dirname(__file__), 'resources', 'Logo (2).png')
        if os.path.exists(logo_path):
            try:
                logo_img = ct.CTkImage(
                    light_image=Image.open(logo_path), 
                    dark_image=Image.open(logo_path), 
                    size=(90, 90)
                )
                logo_label = ct.CTkLabel(parent, image=logo_img, text="", fg_color="#000000")
                logo_label.pack(pady=(10, 10))
            except Exception as e:
                self.logger.error(f"Error cargando logo: {str(e)}")
                ct.CTkLabel(
                    parent, 
                    text="V&C", 
                    font=("Segoe UI", 28, "bold"), 
                    text_color="#00FFAA", 
                    fg_color="#000000"
                ).pack(pady=(10, 10))
        else:
            ct.CTkLabel(
                parent, 
                text="V&C", 
                font=("Segoe UI", 28, "bold"), 
                text_color="#00FFAA", 
                fg_color="#000000"
            ).pack(pady=(10, 10))
        
        # Título
        ct.CTkLabel(
            parent, 
            text="Escáner V&C", 
            font=("Segoe UI", 22, "bold"), 
            text_color="#00FFAA", 
            fg_color="#000000"
        ).pack(pady=(0, 8))
    
    def _crear_botones_escaner(self, parent):
        """Crea los botones del escáner"""
        botones_frame = ct.CTkFrame(parent, fg_color="#000000")
        botones_frame.pack(pady=(0, 10))
        # Botón buscar
        self.search_button = ct.CTkButton(
            botones_frame,
            text="Buscar",
            font=("Segoe UI", 14, "bold"),
            fg_color="#000000",
            border_width=2,
            border_color="#00FFAA",
            text_color="#00FFAA",
            hover_color="#111111",
            corner_radius=12,
            width=160,
            height=36,
            command=self.buscar_codigo
        )
        self.search_button.pack(side="left", padx=(0, 8))
        # Eliminar el botón limpiar BD para todos los usuarios
    
    def _crear_resultados_escaner(self, parent):
        """Crea los labels de resultados"""
        self.clave_valor = ct.CTkLabel(
            parent, 
            text="ITEM: ", 
            font=("Segoe UI", 13, "bold"), 
            text_color="#00FFAA", 
            fg_color="#000000"
        )
        self.clave_valor.pack(pady=(10, 0))
        
        self.resultado_valor = ct.CTkLabel(
            parent, 
            text="RESULTADO: ", 
            font=("Segoe UI", 12), 
            text_color="#00FFAA", 
            fg_color="#000000", 
            wraplength=500
        )
        self.resultado_valor.pack(pady=(0, 0))
        # NOM oculta por el momento porque me da flojera revisar la logica y no tengo como hacer relacion
        self.nom_valor = ct.CTkLabel(
            parent, 
            text="",  # texto vacío por defecto
            font=("Segoe UI", 12, "italic"), 
            text_color="#00FFAA", 
            fg_color="transparent", 
            wraplength=500
        )
        self.nom_valor.pack(pady=(0, 10))
    
    def _crear_estadisticas_escaner(self, parent):
        """Crea las estadísticas del escáner"""
        # Estadísticas
        self.total_codigos_label = ct.CTkLabel(
            parent, 
            text="Total de códigos: 0", 
            font=("Segoe UI", 11), 
            text_color="#00FFAA", 
            fg_color="#000000"
        )
        self.total_codigos_label.pack(pady=(0, 2))
        
        self.con_resultado_label = ct.CTkLabel(
            parent, 
            text="Items en total: 0", 
            font=("Segoe UI", 11), 
            text_color="#00FFAA", 
            fg_color="#000000"
        )
        self.con_resultado_label.pack(pady=(0, 2))
        
        self.sin_resultado_label = ct.CTkLabel(
            parent, 
            text="Sin resultado: 0", 
            font=("Segoe UI", 11), 
            text_color="#00FFAA", 
            fg_color="#000000"
        )
        self.sin_resultado_label.pack(pady=(0, 2))
        
        self.ultima_actualizacion_label = ct.CTkLabel(
            parent, 
            text="Última actualización: Nunca", 
            font=("Segoe UI", 11), 
            text_color="#00FFAA", 
            fg_color="#000000"
        )
        self.ultima_actualizacion_label.pack(pady=(0, 8))
        
        # Botón cerrar sesión (logout)
        self.logout_button = ct.CTkButton(
            parent,
            text="Cerrar Sesión",
            font=("Segoe UI", 12, "bold"),
            fg_color="#000000",
            border_width=2,
            border_color="#00FFAA",
            text_color="#00FFAA",
            hover_color="#111111",
            corner_radius=12,
            width=200,
            height=32,
            command=self.cerrar_sesion
        )
        self.logout_button.pack(pady=(0, 8))
    
        # Botón historial del día
        self.historial_button = ct.CTkButton(
            text="Ver Historial del Día",
            font=("Segoe UI", 12, "bold"),
            fg_color="#000000",
            border_width=2,
            border_color="#00FFAA",
            text_color="#00FFAA",
            hover_color="#111111",
            corner_radius=12,
            width=200,
            height=32,
            command=self.mostrar_historial_cargas_y_consultas
        )
        self.historial_button.pack(pady=(0, 18))

        # Botón solo para admins: Exportar Reporte del Día
        if self.rol == "admin":
            self.exportar_reporte_button = ct.CTkButton(
                parent,
                text="Exportar Reporte del Día",
                font=("Segoe UI", 12, "bold"),
                fg_color="#000000",
                border_width=2,
                border_color="#00FFAA",
                text_color="#00FFAA",
                hover_color="#111111",
                corner_radius=12,
                width=200,
                height=32,
                command=self.exportar_reporte_dia
            )
            self.exportar_reporte_button.pack(pady=(0, 10))
        else:
            self.exportar_reporte_button = None

        # Botón Exportar Capturas del Día (para todos los roles)
        def exportar_capturas():
            import tkinter as tk
            from tkinter import filedialog, messagebox
            from datetime import datetime
            top = tk.Toplevel(self.master)
            top.title("Seleccionar día para exportar capturas")
            top.geometry("400x220")
            top.configure(bg="#000000")  # Fondo negro

            label = tk.Label(
                top, text="Selecciona la fecha:",
                font=("Segoe UI", 16, "bold"),
                fg="#00FFAA", bg="#000000"
            )
            label.pack(pady=20)

            if DateEntry:
                cal = DateEntry(
                    top, width=18, background='#111111', foreground='#00FFAA',
                    borderwidth=2, date_pattern='yyyy-mm-dd',
                    font=("Segoe UI", 14), headersbackground="#222222", headersforeground="#00FFAA"
                )
                cal.pack(pady=10)
            else:
                tk.Label(
                    top, text="Instala tkcalendar para selector visual",
                    fg="red", bg="#000000", font=("Segoe UI", 12, "bold")
                ).pack(pady=10)
                cal = None

            def exportar():
                fecha = cal.get_date().strftime('%Y-%m-%d') if cal else None
                if not fecha:
                    messagebox.showerror("Error", "Selecciona una fecha válida.")
                    return
                try:
                    query_capturas = "SELECT fecha, usuario, codigo, item, cumple, motivo FROM capturas WHERE fecha::date = %s ORDER BY fecha DESC"
                    capturas = self.db_manager.execute_query(query_capturas, (fecha,))
                except Exception as e:
                    capturas = []
                if not capturas:
                    messagebox.showinfo("Sin datos", f"No hay capturas para el día {fecha}")
                    return
                import pandas as pd
                df = pd.DataFrame(capturas)
                ruta = filedialog.asksaveasfilename(
                    defaultextension=".xlsx",
                    filetypes=[("Archivos Excel", "*.xlsx")],
                    initialfile=f"capturas_{fecha}.xlsx",
                    title="Guardar capturas como..."
                )
                if not ruta:
                    return
                df.to_excel(ruta, index=False)
                messagebox.showinfo("Éxito", f"Capturas exportadas: {ruta}")
                top.destroy()

            export_btn = tk.Button(
                top, text="Exportar", command=exportar,
                font=("Segoe UI", 14, "bold"),
                bg="#00FFAA", fg="#000000", activebackground="#00FFAA", activeforeground="#000000",
                relief="flat", borderwidth=0, width=16, height=2
            )
            export_btn.pack(pady=20)

        self.exportar_capturas_button = ct.CTkButton(
            parent,
            text="Exportar Capturas del Día",
            font=("Segoe UI", 14, "bold"),
            fg_color="#000000",
            border_width=2,
            border_color="#00FFAA",
            text_color="#00FFAA",
            hover_color="#111111",
            corner_radius=12,
            width=200,
            height=40,
            command=exportar_capturas
        )
        self.exportar_capturas_button.pack(pady=(0, 10))
    
    def exportar_reporte_dia(self):
        import tkinter as tk
        from tkinter import filedialog
        top = tk.Toplevel(self.master)
        top.title("Seleccionar día para reporte")
        top.geometry("400x220")
        top.configure(bg="#000000")  # Fondo negro

        label = tk.Label(
            top, text="Selecciona la fecha:",
            font=("Segoe UI", 16, "bold"),
            fg="#00FFAA", bg="#000000"
        )
        label.pack(pady=20)

        if DateEntry:
            cal = DateEntry(
                top, width=18, background='#111111', foreground='#00FFAA',
                borderwidth=2, date_pattern='yyyy-mm-dd',
                font=("Segoe UI", 14), headersbackground="#222222", headersforeground="#00FFAA"
            )
            cal.pack(pady=10)
        else:
            tk.Label(
                top, text="Instala tkcalendar para selector visual",
                fg="red", bg="#000000", font=("Segoe UI", 12, "bold")
            ).pack(pady=10)
            cal = None

        def exportar():
            fecha = cal.get_date().strftime('%Y-%m-%d') if cal else None
            if not fecha:
                messagebox.showerror("Error", "Selecciona una fecha válida.")
                return
            try:
                query = """
                    SELECT usuario, codigo_barras, item_id, resultado, fecha_hora
                    FROM consultas
                    WHERE fecha_hora::date = %s
                    ORDER BY fecha_hora DESC
                """
                resultados = self.db_manager.execute_query(query, (fecha,))
                if not resultados:
                    messagebox.showinfo("Sin datos", f"No hay consultas para el día {fecha}")
                    return
                df = pd.DataFrame(resultados)
                ruta = filedialog.asksaveasfilename(
                    defaultextension=".xlsx",
                    filetypes=[("Archivos Excel", "*.xlsx")],
                    initialfile=f"reporte_consultas_{fecha}.xlsx",
                    title="Guardar reporte como..."
                )
                if not ruta:
                    return
                df.to_excel(ruta, index=False)
                messagebox.showinfo("Éxito", f"Reporte exportado: {ruta}")
                top.destroy()
            except Exception as e:
                messagebox.showerror("Error", f"Error exportando reporte: {str(e)}")

        export_btn = tk.Button(
            top, text="Exportar", command=exportar,
            font=("Segoe UI", 14, "bold"),
            bg="#00FFAA", fg="#000000", activebackground="#00FFAA", activeforeground="#000000",
            relief="flat", borderwidth=0, width=16, height=2
        )
        export_btn.pack(pady=20)
    
    def cerrar_sesion(self):
        """Cierra la sesión y regresa a la pantalla de login"""
        try:
            self.logger.log_user_action(self.usuario, "Cerrar sesión")
            self.master.destroy()
            app = EscanerApp()
            app.ejecutar()
        except Exception as e:
            print(f"Error al cerrar sesión: {str(e)}")
    
    def buscar_codigo(self):
        import os
        codigo = self.codigo_var.get().strip()
        # Easter egg: si el usuario escribe 'tetris', lanza el minijuego
        if codigo.lower() == 'tetris':
            try:
                subprocess.Popen(['python', os.path.join('tetris', 'tetris.py')])
            except Exception as e:
                messagebox.showerror("Error", f"No se pudo iniciar Tetris: {e}")
            self.codigo_var.set("")
            self.codigo_entry.focus_set()
            return
        es_valido, mensaje = Validators.validar_codigo_barras(codigo)
        if not es_valido:
            self.resultado_valor.configure(text=mensaje)
            self.clave_valor.configure(text="")
            self.codigo_var.set("")
            self.codigo_entry.focus_set()
            return
        codigo_limpio = Validators.limpiar_codigo_barras(codigo)
        self.search_button.configure(state="disabled", text="Buscando...")
        threading.Thread(target=self._ejecutar_busqueda_nueva, args=(codigo_limpio,), daemon=True).start()

    def _ejecutar_busqueda_nueva(self, codigo):
        try:
            resultado = self.codigo_model.buscar_codigo(codigo)
            if resultado:
                self.master.after(0, lambda: self._mostrar_resultado(resultado))
                # Registrar consulta
                item_id = None
                item = resultado.get('item')
                if item:
                    res = self.db_manager.execute_query("SELECT id FROM items WHERE item = %s", (item,))
                    if res:
                        item_id = res[0]['id']
                self.captura_model.registrar_consulta(self.usuario, codigo, item_id, resultado.get('resultado', ''))
                self.logger.log_user_action(self.usuario, f"Búsqueda exitosa: {codigo}")
            else:
                self.master.after(0, lambda: self._mostrar_no_encontrado())
                self.logger.log_user_action(self.usuario, f"Búsqueda sin resultados: {codigo}")
        except Exception as e:
            self.logger.error(f"Error en búsqueda: {str(e)}")
            self.master.after(0, lambda: self._mostrar_error_busqueda(str(e)))
        finally:
            self.master.after(0, lambda: self._restaurar_boton_busqueda())

    def _mostrar_resultado(self, resultado):
        """Muestra el resultado de la búsqueda"""
        self.clave_valor.configure(text=f"ITEM: {resultado.get('item', '')}")
        res = resultado.get('resultado', 'Sin resultado') or 'Sin resultado'
        self.resultado_valor.configure(text=f"RESULTADO: {res}")
        # Mostrar motivo solo si es NO CUMPLE
        if res == 'NO CUMPLE':
            item = resultado.get('item', '')
            item_id_res = self.db_manager.execute_query("SELECT id FROM items WHERE item = %s", (item,))
            if item_id_res:
                item_id = item_id_res[0]['id']
                motivo = self.db_manager.execute_query("SELECT motivo FROM motivos_no_cumplimiento WHERE item_id = %s", (item_id,))
                if motivo and motivo[0].get('motivo'):
                    self.nom_valor.configure(text=motivo[0]['motivo'])
                    return
        self.nom_valor.configure(text="")
    
    def _mostrar_no_encontrado(self):
        """Muestra mensaje de no encontrado"""
        self.clave_valor.configure(text="")
        self.resultado_valor.configure(text="Código no encontrado")
        self.nom_valor.configure(text="")
    
    def _mostrar_error_busqueda(self, error):
        """Muestra error en la búsqueda"""
        self.clave_valor.configure(text="")
        self.resultado_valor.configure(text=f"Error al buscar: {error}")
        self.nom_valor.configure(text="")
    
    def _restaurar_boton_busqueda(self):
        """Restaura el botón de búsqueda"""
        safe_configure(self.search_button, text="Buscar", state="normal")
        self.codigo_var.set("")
        self.codigo_entry.focus_set()
    
    def cargar_estadisticas(self):
        """Carga las estadísticas de la base de datos"""
        try:
            stats = self.codigo_model.obtener_estadisticas()
            if isinstance(stats, dict):
                self.total_codigos_label.configure(text=f"Total de códigos: {stats.get('total_codigos', 0)}")
                self.con_resultado_label.configure(text=f"Items en total: {stats.get('total_items', 0)}")
                self.sin_resultado_label.configure(text=f"Sin resultado: {stats.get('sin_resultado', 0)}")
                self.ultima_actualizacion_label.configure(text=f"Última actualización: {stats.get('ultima_actualizacion', 'Nunca')}")
            else:
                self.total_codigos_label.configure(text="Total de códigos: 0")
                self.con_resultado_label.configure(text="Items en total: 0")
                self.sin_resultado_label.configure(text="Sin resultado: 0")
                self.ultima_actualizacion_label.configure(text="Última actualización: Nunca")
        except Exception as e:
            self.logger.error(f"Error cargando estadísticas: {str(e)}")
            self.total_codigos_label.configure(text="Total de códigos: 0")
            self.con_resultado_label.configure(text="Items en total: 0")
            self.sin_resultado_label.configure(text="Sin resultado: 0")
            self.ultima_actualizacion_label.configure(text="Última actualización: Nunca")
    
    def actualizar_indice(self):
        es_valido, mensaje = Validators.validar_configuracion_completa(self.config_data)
        if not es_valido:
            messagebox.showerror("Error", mensaje)
            return
        rutas = filedialog.askopenfilenames(
            filetypes=[("Archivos Excel", "*.xls;*.xlsx"), ("Todos", "*.*")],
            title="Seleccionar uno o varios archivos CLP"
        )
        if rutas:
            threading.Thread(target=self._ejecutar_actualizacion_varios, args=(rutas,), daemon=True).start()

    def _ejecutar_actualizacion_varios(self, rutas):
        try:
            self.master.after(0, lambda: self.update_button.configure(state="disabled", text="Actualizando..."))
            resultado = self.codigo_model.cargar_varios_clp(rutas, self.usuario_actual)
            if not isinstance(resultado, dict):
                resultado = {'procesados': 0, 'nuevos_items': 0, 'nuevos_codigos': 0, 'clp_registros': []}
            self.master.after(0, lambda: self._mostrar_resultado_actualizacion(resultado))
            cargas = resultado.get('clp_registros', [])
            if cargas:
                msg = '\n'.join([f"Archivo: {os.path.basename(c['archivo'])}, Usuario: {c['usuario']}, Códigos agregados: {c['codigos_agregados']}" for c in cargas])
                print("Cargas CLP del día:\n" + msg)
            self.logger.log_user_action(self.usuario, "Índice actualizado", f"Registros: {resultado.get('procesados', 0)}")
        except Exception as e:
            self.logger.error(f"Error actualizando índice: {str(e)}")
            self.master.after(0, lambda e=e: messagebox.showerror("Error", f"Error al actualizar índice: {str(e)}"))
        finally:
            self.master.after(0, lambda: self.update_button.configure(state="normal", text="Actualizar Índice"))
            self.master.after(0, self.cargar_estadisticas)
    
    def _mostrar_resultado_actualizacion(self, resultado):
        """Muestra el resultado de la actualización del índice"""
        try:
            if isinstance(resultado, dict):
                mensaje = f"Índice actualizado exitosamente.\n"
                mensaje += f"Nuevos registros: {resultado.get('nuevos_items', 0)}\n"
                mensaje += f"Total de códigos: {resultado.get('nuevos_codigos', 0)}\n"
                mensaje += f"Total procesados: {resultado.get('procesados', 0)}\n"
                messagebox.showinfo("Éxito", mensaje)
            else:
                messagebox.showinfo("Éxito", f"Índice actualizado: {resultado}")
        except Exception as e:
            self.logger.error(f"Error mostrando resultado: {str(e)}")
            messagebox.showerror("Error", f"Error al actualizar índice: {str(e)}")
    
    def _configurar_tab_captura(self, parent):
        # Scrollable frame principal con mejor configuración
        main_frame = ct.CTkScrollableFrame(parent, fg_color="#000000", width=800, height=600)
        main_frame.pack(fill="both", expand=True, padx=20, pady=20)
        
        # Título
        ct.CTkLabel(
            main_frame, 
            text="Captura de Cumplimientos", 
            font=("Segoe UI", 18, "bold"), 
            text_color="#00FFAA"
        ).pack(pady=(0, 20))
        
        # Botón para subir capturas pendientes (solo admin y captura) ANTES de los campos
        if self.rol in ["admin", "captura"]:
            self.subir_pendientes_btn = ct.CTkButton(
                main_frame,
                text="Subir capturas pendientes",
                command=self.subir_capturas_offline,
                font=("Segoe UI", 12, "bold"),
                fg_color="#00FFAA",
                text_color="#000000",
                border_width=2,
                border_color="#00FFAA",
                corner_radius=10
            )
            self.subir_pendientes_btn.pack(pady=(0, 10))
            self._actualizar_estado_pendientes()
        
        # Variables
        self.codigo_captura_var = StringVar()
        self.item_captura_var = StringVar()
        self.motivo_captura_var = StringVar(value="Instrucciones de cuidado")
        self.cumple_captura_var = StringVar(value="NO CUMPLE")
        
        # Frame para campos de entrada
        campos_frame = ct.CTkFrame(main_frame, fg_color="#000000")
        campos_frame.pack(fill="x", pady=(0, 20))
        
        # Código de barras
        ct.CTkLabel(
            campos_frame, 
            text="Código de barras:", 
            text_color="#00FFAA", 
            font=("Segoe UI", 13, "bold")
        ).pack(anchor="w", padx=10, pady=(10, 0))
        
        self.codigo_captura_entry = ct.CTkEntry(
            campos_frame, 
            textvariable=self.codigo_captura_var,
            font=("Segoe UI", 13),
            width=400,
            height=36,
            corner_radius=12,
            border_width=2,
            border_color="#00FFAA",
            fg_color="#000000",
            text_color="#00FFAA"
        )
        self.codigo_captura_entry.pack(fill="x", padx=10, pady=(0, 8))
        
        # Evento para buscar automáticamente el item cuando se
        self.codigo_captura_entry.bind("<Return>", lambda e: self._buscar_item_automatico())
        
        # Item
        ct.CTkLabel(
            campos_frame, 
            text="Item:", 
            text_color="#00FFAA", 
            font=("Segoe UI", 13, "bold")
        ).pack(anchor="w", padx=10, pady=(10, 0))
        self.item_captura_entry = ct.CTkEntry(
            campos_frame, 
            textvariable=self.item_captura_var,
            font=("Segoe UI", 13),
            width=400,
            height=36,
            corner_radius=12,
            border_width=2,
            border_color="#00FFAA",
            fg_color="#000000",
            text_color="#00FFAA",
            state="disabled"  # <-- Solo lectura
        )
        self.item_captura_entry.pack(fill="x", padx=10, pady=(0, 8))
        
        # Cumple/No cumple SIEMPRE visible
        ct.CTkLabel(
            campos_frame, 
            text="¿Cumple?", 
            text_color="#00FFAA", 
            font=("Segoe UI", 13, "bold")
        ).pack(anchor="w", padx=10, pady=(10, 0))
        self.cumple_captura_menu = ct.CTkOptionMenu(
            campos_frame,
            variable=self.cumple_captura_var,
            values=["CUMPLE", "NO CUMPLE"],
            fg_color="#000000",
            text_color="#00FFAA",
            font=("Segoe UI", 13),
            width=400,
            height=36
        )
        self.cumple_captura_menu.pack(fill="x", padx=10, pady=(0, 8))

        # Frame para motivo y botón guardar
        motivo_guardar_frame = ct.CTkFrame(campos_frame, fg_color="#000000")
        motivo_guardar_frame.pack(fill="x", pady=(0, 10))

        # Motivo siempre visible, pero desactivado si Cumple es 'CUMPLE'
        motivo_options = [
            "Instrucciones de cuidado",
            "Insumos",
            "Pais de origen",
            "Talla",
            "Importador",
            "Marca"
        ]
        self.motivo_label = ct.CTkLabel(
            motivo_guardar_frame, 
            text="Motivo:", 
            text_color="#00FFAA", 
            font=("Segoe UI", 13, "bold")
        )
        self.motivo_label.pack(anchor="w", padx=10, pady=(10, 0))
        self.motivo_captura_var = StringVar(value=motivo_options[0])
        self.motivo_captura_menu = ct.CTkOptionMenu(
            motivo_guardar_frame,
            variable=self.motivo_captura_var,
            values=motivo_options,
            fg_color="#000000",
            text_color="#00FFAA",
            font=("Segoe UI", 13),
            width=400,
            height=36
        )
        self.motivo_captura_menu.pack(fill="x", padx=10, pady=(0, 8))
        def on_cumple_change(*args):
            if self.cumple_captura_var.get() == "NO CUMPLE":
                self.motivo_captura_menu.configure(state="normal", text_color="#00FFAA")
                self.motivo_label.configure(text_color="#00FFAA")
            else:
                self.motivo_captura_menu.configure(state="disabled", text_color="#888888")
                self.motivo_label.configure(text_color="#888888")
        self.cumple_captura_var.trace_add('write', on_cumple_change)
        on_cumple_change()

        # Botón guardar SIEMPRE al final del frame
        self.guardar_btn = ct.CTkButton(
            motivo_guardar_frame,
            text="Guardar",
            command=self.guardar_captura_offline,
            font=("Segoe UI", 12, "bold"),
            fg_color="#00FFAA",
            text_color="#000000",
            border_width=2,
            border_color="#00FFAA",
            corner_radius=10
        )
        self.guardar_btn.pack(pady=(10, 0))
    
    def guardar_captura_offline(self):
        """Guarda la captura y la inserta/actualiza directamente en la tabla de ítems y en el historial de capturas"""
        codigo = self.codigo_captura_var.get().strip()
        motivo = self.motivo_captura_var.get().strip() if self.cumple_captura_var.get() == "NO CUMPLE" else ""
        cumple = self.cumple_captura_var.get().strip()
        if not codigo or not cumple:
            messagebox.showwarning("Campos vacíos", "Código y cumple son obligatorios")
            return
        # Buscar item_id en codigos_barras
        res = self.codigo_model.db.execute_query(
            "SELECT item_id FROM codigos_barras WHERE codigo_barras = %s", (codigo,))
        if not res:
            messagebox.showerror("Error", "El código no existe en la base de datos. Solo se pueden capturar códigos existentes.")
            return
        item_id = res[0]['item_id']
        # Obtener el nombre del item
        item_res = self.codigo_model.db.execute_query("SELECT item FROM items WHERE id = %s", (item_id,))
        item = item_res[0]['item'] if item_res else ''
        # Actualizar resultado en items
        self.codigo_model.db.execute_query(
            "UPDATE items SET resultado = %s, fecha_actualizacion = NOW() WHERE id = %s",
            (cumple, item_id), fetch=False)
        # Manejo de motivo
        if cumple == "NO CUMPLE":
            self.codigo_model.db.execute_query(
                "INSERT INTO motivos_no_cumplimiento (item_id, motivo) VALUES (%s, %s) ON CONFLICT (item_id) DO UPDATE SET motivo = EXCLUDED.motivo",
                (item_id, motivo), fetch=False)
        else:
            self.codigo_model.db.execute_query(
                "DELETE FROM motivos_no_cumplimiento WHERE item_id = %s", (item_id,), fetch=False)
        # Guardar en historial de capturas
        self.codigo_model.db.execute_query(
            "INSERT INTO capturas (codigo, item, motivo, cumple, usuario, fecha) VALUES (%s, %s, %s, %s, %s, NOW())",
            (codigo, item, motivo, cumple, self.usuario), fetch=False)
        messagebox.showinfo("Éxito", "Captura guardada y actualizada en ítems")
        self.codigo_captura_var.set("")
        self.item_captura_var.set("")
        self.codigo_captura_entry.focus_set()
    
    def subir_capturas_offline(self):
        """Sube las capturas pendientes del archivo local a la base de datos"""
        import os
        ruta = f"capturas_pendientes_{self.usuario}.json"
        if not os.path.exists(ruta):
            messagebox.showinfo("Sin capturas pendientes", "No hay capturas pendientes para subir.")
            return
        try:
            with open(ruta, "r", encoding="utf-8") as f:
                capturas = json.load(f)
            subidas = 0
            for cap in capturas:
                try:
                    if self.captura_model.guardar_captura(cap["codigo"], cap["item"], cap["motivo"], cap["cumple"], cap["usuario"]):
                        subidas += 1
                except Exception as e:
                    self.logger.error(f"Error subiendo captura offline: {str(e)}")
            if subidas > 0:
                os.remove(ruta)
                messagebox.showinfo("Éxito", f"{subidas} capturas subidas correctamente.")
            else:
                messagebox.showwarning("Sin conexión", "No se pudo subir ninguna captura. Intenta de nuevo más tarde.")
        except Exception as e:
            self.logger.error(f"Error leyendo capturas offline: {str(e)}")
            messagebox.showerror("Error", f"Error leyendo capturas pendientes: {str(e)}")
        self._actualizar_estado_pendientes()
    
    def _buscar_item_automatico(self):
        """Busca automáticamente el item cuando se ingresa un código de barras"""
        codigo = self.codigo_captura_var.get().strip()
        
        # Solo buscar si el código tiene al menos 8 caracteres (código de barras mínimo)
        if len(codigo) >= 8:
            # Validar formato del código
            es_valido, _ = Validators.validar_codigo_barras(codigo)
            if es_valido:
                # Limpiar código
                codigo_limpio = Validators.limpiar_codigo_barras(codigo)
                
                # Buscar en hilo separado para no bloquear la interfaz
                threading.Thread(
                    target=self._ejecutar_busqueda_automatica, 
                    args=(codigo_limpio,), 
                    daemon=True
                ).start()
    
    def _ejecutar_busqueda_automatica(self, codigo):
        """Ejecuta la búsqueda automática del item y resultado"""
        try:
            # Buscar item_id y datos del item
            res = self.codigo_model.db.execute_query(
                "SELECT cb.item_id, i.item, i.resultado FROM codigos_barras cb JOIN items i ON cb.item_id = i.id WHERE cb.codigo_barras = %s",
                (codigo,))
            if res:
                item_id = res[0]['item_id']
                item = res[0]['item']
                resultado = res[0]['resultado']
                self.master.after(0, lambda: self.item_captura_var.set(item))
                self.master.after(0, lambda: self.cumple_captura_var.set(resultado))
                # Si el resultado es NO CUMPLE, buscar motivo y mostrarlo
                if resultado == 'NO CUMPLE':
                    motivo = self.codigo_model.db.execute_query(
                        "SELECT motivo FROM motivos_no_cumplimiento WHERE item_id = %s", (item_id,))
                    if motivo and motivo[0].get('motivo'):
                        self.master.after(0, lambda: self.motivo_captura_var.set(motivo[0]['motivo']))
                self.logger.log_user_action(self.usuario, f"Búsqueda automática exitosa: {codigo}")
        except Exception as e:
            self.logger.error(f"Error en búsqueda automática: {str(e)}")
    
    def _actualizar_estado_pendientes(self):
        """Actualiza la visibilidad del botón de subir capturas pendientes"""
        import os
        ruta = f"capturas_pendientes_{self.usuario}.json"
        if hasattr(self, "subir_pendientes_btn"):
            if os.path.exists(ruta):
                try:
                    with open(ruta, "r", encoding="utf-8") as f:
                        capturas = json.load(f)
                    num_capturas = len(capturas)
                    self.subir_pendientes_btn.configure(
                        state="normal", 
                        text=f"Subir capturas pendientes ({num_capturas})"
                    )
                except Exception:
                    self.subir_pendientes_btn.configure(
                        state="normal", 
                        text="Subir capturas pendientes"
                    )
            else:
                self.subir_pendientes_btn.configure(
                    state="disabled", 
                    text="No hay capturas pendientes"
                )

    def _configurar_tab_configuracion(self, parent):
        main_frame = ct.CTkFrame(parent, fg_color="#000000")
        main_frame.pack(fill="both", expand=True, padx=40, pady=40)

        ct.CTkLabel(
            main_frame,
            text="Configuración de Archivos CLP",
            font=("Segoe UI", 18, "bold"),
            text_color="#00FFAA"
        ).pack(pady=(0, 20))

        # Variable para mostrar archivos seleccionados
        self.rutas_clp_var = StringVar(value="No hay archivos seleccionados")

        archivos_frame = ct.CTkFrame(main_frame, fg_color="#000000")
        archivos_frame.pack(fill="x", pady=(0, 20))

        ct.CTkLabel(
            archivos_frame,
            text="Archivos CLP seleccionados:",
            text_color="#00FFAA",
            font=("Segoe UI", 14, "bold")
        ).pack(anchor="w", padx=20, pady=(10, 0))

        self.rutas_clp_label = ct.CTkLabel(
            archivos_frame,
            textvariable=self.rutas_clp_var,
            text_color="#55DDFF",
            wraplength=600,
            fg_color="#000000"
        )
        self.rutas_clp_label.pack(anchor="w", padx=20, pady=(0, 5))

        def seleccionar_archivos():
            rutas = filedialog.askopenfilenames(
                filetypes=[("Archivos Excel", "*.xls;*.xlsx"), ("Todos", "*.*")],
                title="Seleccionar uno o varios archivos CLP"
            )
            if rutas:
                self.rutas_clp_var.set("\n".join(rutas))
                self.rutas_clp = rutas
            else:
                self.rutas_clp_var.set("No hay archivos seleccionados")
                self.rutas_clp = []

        ct.CTkButton(
            archivos_frame,
            text="Seleccionar Archivos CLP",
            command=seleccionar_archivos,
            font=("Segoe UI", 13, "bold"),
            fg_color="#000000",
            hover_color="#111111",
            border_width=2,
            border_color="#00FFAA",
            text_color="#00FFAA",
            corner_radius=12,
            width=260,
            height=36
        ).pack(pady=5, padx=20, anchor="w")

        def cargar_archivos_clp():
            if not hasattr(self, "rutas_clp") or not self.rutas_clp:
                messagebox.showerror("Error", "No hay archivos CLP seleccionados.")
                return
            resultado = self.codigo_model.cargar_varios_clp(self.rutas_clp, self.usuario)
            if not isinstance(resultado, dict):
                resultado = {'procesados': 0, 'nuevos_items': 0, 'nuevos_codigos': 0, 'clp_registros': []}
            mensaje = f"Carga completada.\nNuevos items: {resultado.get('nuevos_items', 0)}\nNuevos códigos: {resultado.get('nuevos_codigos', 0)}\nTotal procesados: {resultado.get('procesados', 0)}"
            messagebox.showinfo("Éxito", mensaje)
            self.rutas_clp_var.set("No hay archivos seleccionados")
            self.rutas_clp = []
            self.cargar_estadisticas()

        ct.CTkButton(
            archivos_frame,
            text="Cargar Archivos CLP",
            command=cargar_archivos_clp,
            font=("Segoe UI", 13, "bold"),
            fg_color="#00FFAA",
            text_color="#000000",
            border_width=2,
            border_color="#00FFAA",
            corner_radius=12,
            width=260,
            height=36
        ).pack(pady=5, padx=20, anchor="w")

    def mostrar_historial_cargas_y_consultas(self):
        import tkinter as tk
        from tkinter import ttk, filedialog
        import customtkinter as ct
        import pandas as pd
        # Crear ventana toplevel
        top = ct.CTkToplevel(self.master)
        top.title("Historial del día")
        top.geometry("700x700")
        top.configure(fg_color="#000000")
        top.lift()
        top.attributes('-topmost', True)
        top.focus_force()

        # Frame principal
        main_frame = ct.CTkFrame(top, fg_color="#000000")
        main_frame.pack(fill="both", expand=True, padx=20, pady=20)

        # Filtro por nombre de archivo
        filtro_var = tk.StringVar()
        def actualizar_cargas(*args):
            filtro = filtro_var.get().strip().lower()
            try:
                if filtro:
                    # Buscar en todo el historial por coincidencia de nombre de archivo
                    query_cargas = "SELECT archivo, usuario, fecha_carga, codigos_agregados FROM clp_cargas WHERE LOWER(archivo) LIKE %s ORDER BY fecha_carga DESC"
                    cargas = self.db_manager.execute_query(query_cargas, (f"%{filtro}%",))
                else:
                    # Solo mostrar las cargas del día actual
                    query_cargas = "SELECT archivo, usuario, fecha_carga, codigos_agregados FROM clp_cargas WHERE fecha_carga::date = CURRENT_DATE ORDER BY fecha_carga DESC"
                    cargas = self.db_manager.execute_query(query_cargas)
            except Exception as e:
                cargas = []
            cargas_text = "Sin cargas."
            if cargas:
                cargas_text = "\n".join([
                    f"{c['fecha_carga']}: {c['archivo']} (Usuario: {c['usuario']}, Códigos: {c['codigos_agregados']})" for c in cargas
                ])
            cargas_label.configure(state="normal")
            cargas_label.delete("1.0", tk.END)
            cargas_label.insert("1.0", cargas_text)
            cargas_label.configure(state="disabled")

        filtro_frame = ct.CTkFrame(main_frame, fg_color="#000000")
        filtro_frame.pack(fill="x", pady=(0, 5))
        ct.CTkLabel(filtro_frame, text="Filtrar por archivo:", text_color="#00FFAA").pack(side="left", padx=(0, 8))
        filtro_entry = ct.CTkEntry(filtro_frame, textvariable=filtro_var, width=200)
        filtro_entry.pack(side="left")
        filtro_var.trace_add('write', lambda *args: actualizar_cargas())

        # Sección de cargas CLP
        ct.CTkLabel(
            main_frame, text="Cargas CLP del día:", font=("Segoe UI", 16, "bold"), text_color="#00FFAA", fg_color="#000000"
        ).pack(anchor="w", pady=(0, 5))
        cargas_label = ct.CTkTextbox(main_frame, width=650, height=60, fg_color="#111111", text_color="#00FFAA", font=("Segoe UI", 12))
        cargas_label.pack(pady=(0, 15))
        actualizar_cargas()

        # Sección de consultas recientes
        ct.CTkLabel(
            main_frame, text="Consultas recientes:", font=("Segoe UI", 16, "bold"), text_color="#00FFAA", fg_color="#000000"
        ).pack(anchor="w", pady=(0, 5))
        try:
            query_consultas = "SELECT fecha_hora, usuario, codigo_barras, resultado FROM consultas WHERE fecha_hora::date = CURRENT_DATE ORDER BY fecha_hora DESC LIMIT 50"
            consultas = self.db_manager.execute_query(query_consultas)
        except Exception as e:
            consultas = []
        # Tabla de consultas
        table_frame = ct.CTkFrame(main_frame, fg_color="#111111")
        table_frame.pack(fill="both", expand=True, pady=(0, 10))
        columns = ("Fecha/Hora", "Usuario", "Código de Barras", "Resultado")
        tree = ttk.Treeview(table_frame, columns=columns, show="headings", height=12)
        for col in columns:
            tree.heading(col, text=col)
        # Estilo ttk para fondo oscuro y tipo Excel
        style = ttk.Style()
        style.theme_use('default')
        style.configure("Treeview",
                        background="#111111",
                        foreground="#00FFAA",
                        rowheight=24,
                        fieldbackground="#111111",
                        font=("Segoe UI", 11),
                        bordercolor="#222222",
                        borderwidth=1)
        style.configure("Treeview.Heading",
                        background="#00FFAA",
                        foreground="#000000",
                        font=("Segoe UI", 13, "bold"),
                        relief="flat")
        style.map('Treeview', background=[('selected', '#222222')])
        style.layout("Treeview", [
            ('Treeview.treearea', {'sticky': 'nswe'})
        ])
        # Ajustar ancho de columnas
        tree.column("Fecha/Hora", width=160, anchor="center")
        tree.column("Usuario", width=100, anchor="center")
        tree.column("Código de Barras", width=220, anchor="center")
        tree.column("Resultado", width=120, anchor="center")
        # Insertar datos con rayado
        for i, c in enumerate(consultas):
            values = (c['fecha_hora'], c['usuario'], c['codigo_barras'], c['resultado'] or "Sin resultado")
            tag = 'evenrow' if i % 2 == 0 else 'oddrow'
            tree.insert("", "end", values=values, tags=(tag,))
        tree.tag_configure('evenrow', background='#181818')
        tree.tag_configure('oddrow', background='#222222')
        # Scrollbar
        scrollbar = ttk.Scrollbar(table_frame, orient="vertical", command=tree.yview)
        tree.configure(yscrollcommand=scrollbar.set)
        tree.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        # Sección de capturas del día
        ct.CTkLabel(
            main_frame, text="Capturas del día:", font=("Segoe UI", 16, "bold"), text_color="#00FFAA", fg_color="#000000"
        ).pack(anchor="w", pady=(10, 5))
        # Tabla de capturas
        capturas_frame = ct.CTkFrame(main_frame, fg_color="#111111")
        capturas_frame.pack(fill="both", expand=True, pady=(0, 10))
        columns = ("Fecha/Hora", "Usuario", "Código", "Item", "Resultado", "Motivo")
        capturas_tree = ttk.Treeview(capturas_frame, columns=columns, show="headings", height=8)
        for col in columns:
            capturas_tree.heading(col, text=col)
        # Estilo ttk para fondo oscuro
        style = ttk.Style()
        style.theme_use('default')
        style.configure("Treeview",
                        background="#111111",
                        foreground="#00FFAA",
                        rowheight=24,
                        fieldbackground="#111111",
                        font=("Segoe UI", 11),
                        bordercolor="#222222",
                        borderwidth=1)
        style.configure("Treeview.Heading",
                        background="#00FFAA",
                        foreground="#000000",
                        font=("Segoe UI", 13, "bold"),
                        relief="flat")
        style.map('Treeview', background=[('selected', '#222222')])
        style.layout("Treeview", [
            ('Treeview.treearea', {'sticky': 'nswe'})
        ])
        # Ajustar ancho de columnas
        capturas_tree.column("Fecha/Hora", width=140, anchor="center")
        capturas_tree.column("Usuario", width=80, anchor="center")
        capturas_tree.column("Código", width=160, anchor="center")
        capturas_tree.column("Item", width=80, anchor="center")
        capturas_tree.column("Resultado", width=100, anchor="center")
        capturas_tree.column("Motivo", width=160, anchor="center")
        # Consultar capturas del día
        try:
            query_capturas = "SELECT fecha, usuario, codigo, item, cumple, motivo FROM capturas WHERE fecha::date = CURRENT_DATE ORDER BY fecha DESC"
            capturas = self.db_manager.execute_query(query_capturas)
        except Exception as e:
            capturas = []
        for i, c in enumerate(capturas):
            values = (
                c['fecha'], c['usuario'], c['codigo'], c['item'], c['cumple'], c['motivo'] or ""
            )
            tag = 'evenrow' if i % 2 == 0 else 'oddrow'
            capturas_tree.insert("", "end", values=values, tags=(tag,))
        capturas_tree.tag_configure('evenrow', background='#181818')
        capturas_tree.tag_configure('oddrow', background='#222222')
        # Scrollbar
        scrollbar = ttk.Scrollbar(capturas_frame, orient="vertical", command=capturas_tree.yview)
        capturas_tree.configure(yscrollcommand=scrollbar.set)
        capturas_tree.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        # Botón cerrar
        cerrar_btn = ct.CTkButton(
            main_frame, text="Cerrar", command=top.destroy,
            font=("Segoe UI", 14, "bold"), fg_color="#00FFAA", text_color="#000000",
            width=200, height=40, corner_radius=12
        )
        cerrar_btn.pack(pady=10)

        # Botón historial del día
        self.historial_button = ct.CTkButton(
            parent,
            text="Ver Historial del Día",
            font=("Segoe UI", 12, "bold"),
            fg_color="#000000",
            border_width=2,
            border_color="#00FFAA",
            text_color="#00FFAA",
            hover_color="#111111",
            corner_radius=12,
            width=200,
            height=32,
            command=self.mostrar_historial_cargas_y_consultas
        )
        self.historial_button.pack(pady=(0, 18))

        # Botón solo para admins: Exportar Reporte del Día
        if self.rol == "admin":
            self.exportar_reporte_button = ct.CTkButton(
                parent,
                text="Exportar Reporte del Día",
                font=("Segoe UI", 12, "bold"),
                fg_color="#000000",
                border_width=2,
                border_color="#00FFAA",
                text_color="#00FFAA",
                hover_color="#111111",
                corner_radius=12,
                width=200,
                height=32,
                command=self.exportar_reporte_dia
            )
            self.exportar_reporte_button.pack(pady=(0, 10))
        else:
            self.exportar_reporte_button = None

        # Botón Exportar Capturas del Día (para todos los roles)
        def exportar_capturas():
            import tkinter as tk
            from tkinter import filedialog, messagebox
            from datetime import datetime
            top = tk.Toplevel(self.master)
            top.title("Seleccionar día para exportar capturas")
            top.geometry("400x220")
            top.configure(bg="#000000")  # Fondo negro

            label = tk.Label(
                top, text="Selecciona la fecha:",
                font=("Segoe UI", 16, "bold"),
                fg="#00FFAA", bg="#000000"
            )
            label.pack(pady=20)

            if DateEntry:
                cal = DateEntry(
                    top, width=18, background='#111111', foreground='#00FFAA',
                    borderwidth=2, date_pattern='yyyy-mm-dd',
                    font=("Segoe UI", 14), headersbackground="#222222", headersforeground="#00FFAA"
                )
                cal.pack(pady=10)
            else:
                tk.Label(
                    top, text="Instala tkcalendar para selector visual",
                    fg="red", bg="#000000", font=("Segoe UI", 12, "bold")
                ).pack(pady=10)
                cal = None

            def exportar():
                fecha = cal.get_date().strftime('%Y-%m-%d') if cal else None
                if not fecha:
                    messagebox.showerror("Error", "Selecciona una fecha válida.")
                    return
                try:
                    query_capturas = "SELECT fecha, usuario, codigo, item, cumple, motivo FROM capturas WHERE fecha::date = %s ORDER BY fecha DESC"
                    capturas = self.db_manager.execute_query(query_capturas, (fecha,))
                except Exception as e:
                    capturas = []
                if not capturas:
                    messagebox.showinfo("Sin datos", f"No hay capturas para el día {fecha}")
                    return
                import pandas as pd
                df = pd.DataFrame(capturas)
                ruta = filedialog.asksaveasfilename(
                    defaultextension=".xlsx",
                    filetypes=[("Archivos Excel", "*.xlsx")],
                    initialfile=f"capturas_{fecha}.xlsx",
                    title="Guardar capturas como..."
                )
                if not ruta:
                    return
                df.to_excel(ruta, index=False)
                messagebox.showinfo("Éxito", f"Capturas exportadas: {ruta}")
                top.destroy()

            export_btn = tk.Button(
                top, text="Exportar", command=exportar,
                font=("Segoe UI", 14, "bold"),
                bg="#00FFAA", fg="#000000", activebackground="#00FFAA", activeforeground="#000000",
                relief="flat", borderwidth=0, width=16, height=2
            )
            export_btn.pack(pady=20)

        self.exportar_capturas_button = ct.CTkButton(
            parent,
            text="Exportar Capturas del Día",
            font=("Segoe UI", 14, "bold"),
            fg_color="#000000",
            border_width=2,
            border_color="#00FFAA",
            text_color="#00FFAA",
            hover_color="#111111",
            corner_radius=12,
            width=200,
            height=40,
            command=exportar_capturas
        )
        self.exportar_capturas_button.pack(pady=(0, 10))
    
    def exportar_reporte_dia(self):
        import tkinter as tk
        from tkinter import filedialog
        top = tk.Toplevel(self.master)
        top.title("Seleccionar día para reporte")
        top.geometry("400x220")
        top.configure(bg="#000000")  # Fondo negro

        label = tk.Label(
            top, text="Selecciona la fecha:",
            font=("Segoe UI", 16, "bold"),
            fg="#00FFAA", bg="#000000"
        )
        label.pack(pady=20)

        if DateEntry:
            cal = DateEntry(
                top, width=18, background='#111111', foreground='#00FFAA',
                borderwidth=2, date_pattern='yyyy-mm-dd',
                font=("Segoe UI", 14), headersbackground="#222222", headersforeground="#00FFAA"
            )
            cal.pack(pady=10)
        else:
            tk.Label(
                top, text="Instala tkcalendar para selector visual",
                fg="red", bg="#000000", font=("Segoe UI", 12, "bold")
            ).pack(pady=10)
            cal = None

        def exportar():
            fecha = cal.get_date().strftime('%Y-%m-%d') if cal else None
            if not fecha:
                messagebox.showerror("Error", "Selecciona una fecha válida.")
                return
            try:
                query = """
                    SELECT usuario, codigo_barras, item_id, resultado, fecha_hora
                    FROM consultas
                    WHERE fecha_hora::date = %s
                    ORDER BY fecha_hora DESC
                """
                resultados = self.db_manager.execute_query(query, (fecha,))
                if not resultados:
                    messagebox.showinfo("Sin datos", f"No hay consultas para el día {fecha}")
                    return
                df = pd.DataFrame(resultados)
                ruta = filedialog.asksaveasfilename(
                    defaultextension=".xlsx",
                    filetypes=[("Archivos Excel", "*.xlsx")],
                    initialfile=f"reporte_consultas_{fecha}.xlsx",
                    title="Guardar reporte como..."
                )
                if not ruta:
                    return
                df.to_excel(ruta, index=False)
                messagebox.showinfo("Éxito", f"Reporte exportado: {ruta}")
                top.destroy()
            except Exception as e:
                messagebox.showerror("Error", f"Error exportando reporte: {str(e)}")

        export_btn = tk.Button(
            top, text="Exportar", command=exportar,
            font=("Segoe UI", 14, "bold"),
            bg="#00FFAA", fg="#000000", activebackground="#00FFAA", activeforeground="#000000",
            relief="flat", borderwidth=0, width=16, height=2
        )
        export_btn.pack(pady=20)
    
    def cerrar_sesion(self):
        """Cierra la sesión y regresa a la pantalla de login"""
        try:
            self.logger.log_user_action(self.usuario, "Cerrar sesión")
            self.master.destroy()
            app = EscanerApp()
            app.ejecutar()
        except Exception as e:
            print(f"Error al cerrar sesión: {str(e)}")
    
    def buscar_codigo(self):
        import os
        codigo = self.codigo_var.get().strip()
        # Easter egg: si el usuario escribe 'tetris', lanza el minijuego
        if codigo.lower() == 'tetris':
            try:
                subprocess.Popen(['python', os.path.join('tetris', 'tetris.py')])
            except Exception as e:
                messagebox.showerror("Error", f"No se pudo iniciar Tetris: {e}")
            self.codigo_var.set("")
            self.codigo_entry.focus_set()
            return
        es_valido, mensaje = Validators.validar_codigo_barras(codigo)
        if not es_valido:
            self.resultado_valor.configure(text=mensaje)
            self.clave_valor.configure(text="")
            self.codigo_var.set("")
            self.codigo_entry.focus_set()
            return
        codigo_limpio = Validators.limpiar_codigo_barras(codigo)
        self.search_button.configure(state="disabled", text="Buscando...")
        threading.Thread(target=self._ejecutar_busqueda_nueva, args=(codigo_limpio,), daemon=True).start()

    def _ejecutar_busqueda_nueva(self, codigo):
        try:
            resultado = self.codigo_model.buscar_codigo(codigo)
            if resultado:
                self.master.after(0, lambda: self._mostrar_resultado(resultado))
                # Registrar consulta
                item_id = None
                item = resultado.get('item')
                if item:
                    res = self.db_manager.execute_query("SELECT id FROM items WHERE item = %s", (item,))
                    if res:
                        item_id = res[0]['id']
                self.captura_model.registrar_consulta(self.usuario, codigo, item_id, resultado.get('resultado', ''))
                self.logger.log_user_action(self.usuario, f"Búsqueda exitosa: {codigo}")
            else:
                self.master.after(0, lambda: self._mostrar_no_encontrado())
                self.logger.log_user_action(self.usuario, f"Búsqueda sin resultados: {codigo}")
        except Exception as e:
            self.logger.error(f"Error en búsqueda: {str(e)}")
            self.master.after(0, lambda: self._mostrar_error_busqueda(str(e)))
        finally:
            self.master.after(0, lambda: self._restaurar_boton_busqueda())

    def _mostrar_resultado(self, resultado):
        """Muestra el resultado de la búsqueda"""
        self.clave_valor.configure(text=f"ITEM: {resultado.get('item', '')}")
        res = resultado.get('resultado', 'Sin resultado') or 'Sin resultado'
        self.resultado_valor.configure(text=f"RESULTADO: {res}")
        # Mostrar motivo solo si es NO CUMPLE
        if res == 'NO CUMPLE':
            item = resultado.get('item', '')
            item_id_res = self.db_manager.execute_query("SELECT id FROM items WHERE item = %s", (item,))
            if item_id_res:
                item_id = item_id_res[0]['id']
                motivo = self.db_manager.execute_query("SELECT motivo FROM motivos_no_cumplimiento WHERE item_id = %s", (item_id,))
                if motivo and motivo[0].get('motivo'):
                    self.nom_valor.configure(text=motivo[0]['motivo'])
                    return
        self.nom_valor.configure(text="")
    
    def _mostrar_no_encontrado(self):
        """Muestra mensaje de no encontrado"""
        self.clave_valor.configure(text="")
        self.resultado_valor.configure(text="Código no encontrado")
        self.nom_valor.configure(text="")
    
    def _mostrar_error_busqueda(self, error):
        """Muestra error en la búsqueda"""
        self.clave_valor.configure(text="")
        self.resultado_valor.configure(text=f"Error al buscar: {error}")
        self.nom_valor.configure(text="")
    
    def _restaurar_boton_busqueda(self):
        """Restaura el botón de búsqueda"""
        safe_configure(self.search_button, text="Buscar", state="normal")
        self.codigo_var.set("")
        self.codigo_entry.focus_set()
    
    def cargar_estadisticas(self):
        """Carga las estadísticas de la base de datos"""
        try:
            stats = self.codigo_model.obtener_estadisticas()
            if isinstance(stats, dict):
                self.total_codigos_label.configure(text=f"Total de códigos: {stats.get('total_codigos', 0)}")
                self.con_resultado_label.configure(text=f"Items en total: {stats.get('total_items', 0)}")
                self.sin_resultado_label.configure(text=f"Sin resultado: {stats.get('sin_resultado', 0)}")
                self.ultima_actualizacion_label.configure(text=f"Última actualización: {stats.get('ultima_actualizacion', 'Nunca')}")
            else:
                self.total_codigos_label.configure(text="Total de códigos: 0")
                self.con_resultado_label.configure(text="Items en total: 0")
                self.sin_resultado_label.configure(text="Sin resultado: 0")
                self.ultima_actualizacion_label.configure(text="Última actualización: Nunca")
        except Exception as e:
            self.logger.error(f"Error cargando estadísticas: {str(e)}")
            self.total_codigos_label.configure(text="Total de códigos: 0")
            self.con_resultado_label.configure(text="Items en total: 0")
            self.sin_resultado_label.configure(text="Sin resultado: 0")
            self.ultima_actualizacion_label.configure(text="Última actualización: Nunca")
    
    def actualizar_indice(self):
        es_valido, mensaje = Validators.validar_configuracion_completa(self.config_data)
        if not es_valido:
            messagebox.showerror("Error", mensaje)
            return
        rutas = filedialog.askopenfilenames(
            filetypes=[("Archivos Excel", "*.xls;*.xlsx"), ("Todos", "*.*")],
            title="Seleccionar uno o varios archivos CLP"
        )
        if rutas:
            threading.Thread(target=self._ejecutar_actualizacion_varios, args=(rutas,), daemon=True).start()

    def _ejecutar_actualizacion_varios(self, rutas):
        try:
            self.master.after(0, lambda: self.update_button.configure(state="disabled", text="Actualizando..."))
            resultado = self.codigo_model.cargar_varios_clp(rutas, self.usuario_actual)
            if not isinstance(resultado, dict):
                resultado = {'procesados': 0, 'nuevos_items': 0, 'nuevos_codigos': 0, 'clp_registros': []}
            self.master.after(0, lambda: self._mostrar_resultado_actualizacion(resultado))
            cargas = resultado.get('clp_registros', [])
            if cargas:
                msg = '\n'.join([f"Archivo: {os.path.basename(c['archivo'])}, Usuario: {c['usuario']}, Códigos agregados: {c['codigos_agregados']}" for c in cargas])
                print("Cargas CLP del día:\n" + msg)
            self.logger.log_user_action(self.usuario, "Índice actualizado", f"Registros: {resultado.get('procesados', 0)}")
        except Exception as e:
            self.logger.error(f"Error actualizando índice: {str(e)}")
            self.master.after(0, lambda e=e: messagebox.showerror("Error", f"Error al actualizar índice: {str(e)}"))
        finally:
            self.master.after(0, lambda: self.update_button.configure(state="normal", text="Actualizar Índice"))
            self.master.after(0, self.cargar_estadisticas)
    
    def _mostrar_resultado_actualizacion(self, resultado):
        """Muestra el resultado de la actualización del índice"""
        try:
            if isinstance(resultado, dict):
                mensaje = f"Índice actualizado exitosamente.\n"
                mensaje += f"Nuevos registros: {resultado.get('nuevos_items', 0)}\n"
                mensaje += f"Total de códigos: {resultado.get('nuevos_codigos', 0)}\n"
                mensaje += f"Total procesados: {resultado.get('procesados', 0)}\n"
                messagebox.showinfo("Éxito", mensaje)
            else:
                messagebox.showinfo("Éxito", f"Índice actualizado: {resultado}")
        except Exception as e:
            self.logger.error(f"Error mostrando resultado: {str(e)}")
            messagebox.showerror("Error", f"Error al actualizar índice: {str(e)}")
    
    def _configurar_tab_captura(self, parent):
        # Scrollable frame principal con mejor configuración
        main_frame = ct.CTkScrollableFrame(parent, fg_color="#000000", width=800, height=600)
        main_frame.pack(fill="both", expand=True, padx=20, pady=20)
        
        # Título
        ct.CTkLabel(
            main_frame, 
            text="Captura de Cumplimientos", 
            font=("Segoe UI", 18, "bold"), 
            text_color="#00FFAA"
        ).pack(pady=(0, 20))
        
        # Botón para subir capturas pendientes (solo admin y captura) ANTES de los campos
        if self.rol in ["admin", "captura"]:
            self.subir_pendientes_btn = ct.CTkButton(
                main_frame,
                text="Subir capturas pendientes",
                command=self.subir_capturas_offline,
                font=("Segoe UI", 12, "bold"),
                fg_color="#00FFAA",
                text_color="#000000",
                border_width=2,
                border_color="#00FFAA",
                corner_radius=10
            )
            self.subir_pendientes_btn.pack(pady=(0, 10))
            self._actualizar_estado_pendientes()
        
        # Variables
        self.codigo_captura_var = StringVar()
        self.item_captura_var = StringVar()
        self.motivo_captura_var = StringVar(value="Instrucciones de cuidado")
        self.cumple_captura_var = StringVar(value="NO CUMPLE")
        
        # Frame para campos de entrada
        campos_frame = ct.CTkFrame(main_frame, fg_color="#000000")
        campos_frame.pack(fill="x", pady=(0, 20))
        
        # Código de barras
        ct.CTkLabel(
            campos_frame, 
            text="Código de barras:", 
            text_color="#00FFAA", 
            font=("Segoe UI", 13, "bold")
        ).pack(anchor="w", padx=10, pady=(10, 0))
        
        self.codigo_captura_entry = ct.CTkEntry(
            campos_frame, 
            textvariable=self.codigo_captura_var,
            font=("Segoe UI", 13),
            width=400,
            height=36,
            corner_radius=12,
            border_width=2,
            border_color="#00FFAA",
            fg_color="#000000",
            text_color="#00FFAA"
        )
        self.codigo_captura_entry.pack(fill="x", padx=10, pady=(0, 8))
        
        # Evento para buscar automáticamente el item cuando se
        self.codigo_captura_entry.bind("<Return>", lambda e: self._buscar_item_automatico())
        
        # Item
        ct.CTkLabel(
            campos_frame, 
            text="Item:", 
            text_color="#00FFAA", 
            font=("Segoe UI", 13, "bold")
        ).pack(anchor="w", padx=10, pady=(10, 0))
        self.item_captura_entry = ct.CTkEntry(
            campos_frame, 
            textvariable=self.item_captura_var,
            font=("Segoe UI", 13),
            width=400,
            height=36,
            corner_radius=12,
            border_width=2,
            border_color="#00FFAA",
            fg_color="#000000",
            text_color="#00FFAA",
            state="disabled"  # <-- Solo lectura
        )
        self.item_captura_entry.pack(fill="x", padx=10, pady=(0, 8))
        
        # Cumple/No cumple SIEMPRE visible
        ct.CTkLabel(
            campos_frame, 
            text="¿Cumple?", 
            text_color="#00FFAA", 
            font=("Segoe UI", 13, "bold")
        ).pack(anchor="w", padx=10, pady=(10, 0))
        self.cumple_captura_menu = ct.CTkOptionMenu(
            campos_frame,
            variable=self.cumple_captura_var,
            values=["CUMPLE", "NO CUMPLE"],
            fg_color="#000000",
            text_color="#00FFAA",
            font=("Segoe UI", 13),
            width=400,
            height=36
        )
        self.cumple_captura_menu.pack(fill="x", padx=10, pady=(0, 8))

        # Frame para motivo y botón guardar
        motivo_guardar_frame = ct.CTkFrame(campos_frame, fg_color="#000000")
        motivo_guardar_frame.pack(fill="x", pady=(0, 10))

        # Motivo siempre visible, pero desactivado si Cumple es 'CUMPLE'
        motivo_options = [
            "Instrucciones de cuidado",
            "Insumos",
            "Pais de origen",
            "Talla",
            "Importador",
            "Marca"
        ]
        self.motivo_label = ct.CTkLabel(
            motivo_guardar_frame, 
            text="Motivo:", 
            text_color="#00FFAA", 
            font=("Segoe UI", 13, "bold")
        )
        self.motivo_label.pack(anchor="w", padx=10, pady=(10, 0))
        self.motivo_captura_var = StringVar(value=motivo_options[0])
        self.motivo_captura_menu = ct.CTkOptionMenu(
            motivo_guardar_frame,
            variable=self.motivo_captura_var,
            values=motivo_options,
            fg_color="#000000",
            text_color="#00FFAA",
            font=("Segoe UI", 13),
            width=400,
            height=36
        )
        self.motivo_captura_menu.pack(fill="x", padx=10, pady=(0, 8))
        def on_cumple_change(*args):
            if self.cumple_captura_var.get() == "NO CUMPLE":
                self.motivo_captura_menu.configure(state="normal", text_color="#00FFAA")
                self.motivo_label.configure(text_color="#00FFAA")
            else:
                self.motivo_captura_menu.configure(state="disabled", text_color="#888888")
                self.motivo_label.configure(text_color="#888888")
        self.cumple_captura_var.trace_add('write', on_cumple_change)
        on_cumple_change()

        # Botón guardar SIEMPRE al final del frame
        self.guardar_btn = ct.CTkButton(
            motivo_guardar_frame,
            text="Guardar",
            command=self.guardar_captura_offline,
            font=("Segoe UI", 12, "bold"),
            fg_color="#00FFAA",
            text_color="#000000",
            border_width=2,
            border_color="#00FFAA",
            corner_radius=10
        )
        self.guardar_btn.pack(pady=(10, 0))
    
    def guardar_captura_offline(self):
        """Guarda la captura y la inserta/actualiza directamente en la tabla de ítems y en el historial de capturas"""
        codigo = self.codigo_captura_var.get().strip()
        motivo = self.motivo_captura_var.get().strip() if self.cumple_captura_var.get() == "NO CUMPLE" else ""
        cumple = self.cumple_captura_var.get().strip()
        if not codigo or not cumple:
            messagebox.showwarning("Campos vacíos", "Código y cumple son obligatorios")
            return
        # Buscar item_id en codigos_barras
        res = self.codigo_model.db.execute_query(
            "SELECT item_id FROM codigos_barras WHERE codigo_barras = %s", (codigo,))
        if not res:
            messagebox.showerror("Error", "El código no existe en la base de datos. Solo se pueden capturar códigos existentes.")
            return
        item_id = res[0]['item_id']
        # Obtener el nombre del item
        item_res = self.codigo_model.db.execute_query("SELECT item FROM items WHERE id = %s", (item_id,))
        item = item_res[0]['item'] if item_res else ''
        # Actualizar resultado en items
        self.codigo_model.db.execute_query(
            "UPDATE items SET resultado = %s, fecha_actualizacion = NOW() WHERE id = %s",
            (cumple, item_id), fetch=False)
        # Manejo de motivo
        if cumple == "NO CUMPLE":
            self.codigo_model.db.execute_query(
                "INSERT INTO motivos_no_cumplimiento (item_id, motivo) VALUES (%s, %s) ON CONFLICT (item_id) DO UPDATE SET motivo = EXCLUDED.motivo",
                (item_id, motivo), fetch=False)
        else:
            self.codigo_model.db.execute_query(
                "DELETE FROM motivos_no_cumplimiento WHERE item_id = %s", (item_id,), fetch=False)
        # Guardar en historial de capturas
        self.codigo_model.db.execute_query(
            "INSERT INTO capturas (codigo, item, motivo, cumple, usuario, fecha) VALUES (%s, %s, %s, %s, %s, NOW())",
            (codigo, item, motivo, cumple, self.usuario), fetch=False)
        messagebox.showinfo("Éxito", "Captura guardada y actualizada en ítems")
        self.codigo_captura_var.set("")
        self.item_captura_var.set("")
        self.codigo_captura_entry.focus_set()
    
    def subir_capturas_offline(self):
        """Sube las capturas pendientes del archivo local a la base de datos"""
        import os
        ruta = f"capturas_pendientes_{self.usuario}.json"
        if not os.path.exists(ruta):
            messagebox.showinfo("Sin capturas pendientes", "No hay capturas pendientes para subir.")
            return
        try:
            with open(ruta, "r", encoding="utf-8") as f:
                capturas = json.load(f)
            subidas = 0
            for cap in capturas:
                try:
                    if self.captura_model.guardar_captura(cap["codigo"], cap["item"], cap["motivo"], cap["cumple"], cap["usuario"]):
                        subidas += 1
                except Exception as e:
                    self.logger.error(f"Error subiendo captura offline: {str(e)}")
            if subidas > 0:
                os.remove(ruta)
                messagebox.showinfo("Éxito", f"{subidas} capturas subidas correctamente.")
            else:
                messagebox.showwarning("Sin conexión", "No se pudo subir ninguna captura. Intenta de nuevo más tarde.")
        except Exception as e:
            self.logger.error(f"Error leyendo capturas offline: {str(e)}")
            messagebox.showerror("Error", f"Error leyendo capturas pendientes: {str(e)}")
        self._actualizar_estado_pendientes()
    
    def _buscar_item_automatico(self):
        """Busca automáticamente el item cuando se ingresa un código de barras"""
        codigo = self.codigo_captura_var.get().strip()
        
        # Solo buscar si el código tiene al menos 8 caracteres (código de barras mínimo)
        if len(codigo) >= 8:
            # Validar formato del código
            es_valido, _ = Validators.validar_codigo_barras(codigo)
            if es_valido:
                # Limpiar código
                codigo_limpio = Validators.limpiar_codigo_barras(codigo)
                
                # Buscar en hilo separado para no bloquear la interfaz
                threading.Thread(
                    target=self._ejecutar_busqueda_automatica, 
                    args=(codigo_limpio,), 
                    daemon=True
                ).start()
    
    def _ejecutar_busqueda_automatica(self, codigo):
        """Ejecuta la búsqueda automática del item y resultado"""
        try:
            # Buscar item_id y datos del item
            res = self.codigo_model.db.execute_query(
                "SELECT cb.item_id, i.item, i.resultado FROM codigos_barras cb JOIN items i ON cb.item_id = i.id WHERE cb.codigo_barras = %s",
                (codigo,))
            if res:
                item_id = res[0]['item_id']
                item = res[0]['item']
                resultado = res[0]['resultado']
                self.master.after(0, lambda: self.item_captura_var.set(item))
                self.master.after(0, lambda: self.cumple_captura_var.set(resultado))
                # Si el resultado es NO CUMPLE, buscar motivo y mostrarlo
                if resultado == 'NO CUMPLE':
                    motivo = self.codigo_model.db.execute_query(
                        "SELECT motivo FROM motivos_no_cumplimiento WHERE item_id = %s", (item_id,))
                    if motivo and motivo[0].get('motivo'):
                        self.master.after(0, lambda: self.motivo_captura_var.set(motivo[0]['motivo']))
                self.logger.log_user_action(self.usuario, f"Búsqueda automática exitosa: {codigo}")
        except Exception as e:
            self.logger.error(f"Error en búsqueda automática: {str(e)}")
    
    def _actualizar_estado_pendientes(self):
        """Actualiza la visibilidad del botón de subir capturas pendientes"""
        import os
        ruta = f"capturas_pendientes_{self.usuario}.json"
        if hasattr(self, "subir_pendientes_btn"):
            if os.path.exists(ruta):
                try:
                    with open(ruta, "r", encoding="utf-8") as f:
                        capturas = json.load(f)
                    num_capturas = len(capturas)
                    self.subir_pendientes_btn.configure(
                        state="normal", 
                        text=f"Subir capturas pendientes ({num_capturas})"
                    )
                except Exception:
                    self.subir_pendientes_btn.configure(
                        state="normal", 
                        text="Subir capturas pendientes"
                    )
            else:
                self.subir_pendientes_btn.configure(
                    state="disabled", 
                    text="No hay capturas pendientes"
                )

    def _configurar_tab_configuracion(self, parent):
        main_frame = ct.CTkFrame(parent, fg_color="#000000")
        main_frame.pack(fill="both", expand=True, padx=40, pady=40)

        ct.CTkLabel(
            main_frame,
            text="Configuración de Archivos CLP",
            font=("Segoe UI", 18, "bold"),
            text_color="#00FFAA"
        ).pack(pady=(0, 20))

        # Variable para mostrar archivos seleccionados
        self.rutas_clp_var = StringVar(value="No hay archivos seleccionados")

        archivos_frame = ct.CTkFrame(main_frame, fg_color="#000000")
        archivos_frame.pack(fill="x", pady=(0, 20))

        ct.CTkLabel(
            archivos_frame,
            text="Archivos CLP seleccionados:",
            text_color="#00FFAA",
            font=("Segoe UI", 14, "bold")
        ).pack(anchor="w", padx=20, pady=(10, 0))

        self.rutas_clp_label = ct.CTkLabel(
            archivos_frame,
            textvariable=self.rutas_clp_var,
            text_color="#55DDFF",
            wraplength=600,
            fg_color="#000000"
        )
        self.rutas_clp_label.pack(anchor="w", padx=20, pady=(0, 5))

        def seleccionar_archivos():
            rutas = filedialog.askopenfilenames(
                filetypes=[("Archivos Excel", "*.xls;*.xlsx"), ("Todos", "*.*")],
                title="Seleccionar uno o varios archivos CLP"
            )
            if rutas:
                self.rutas_clp_var.set("\n".join(rutas))
                self.rutas_clp = rutas
            else:
                self.rutas_clp_var.set("No hay archivos seleccionados")
                self.rutas_clp = []

        ct.CTkButton(
            archivos_frame,
            text="Seleccionar Archivos CLP",
            command=seleccionar_archivos,
            font=("Segoe UI", 13, "bold"),
            fg_color="#000000",
            hover_color="#111111",
            border_width=2,
            border_color="#00FFAA",
            text_color="#00FFAA",
            corner_radius=12,
            width=260,
            height=36
        ).pack(pady=5, padx=20, anchor="w")

        def cargar_archivos_clp():
            if not hasattr(self, "rutas_clp") or not self.rutas_clp:
                messagebox.showerror("Error", "No hay archivos CLP seleccionados.")
                return
            resultado = self.codigo_model.cargar_varios_clp(self.rutas_clp, self.usuario)
            if not isinstance(resultado, dict):
                resultado = {'procesados': 0, 'nuevos_items': 0, 'nuevos_codigos': 0, 'clp_registros': []}
            mensaje = f"Carga completada.\nNuevos items: {resultado.get('nuevos_items', 0)}\nNuevos códigos: {resultado.get('nuevos_codigos', 0)}\nTotal procesados: {resultado.get('procesados', 0)}"
            messagebox.showinfo("Éxito", mensaje)
            self.rutas_clp_var.set("No hay archivos seleccionados")
            self.rutas_clp = []
            self.cargar_estadisticas()

        ct.CTkButton(
            archivos_frame,
            text="Cargar Archivos CLP",
            command=cargar_archivos_clp,
            font=("Segoe UI", 13, "bold"),
            fg_color="#00FFAA",
            text_color="#000000",
            border_width=2,
            border_color="#00FFAA",
            corner_radius=12,
            width=260,
            height=36
        ).pack(pady=5, padx=20, anchor="w")

if __name__ == "__main__":
    app = EscanerApp()
    app.ejecutar()    
