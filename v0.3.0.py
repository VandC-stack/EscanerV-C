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

# Configuración de la aplicación
ct.set_appearance_mode("dark")
ct.set_default_color_theme("dark-blue")

# Constantes de versión
VERSION_ACTUAL = "0.3.0"
FECHA_COMPILACION = "2025-01-28"

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

class EscanerApp:
    def __init__(self):
        self.root = ct.CTk()
        self.root.title("Escáner V&C v3.0.0")
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
            if hasattr(self, 'login_button') and self.login_button.winfo_exists():
                self.login_button.configure(state="normal", text="Entrar")
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
            # Usuarios
            tablas_tabview.add("Usuarios")
            self._crear_lista_usuarios(tablas_tabview.tab("Usuarios"), side="top")
            # Codigos_items
            tablas_tabview.add("Codigos_items")
            self.codigos_items_tab = tablas_tabview.tab("Codigos_items")
            self._mostrar_tabla_sql(self.codigos_items_tab, "codigos_items")
            # Capturas
            tablas_tabview.add("Capturas")
            if self.rol == "superadmin":
                self._configurar_tab_revision_capturas(tablas_tabview.tab("Capturas"))
            else:
                self._configurar_tab_captura(tablas_tabview.tab("Capturas"))
            # Refrescar codigos_items y usuarios al cambiar de pestaña
            def on_tab_change():
                current_tab = tablas_tabview.get()
                if current_tab == "Codigos_items":
                    self._mostrar_tabla_sql(self.codigos_items_tab, "codigos_items")
                elif current_tab == "Usuarios":
                    # Refrescar la tabla de usuarios
                    for widget in tablas_tabview.tab("Usuarios").winfo_children():
                        widget.destroy()
                    self._crear_lista_usuarios(tablas_tabview.tab("Usuarios"), side="top")
            try:
                tablas_tabview.configure(command=on_tab_change)
            except Exception:
                pass
        except Exception as e:
            try:
                if hasattr(self, 'logger') and self.logger:
                    self.logger.error(f"Error configurando tab base de datos: {str(e)}")
                else:
                    print(f"Error configurando tab base de datos: {str(e)}")
            except:
                print(f"Error configurando tab base de datos: {str(e)}")
            raise e
    
    def _configurar_tab_revision_capturas(self, parent):
        from tkinter import ttk, messagebox
        from models.captura import Captura
        # Scrollable frame para la tabla y los botones
        scroll_frame = ct.CTkScrollableFrame(parent, fg_color="#000000", width=900, height=500)
        scroll_frame.pack(fill="both", expand=True, padx=20, pady=(20, 0))
        ct.CTkLabel(
            scroll_frame,
            text="Revisión de Capturas",
            font=("Segoe UI", 18, "bold"),
            text_color="#00FFAA"
        ).pack(pady=(0, 20))
        captura_model = Captura(self.db_manager)
        capturas = captura_model.obtener_todas_capturas()
        if not capturas:
            ct.CTkLabel(
                scroll_frame,
                text="No hay capturas registradas.",
                text_color="#00FFAA",
                font=("Segoe UI", 14, "bold")
            ).pack(pady=20)
            return
        columns = list(capturas[0].keys())
        style = ttk.Style()
        style.theme_use('default')
        style.configure("Treeview",
                        background="#000000",
                        foreground="#00FFAA",
                        rowheight=24,
                        fieldbackground="#000000",
                        font=("Segoe UI", 10))
        style.configure("Treeview.Heading",
                        background="#111111",
                        foreground="#00FFAA",
                        font=("Segoe UI", 11, "bold"))
        style.map('Treeview', background=[('selected', '#222222')])
        tree = ttk.Treeview(scroll_frame, columns=columns, show="headings", height=16, style="Treeview", selectmode="extended")
        for col in columns:
            tree.heading(col, text=col)
            tree.column(col, width=120, anchor="center")
        for row in capturas:
            tree.insert("", "end", values=[row[col] for col in columns])
        tree.pack(fill="both", expand=True, padx=10, pady=10)
        ct.CTkLabel(scroll_frame, text="Usa Ctrl o Shift para seleccionar varias capturas.", text_color="#55DDFF").pack(pady=(0, 8))
        btns_frame = ct.CTkFrame(scroll_frame, fg_color="#000000")
        btns_frame.pack(pady=10)
        def refrescar_codigos_items_tabla():
            # Busca el tabview de la base de datos y refresca la tabla codigos_items
            try:
                # Busca el frame principal de la base de datos
                for widget in parent.master.winfo_children():
                    if isinstance(widget, ct.CTkTabview):
                        tabview = widget
                        if "Codigos_items" in tabview._tabs:
                            codigos_tab = tabview.tab("Codigos_items")
                            self._mostrar_tabla_sql(codigos_tab, "codigos_items")
            except Exception as e:
                print(f"Error refrescando codigos_items: {e}")
        def aceptar():
            seleccion = tree.selection()
            if not seleccion:
                messagebox.showwarning("Sin selección", "Selecciona al menos una captura para aceptar.")
                return
            ids = [tree.item(item)['values'][0] for item in seleccion]
            resultado = captura_model.mover_capturas_a_historico(ids)
            for item in seleccion:
                tree.delete(item)
            messagebox.showinfo("Éxito", f"Capturas aceptadas y movidas a codigos_items. Procesadas: {resultado['procesados']}, Actualizadas: {resultado['actualizados']}")
            refrescar_codigos_items_tabla()  # Refresca automáticamente la tabla codigos_items
        def denegar():
            seleccion = tree.selection()
            if not seleccion:
                messagebox.showwarning("Sin selección", "Selecciona al menos una captura para denegar.")
                return
            ids = [tree.item(item)['values'][0] for item in seleccion]
            for id_captura in ids:
                self.db_manager.execute_query("DELETE FROM capturas WHERE id = %s", (id_captura,), fetch=False)
            for item in seleccion:
                tree.delete(item)
            messagebox.showinfo("Éxito", "Capturas denegadas y eliminadas correctamente.")
        aceptar_btn = ct.CTkButton(
            btns_frame,
            text="Aceptar Captura(s)",
            command=aceptar,
            fg_color="#00FFAA",
            text_color="#000000",
            font=("Segoe UI", 12, "bold"),
            border_width=2,
            border_color="#00FFAA",
            corner_radius=10
        )
        aceptar_btn.pack(side="left", padx=10)
        denegar_btn = ct.CTkButton(
            btns_frame,
            text="Denegar Captura(s)",
            command=denegar,
            fg_color="#FF3333",
            text_color="#FFFFFF",
            font=("Segoe UI", 12, "bold"),
            border_width=2,
            border_color="#FF3333",
            corner_radius=10
        )
        denegar_btn.pack(side="left", padx=10)
    
    def _mostrar_tabla_sql(self, parent, nombre_tabla):
        from tkinter import ttk
        # Limpiar widgets previos
        for widget in parent.winfo_children():
            widget.destroy()
        # Buscador
        search_var = None
        if nombre_tabla == "codigos_items":
            search_frame = ct.CTkFrame(parent, fg_color="#000000")
            search_frame.pack(fill="x", padx=10, pady=(10, 0))
            search_var = ct.StringVar()
            ct.CTkLabel(search_frame, text="Buscar por código de barras o item:", text_color="#00FFAA").pack(side="left", padx=(0, 8))
            search_entry = ct.CTkEntry(search_frame, textvariable=search_var, width=200)
            search_entry.pack(side="left")
        # Obtener datos de la tabla
        try:
            datos = self.db_manager.execute_query(f"SELECT * FROM {nombre_tabla}")
        except Exception as e:
            label = ct.CTkLabel(
                parent,
                text=f"Error al obtener datos: {str(e)}",
                text_color="#FF3333",
                font=("Segoe UI", 14, "bold")
            )
            label.pack(pady=20)
            return
        if not datos:
            label = ct.CTkLabel(
                parent,
                text=f"No hay datos en la tabla '{nombre_tabla}'.",
                text_color="#00FFAA",
                font=("Segoe UI", 14, "bold")
            )
            label.pack(pady=20)
            return
        columns = list(datos[0].keys())
        style = ttk.Style()
        style.theme_use('default')
        style.configure("Treeview",
                        background="#000000",
                        foreground="#00FFAA",
                        rowheight=24,
                        fieldbackground="#000000",
                        font=("Segoe UI", 10))
        style.configure("Treeview.Heading",
                        background="#111111",
                        foreground="#00FFAA",
                        font=("Segoe UI", 11, "bold"))
        style.map('Treeview', background=[('selected', '#222222')])
        tree = ttk.Treeview(parent, columns=columns, show="headings", height=16, style="Treeview")
        for col in columns:
            tree.heading(col, text=col)
            tree.column(col, width=120, anchor="center")
        # Guardar referencia a los datos originales para el filtro
        self._codigos_items_data = datos if nombre_tabla == "codigos_items" else None
        for row in datos:
            tree.insert("", "end", values=[row[col] for col in columns])
        tree.pack(fill="both", expand=True, padx=10, pady=10)
        # Lógica de búsqueda para codigos_items
        if nombre_tabla == "codigos_items" and search_var is not None:
            def filtrar(*args):
                filtro = search_var.get().strip().lower()
                # Limpiar la tabla
                for item in tree.get_children():
                    tree.delete(item)
                # Volver a insertar los datos filtrados
                for row in self._codigos_items_data:
                    codigo = str(row.get('codigo_barras', '')).lower()
                    item_val = str(row.get('item', '')).lower()
                    if not filtro or filtro in codigo or filtro in item_val:
                        tree.insert("", "end", values=[row[col] for col in columns])
            search_var.trace_add('write', filtrar)
    
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
            hover_color="#111111",
            border_width=2,
            border_color="#00FFAA",
            text_color="#00FFAA",
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
        # NOM oculta por el momento porque me da flojera revisar la logica
        self.nom_valor = ct.CTkLabel(
            parent, 
            text="NOM: ", 
            font=("Segoe UI", 12, "italic"), 
            text_color="#000000", 
            fg_color="#000000", 
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
            text="Con resultado: 0", 
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
        
        # Botón actualizar
        self.update_button = ct.CTkButton(
            parent,
            text="Actualizar Índice",
            font=("Segoe UI", 12, "bold"),
            fg_color="#000000",
            hover_color="#111111",
            border_width=2,
            border_color="#00FFAA",
            text_color="#00FFAA",
            corner_radius=12,
            width=200,
            height=32,
            command=self.actualizar_indice
        )
        self.update_button.pack(pady=(0, 18))
    
    def buscar_codigo(self):
        """Busca un código de barras"""
        codigo = self.codigo_var.get().strip()
        
        # Validar entrada
        es_valido, mensaje = Validators.validar_codigo_barras(codigo)
        if not es_valido:
            self.resultado_valor.configure(text=mensaje)
            self.clave_valor.configure(text="")
            self.codigo_var.set("")
            self.codigo_entry.focus_set()
            return
        
        # Limpiar código
        codigo_limpio = Validators.limpiar_codigo_barras(codigo)
        
        # Deshabilitar botón durante búsqueda
        self.search_button.configure(state="disabled", text="Buscando...")
        
        # Ejecutar búsqueda en hilo separado
        threading.Thread(target=self._ejecutar_busqueda, args=(codigo_limpio,), daemon=True).start()
    
    def _ejecutar_busqueda(self, codigo):
        """Ejecuta la búsqueda en la base de datos"""
        try:
            resultado = self.codigo_model.buscar_codigo(codigo)
            if resultado:
                # Mostrar item y resultado
                self.master.after(0, lambda: self._mostrar_resultado(resultado))
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
        self.resultado_valor.configure(text=f"RESULTADO: {resultado.get('resultado', 'Sin resultado') or 'Sin resultado'}")
        self.nom_valor.configure(text=f"Última actualización: {resultado.get('fecha_actualizacion', '')}")
    
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
        self.search_button.configure(text="Buscar", state="normal")
        self.codigo_var.set("")
        self.codigo_entry.focus_set()
    
    def cargar_estadisticas(self):
        """Carga las estadísticas de la base de datos"""
        try:
            stats = self.codigo_model.obtener_estadisticas()
            if isinstance(stats, dict):
                self.total_codigos_label.configure(text=f"Total de códigos: {stats.get('total_codigos', 0)}")
                self.con_resultado_label.configure(text=f"Con resultado: {stats.get('con_resultado', 0)}")
                self.sin_resultado_label.configure(text=f"Sin resultado: {stats.get('sin_resultado', 0)}")
                self.ultima_actualizacion_label.configure(text=f"Última actualización: {stats.get('ultima_actualizacion', 'Nunca')}")
            else:
                self.total_codigos_label.configure(text="Total de códigos: 0")
                self.con_resultado_label.configure(text="Con resultado: 0")
                self.sin_resultado_label.configure(text="Sin resultado: 0")
                self.ultima_actualizacion_label.configure(text="Última actualización: Nunca")
        except Exception as e:
            self.logger.error(f"Error cargando estadísticas: {str(e)}")
            self.total_codigos_label.configure(text="Total de códigos: 0")
            self.con_resultado_label.configure(text="Con resultado: 0")
            self.sin_resultado_label.configure(text="Sin resultado: 0")
            self.ultima_actualizacion_label.configure(text="Última actualización: Nunca")
    
    def actualizar_indice(self):
        """Actualiza el índice desde archivos Excel"""
        # Verificar configuración
        es_valido, mensaje = Validators.validar_configuracion_completa(self.config_data)
        if not es_valido:
            messagebox.showerror("Error", mensaje)
            return
        
        # Ejecutar actualización en hilo separado
        threading.Thread(target=self._ejecutar_actualizacion, daemon=True).start()
    
    def _ejecutar_actualizacion(self):
        """Ejecuta la actualización del índice"""
        try:
            self.master.after(0, lambda: self.update_button.configure(state="disabled", text="Actualizando..."))
            # Usar cargar_clp directamente
            resultado = self.codigo_model.cargar_clp(self.config_data['contenedor'])
            if not isinstance(resultado, dict):
                resultado = {'nuevos_registros': 0, 'total_codigos': 0, 'total_procesados': 0}
            self.master.after(0, lambda: self._mostrar_resultado_actualizacion(resultado))
            self.logger.log_user_action(self.usuario, "Índice actualizado", f"Registros: {resultado.get('total_procesados', 0)}")
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
                mensaje += f"Nuevos registros: {resultado.get('nuevos_registros', 0)}\n"
                mensaje += f"Total de códigos: {resultado.get('total_codigos', 0)}\n"
                mensaje += f"Total procesados: {resultado.get('total_procesados', 0)}\n"
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
        
        # Evento para buscar automáticamente el item cuando se ingresa un código
        self.codigo_captura_var.trace_add('write', self._buscar_item_automatico)
        
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
            text_color="#00FFAA"
        )
        self.item_captura_entry.pack(fill="x", padx=10, pady=(0, 8))
        
        # Cumple/No cumple
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
        
        # Motivo solo si NO CUMPLE (movido al campos_frame)
        motivo_options = [
            "Instrucciones de cuidado",
            "Insumos",
            "Pais de origen",
            "Talla",
            "Importador",
            "Marca"
        ]
        
        # Label para motivo
        self.motivo_label = ct.CTkLabel(
            campos_frame, 
            text="Motivo:", 
            text_color="#00FFAA", 
            font=("Segoe UI", 13, "bold")
        )
        
        self.motivo_captura_menu = ct.CTkOptionMenu(
            campos_frame,
            variable=self.motivo_captura_var,
            values=motivo_options,
            fg_color="#000000",
            text_color="#00FFAA",
            font=("Segoe UI", 13),
            width=400,
            height=36
        )
        
        # Mostrar/ocultar motivo según selección de cumple
        def on_cumple_change(*args):
            if self.cumple_captura_var.get() == "NO CUMPLE":
                self.motivo_label.pack(anchor="w", padx=10, pady=(10, 0))
                self.motivo_captura_menu.pack(fill="x", padx=10, pady=(0, 8))
            else:
                self.motivo_label.pack_forget()
                self.motivo_captura_menu.pack_forget()
        
        self.cumple_captura_var.trace_add('write', on_cumple_change)
        on_cumple_change()
        
        # Estado label
        self.estado_captura_label = ct.CTkLabel(
            campos_frame, 
            text="", 
            text_color="#FF3333", 
            font=("Segoe UI", 11, "bold")
        )
        self.estado_captura_label.pack(pady=(4, 8))
        
        # Estadísticas de capturas
        self._crear_estadisticas_captura(main_frame)
        
        # Botones de acción centrados justo después de los campos
        botones_captura_frame = ct.CTkFrame(main_frame, fg_color="#000000")
        botones_captura_frame.pack(anchor="center", pady=20)
        
        self.guardar_captura_btn = ct.CTkButton(
            botones_captura_frame, 
            text="Guardar Captura", 
            command=self.guardar_captura,
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
        self.guardar_captura_btn.pack(side="left", padx=(0, 10), pady=0)
        
        self.descargar_captura_btn = ct.CTkButton(
            botones_captura_frame, 
            text="Descargar Datos", 
            command=self.descargar_capturas,
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
        self.descargar_captura_btn.pack(side="left", padx=(0, 10), pady=0)
        
        if self.rol == "admin":
            self.procesar_historico_btn = ct.CTkButton(
                botones_captura_frame,
                text="Procesar Histórico",
                command=self.procesar_historico,
                font=("Segoe UI", 14, "bold"),
                fg_color="#000000",
                hover_color="#111111",
                border_width=2,
                border_color="#FFAA00",
                text_color="#FFAA00",
                corner_radius=12,
                width=200,
                height=36
            )
            self.procesar_historico_btn.pack(side="left", padx=(0, 10), pady=0)
            
            self.borrar_capturas_btn = ct.CTkButton(
                botones_captura_frame,
                text="Borrar Datos",
                command=self.borrar_capturas,
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
            self.borrar_capturas_btn.pack(side="left", padx=(0, 10), pady=0)
        
        # Botón para subir capturas pendientes (solo admin y captura)
        if self.rol in ["admin", "captura"]:
            self.subir_pendientes_btn = ct.CTkButton(
                parent,
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
    
    def _crear_estadisticas_captura(self, parent):
        """Crea las estadísticas de capturas"""
        stats_frame = ct.CTkFrame(parent, fg_color="#000000")
        stats_frame.pack(fill="x", pady=(20, 0))
        
        ct.CTkLabel(
            stats_frame,
            text="Estadísticas de Capturas",
            font=("Segoe UI", 14, "bold"),
            text_color="#00FFAA"
        ).pack(pady=(10, 5))
        
        # Labels de estadísticas
        self.total_capturas_label = ct.CTkLabel(
            stats_frame,
            text="Total de capturas: 0",
            font=("Segoe UI", 11),
            text_color="#00FFAA"
        )
        self.total_capturas_label.pack(pady=2)
        
        self.cumple_capturas_label = ct.CTkLabel(
            stats_frame,
            text="Cumple: 0",
            font=("Segoe UI", 11),
            text_color="#00FFAA"
        )
        self.cumple_capturas_label.pack(pady=2)
        
        self.no_cumple_capturas_label = ct.CTkLabel(
            stats_frame,
            text="No cumple: 0",
            font=("Segoe UI", 11),
            text_color="#00FFAA"
        )
        self.no_cumple_capturas_label.pack(pady=2)
        
        # Cargar estadísticas iniciales
        self.cargar_estadisticas_captura()
    
    def guardar_captura(self):
        """Guarda una nueva captura"""
        # Obtener valores
        codigo = self.codigo_captura_var.get().strip()
        item = self.item_captura_var.get().strip()
        motivo = self.motivo_captura_var.get().strip()
        cumple = self.cumple_captura_var.get().strip()
        
        # Validar campos
        if not codigo or not item or not cumple:
            self.estado_captura_label.configure(
                text="Todos los campos son obligatorios.",
                text_color="#FF3333"
            )
            return
        
        # Validar código de barras
        es_valido_codigo, mensaje_codigo = Validators.validar_codigo_barras(codigo)
        if not es_valido_codigo:
            self.estado_captura_label.configure(text=mensaje_codigo, text_color="#FF3333")
            return
        
        # Validar item
        es_valido_item, mensaje_item = Validators.validar_item_code(item)
        if not es_valido_item:
            self.estado_captura_label.configure(text=mensaje_item, text_color="#FF3333")
            return
        
        # Validar motivo solo si NO CUMPLE
        if cumple == "NO CUMPLE":
            if not motivo:
                self.estado_captura_label.configure(
                    text="El motivo es obligatorio si el resultado es NO CUMPLE.",
                    text_color="#FF3333"
                )
                return
        
        # Limpiar códigos
        codigo_limpio = Validators.limpiar_codigo_barras(codigo)
        item_limpio = Validators.limpiar_item_code(item)
        
        # Deshabilitar botón durante guardado
        self.guardar_captura_btn.configure(state="disabled", text="Guardando...")
        
        # Ejecutar guardado en hilo separado
        threading.Thread(
            target=self._ejecutar_guardar_captura, 
            args=(codigo_limpio, item_limpio, motivo, cumple), 
            daemon=True
        ).start()
    
    def _ejecutar_guardar_captura(self, codigo, item, motivo, cumple):
        """Ejecuta el guardado de la captura"""
        try:
            # Guardar captura
            if self.captura_model.guardar_captura(codigo, item, motivo, cumple, self.usuario):
                self.master.after(0, lambda: self._mostrar_exito_captura())
                self.logger.log_user_action(self.usuario, f"Captura guardada: {codigo}")
            else:
                self.master.after(0, lambda: self._mostrar_error_captura("Captura duplicada o error al guardar"))
        except Exception as e:
            self.logger.error(f"Error guardando captura: {str(e)}")
            # Persistencia offline si es admin o captura
            if self.rol in ["admin", "captura"]:
                self._guardar_captura_offline(codigo, item, motivo, cumple)
                self.master.after(0, lambda: self._mostrar_error_captura("Sin conexión. Captura guardada localmente. Sube tus capturas pendientes cuando tengas internet."))
                self.master.after(0, self._actualizar_estado_pendientes)
            else:
                self.master.after(0, lambda: self._mostrar_error_captura(str(e)))
        finally:
            self.master.after(0, lambda: self._restaurar_boton_captura())
    
    def _mostrar_exito_captura(self):
        """Muestra mensaje de éxito en captura"""
        self.estado_captura_label.configure(
            text="¡Captura guardada exitosamente!",
            text_color="#00FFAA"
        )
        # Limpiar campos
        self.codigo_captura_var.set("")
        self.item_captura_var.set("")
        self.codigo_captura_entry.focus_set()
        # Actualizar estadísticas
        self.cargar_estadisticas_captura()
    
    def _mostrar_error_captura(self, error):
        """Muestra error en captura"""
        self.estado_captura_label.configure(
            text=f"Error: {error}",
            text_color="#FF3333"
        )
    
    def _restaurar_boton_captura(self):
        """Restaura el botón de captura"""
        self.guardar_captura_btn.configure(state="normal", text="Guardar Captura")
    
    def descargar_capturas(self):
        """Descarga las capturas a un archivo Excel"""
        try:
            # Solicitar ubicación de guardado
            ruta_guardado = filedialog.asksaveasfilename(
                defaultextension=".xlsx",
                filetypes=[("Archivos Excel", "*.xlsx")],
                title="Guardar Capturas",
                initialfile=f"Capturas_{datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx"
            )
            
            if ruta_guardado:
                # Ejecutar descarga en hilo separado
                threading.Thread(
                    target=self._ejecutar_descarga_capturas,
                    args=(ruta_guardado,),
                    daemon=True
                ).start()
            else:
                self.estado_captura_label.configure(
                    text="Descarga cancelada.",
                    text_color="#FF3333"
                )
                
        except Exception as e:
            self.logger.error(f"Error iniciando descarga: {str(e)}")
            self.estado_captura_label.configure(
                text=f"Error al iniciar descarga: {str(e)}",
                text_color="#FF3333"
            )
    
    def _ejecutar_descarga_capturas(self, ruta):
        """Ejecuta la descarga de capturas"""
        try:
            self.master.after(0, lambda: self.descargar_captura_btn.configure(state="disabled", text="Descargando..."))
            
            # Descargar capturas del usuario actual
            if self.captura_model.exportar_capturas_excel(ruta, self.usuario):
                self.master.after(0, lambda: self._mostrar_exito_descarga(ruta))
                self.logger.log_user_action(self.usuario, f"Capturas descargadas: {ruta}")
            else:
                self.master.after(0, lambda: self._mostrar_error_descarga("No hay datos para descargar"))
                
        except Exception as e:
            self.logger.error(f"Error descargando capturas: {str(e)}")
            self.master.after(0, lambda: self._mostrar_error_descarga(str(e)))
        finally:
            self.master.after(0, lambda: self.descargar_captura_btn.configure(state="normal", text="Descargar Datos"))
    
    def _mostrar_exito_descarga(self, ruta):
        """Muestra éxito en descarga"""
        self.estado_captura_label.configure(
            text=f"¡Capturas descargadas exitosamente!\n{ruta}",
            text_color="#00FFAA"
        )
    
    def _mostrar_error_descarga(self, error):
        """Muestra error en descarga"""
        self.estado_captura_label.configure(
            text=f"Error al descargar: {error}",
            text_color="#FF3333"
        )
    
    def procesar_historico(self):
        """Procesa el histórico de capturas"""
        if self.rol != "admin":
            return
        
        respuesta = messagebox.askyesno(
            "Confirmar",
            "¿Desea procesar el histórico de capturas?\nEsto actualizará los resultados en la base de datos."
        )
        
        if respuesta:
            # Ejecutar procesamiento en hilo separado
            threading.Thread(target=self._ejecutar_procesar_historico, daemon=True).start()
    
    def _ejecutar_procesar_historico(self):
        """Ejecuta el procesamiento del histórico"""
        try:
            self.master.after(0, lambda: self.procesar_historico_btn.configure(state="disabled", text="Procesando..."))
            
            resultado = self.captura_model.procesar_historico()
            
            self.master.after(0, lambda: self._mostrar_resultado_historico(resultado))
            self.logger.log_user_action(self.usuario, "Histórico procesado", f"Procesados: {resultado['procesados']}")
            
        except Exception as e:
            self.logger.error(f"Error procesando histórico: {str(e)}")
            self.master.after(0, lambda: messagebox.showerror("Error", f"Error al procesar histórico: {str(e)}"))
        finally:
            self.master.after(0, lambda: self.procesar_historico_btn.configure(state="normal", text="Procesar Histórico"))
    
    def _mostrar_resultado_historico(self, resultado):
        """Muestra el resultado del procesamiento del histórico"""
        mensaje = (
            f"Histórico procesado exitosamente.\n\n"
            f"Registros procesados: {resultado['procesados']}\n"
            f"Resultados actualizados: {resultado['actualizados']}"
        )
        messagebox.showinfo("Éxito", mensaje)
    
    def borrar_capturas(self):
        """Borra la última captura del usuario actual (solo admin)"""
        if self.rol != "admin":
            return
        respuesta = messagebox.askyesno(
            "Confirmar Borrado",
            "¿Está seguro de que desea borrar la ÚLTIMA captura que realizó?\nEsta acción no se puede deshacer."
        )
        if respuesta:
            try:
                # Obtener la última captura del usuario actual
                ultima = self.captura_model.obtener_ultima_captura_usuario(self.usuario)
                if ultima:
                    self.captura_model.eliminar_captura_por_id(ultima['id'])
                    messagebox.showinfo("Éxito", "La última captura ha sido borrada.")
                    self.logger.log_user_action(self.usuario, "Última captura borrada")
                    self.cargar_estadisticas_captura()
                else:
                    messagebox.showerror("Error", "No hay capturas para borrar.")
            except Exception as e:
                self.logger.error(f"Error borrando última captura: {str(e)}")
                messagebox.showerror("Error", f"Error al borrar: {str(e)}")
    
    def cargar_estadisticas_captura(self):
        """Carga las estadísticas de capturas"""
        try:
            stats = self.captura_model.obtener_estadisticas_capturas()
            
            self.total_capturas_label.configure(text=f"Total de capturas: {stats['total_capturas']}")
            self.cumple_capturas_label.configure(text=f"Cumple: {stats['cumple']}")
            self.no_cumple_capturas_label.configure(text=f"No cumple: {stats['no_cumple']}")
            
        except Exception as e:
            self.logger.error(f"Error cargando estadísticas de captura: {str(e)}")
    
    def _configurar_tab_configuracion(self, parent):
        """Configura la pestaña de configuración"""
        # Frame principal
        main_frame = ct.CTkFrame(parent, fg_color="#000000")
        main_frame.pack(fill="both", expand=True, padx=40, pady=40)
        
        # Título
        ct.CTkLabel(
            main_frame, 
            text="Configuración de Archivos", 
            font=("Segoe UI", 18, "bold"), 
            text_color="#00FFAA"
        ).pack(pady=(0, 20))
        
        # Variables de configuración
        self.ruta_contenedor_var = StringVar(value=self.config_data.get("contenedor", ""))
        
        # Frame para archivos
        archivos_frame = ct.CTkFrame(main_frame, fg_color="#000000")
        archivos_frame.pack(fill="x", pady=(0, 20))
        
        # Archivo CLP
        ct.CTkLabel(
            archivos_frame, 
            text="Archivo CLP:", 
            text_color="#00FFAA", 
            font=("Segoe UI", 14, "bold")
        ).pack(anchor="w", padx=20, pady=(10, 0))
        
        self.ruta_contenedor_label = ct.CTkLabel(
            archivos_frame, 
            textvariable=self.ruta_contenedor_var, 
            text_color="#55DDFF", 
            wraplength=600, 
            fg_color="#000000"
        )
        self.ruta_contenedor_label.pack(anchor="w", padx=20, pady=(0, 5))
        
        ct.CTkButton(
            archivos_frame, 
            text="Cargar/Actualizar CLP", 
            command=self.cargar_archivo_contenedor,
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
        
        # Frame para gestión de usuarios (solo superadmin)
        if self.rol == "superadmin":
            self._crear_gestion_usuarios(main_frame)
    
    def _crear_gestion_usuarios(self, parent):
        """Crea la sección de gestión de usuarios"""
        usuarios_frame = ct.CTkFrame(parent, fg_color="#000000")
        usuarios_frame.pack(fill="x", pady=(0, 20))
        
        ct.CTkLabel(
            usuarios_frame, 
            text="Gestión de Usuarios", 
            text_color="#00FFAA", 
            font=("Segoe UI", 14, "bold")
        ).pack(anchor="w", padx=20, pady=(10, 0))
        
        # Botón refrescar base de datos
        self.btn_refrescar_bd = ct.CTkButton(
            usuarios_frame,
            text="Refrescar Base de Datos",
            command=self.refrescar_base_datos,
            fg_color="#00FFAA",
            text_color="#000000",
            font=("Segoe UI", 12, "bold"),
            border_width=2,
            border_color="#00FFAA",
            corner_radius=10
        )
        self.btn_refrescar_bd.pack(anchor="w", padx=20, pady=(0, 10))
        
        # Variables para nuevo usuario
        self.nuevo_usuario_var = StringVar()
        self.nueva_contraseña_var = StringVar()
        self.nuevo_rol_var = StringVar(value="usuario")
        
        # Campos para nuevo usuario
        campos_frame = ct.CTkFrame(usuarios_frame, fg_color="#000000")
        campos_frame.pack(fill="x", padx=20, pady=(10, 0))
        
        # Usuario
        ct.CTkLabel(
            campos_frame, 
            text="Usuario:", 
            text_color="#00FFAA", 
            font=("Segoe UI", 12, "bold")
        ).pack(anchor="w", pady=(5, 0))
        
        self.nuevo_usuario_entry = ct.CTkEntry(
            campos_frame,
            textvariable=self.nuevo_usuario_var,
            font=("Segoe UI", 12),
            width=200,
            height=32,
            corner_radius=8,
            border_width=2,
            border_color="#00FFAA",
            fg_color="#000000",
            text_color="#00FFAA"
        )
        self.nuevo_usuario_entry.pack(anchor="w", pady=(0, 5))
        
        # Contraseña
        ct.CTkLabel(
            campos_frame, 
            text="Contraseña:", 
            text_color="#00FFAA", 
            font=("Segoe UI", 12, "bold")
        ).pack(anchor="w", pady=(5, 0))
        
        self.nueva_contraseña_entry = ct.CTkEntry(
            campos_frame,
            textvariable=self.nueva_contraseña_var,
            show="*",
            font=("Segoe UI", 12),
            width=200,
            height=32,
            corner_radius=8,
            border_width=2,
            border_color="#00FFAA",
            fg_color="#000000",
            text_color="#00FFAA"
        )
        self.nueva_contraseña_entry.pack(anchor="w", pady=(0, 5))
        
        # Rol
        ct.CTkLabel(
            campos_frame, 
            text="Rol:", 
            text_color="#00FFAA", 
            font=("Segoe UI", 12, "bold")
        ).pack(anchor="w", pady=(5, 0))
        
        self.nuevo_rol_menu = ct.CTkOptionMenu(
            campos_frame,
            variable=self.nuevo_rol_var,
            values=["usuario", "captura", "admin"],  # No permitir superadmin
            fg_color="#000000",
            text_color="#00FFAA",
            font=("Segoe UI", 12),
            width=200,
            height=32
        )
        self.nuevo_rol_menu.pack(anchor="w", pady=(0, 10))
        
        # Botón crear usuario
        ct.CTkButton(
            campos_frame,
            text="Crear Usuario",
            command=self.crear_usuario,
            font=("Segoe UI", 12, "bold"),
            fg_color="#000000",
            hover_color="#111111",
            border_width=2,
            border_color="#00FFAA",
            text_color="#00FFAA",
            corner_radius=12,
            width=150,
            height=32
        ).pack(anchor="w", pady=(0, 10))
        
        # Lista de usuarios
        self._crear_lista_usuarios(usuarios_frame)
    
    def _crear_lista_usuarios(self, parent, side="right"):
        from tkinter import ttk, simpledialog, messagebox
        lista_frame = ct.CTkFrame(parent, fg_color="#111111", border_width=2, border_color="#00FFAA")
        lista_frame.pack(side=side, fill="both", expand=True, padx=20, pady=10)
        ct.CTkLabel(
            lista_frame, 
            text="Usuarios Existentes", 
            text_color="#00FFAA", 
            font=("Segoe UI", 14, "bold")
        ).pack(anchor="w", padx=10, pady=(10, 5))
        # Botones superiores alineados a la derecha
        botones_superiores_frame = ct.CTkFrame(lista_frame, fg_color="#111111")
        botones_superiores_frame.pack(fill="x", padx=10, pady=(0, 5))
        self.btn_eliminar_usuario = ct.CTkButton(
            botones_superiores_frame,
            text="Eliminar seleccionado",
            command=self._eliminar_usuario_tabla,
            fg_color="#FF3333",
            text_color="#FFFFFF",
            font=("Segoe UI", 12, "bold"),
            border_width=2,
            border_color="#FF3333",
            corner_radius=10
        )
        self.btn_eliminar_usuario.pack(side="left", padx=(0, 5))
        self.btn_reset_pass = ct.CTkButton(
            botones_superiores_frame,
            text="Restablecer contraseña",
            command=self._restablecer_contrasena_usuario,
            fg_color="#00FFAA",
            text_color="#000000",
            font=("Segoe UI", 12, "bold"),
            border_width=2,
            border_color="#00FFAA",
            corner_radius=10
        )
        self.btn_reset_pass.pack(side="right", padx=(0, 5))
        # Botón refrescar base de datos solo para superadmin
        if self.rol == "superadmin":
            self.btn_refrescar_bd = ct.CTkButton(
                botones_superiores_frame,
                text="Refrescar Base de Datos",
                command=self.refrescar_base_datos,
                fg_color="#00FFAA",
                text_color="#000000",
                font=("Segoe UI", 12, "bold"),
                border_width=2,
                border_color="#00FFAA",
                corner_radius=10
            )
            self.btn_refrescar_bd.pack(side="right", padx=(0, 5))
        # Tabla visual con fondo y bordes customtkinter
        self.usuarios_table_frame = ct.CTkFrame(lista_frame, fg_color="#000000", border_width=2, border_color="#00FFAA")
        self.usuarios_table_frame.pack(fill="both", expand=True, padx=10, pady=10)
        self._refresh_usuarios_table()
    
    def _refresh_usuarios_table(self):
        from tkinter import ttk
        for widget in self.usuarios_table_frame.winfo_children():
            widget.destroy()
        columns = ["id", "usuario", "rol", "activo", "fecha_creacion"]
        style = ttk.Style()
        style.theme_use('default')
        style.configure("Treeview",
                        background="#000000",
                        foreground="#00FFAA",
                        rowheight=28,
                        fieldbackground="#000000",
                        font=("Segoe UI", 11))
        style.configure("Treeview.Heading",
                        background="#111111",
                        foreground="#00FFAA",
                        font=("Segoe UI", 12, "bold"))
        # Cambiar color de selección a un verde brillante
        style.map('Treeview',
                  background=[('selected', '#00FFAA')],
                  foreground=[('selected', '#000000')])
        tree = ttk.Treeview(self.usuarios_table_frame, columns=columns, show="headings", height=16, style="Treeview", selectmode="browse")
        for col in columns:
            tree.heading(col, text=col)
            tree.column(col, width=120, anchor="center")
        usuarios = self.usuario_model.obtener_usuarios()
        for user in usuarios:
            row = [user.get("id", ""), user.get("usuario", ""), user.get("rol", ""), user.get("activo", ""), user.get("fecha_creacion", "")]
            tree.insert("", "end", values=row)
        tree.pack(fill="both", expand=True)
        tree.update_idletasks()  # Fuerza el render completo del widget
        tree.focus_set()         # Da foco al widget
        if tree.get_children():
            tree.selection_set(tree.get_children()[0])  # Selecciona automáticamente la primera fila
        # Forzar selección de fila al hacer clic
        def on_click(event):
            item = tree.identify_row(event.y)
            if item:
                tree.selection_set(item)
        tree.bind('<ButtonRelease-1>', on_click)
        self.usuarios_tree = tree
    
    def _toggle_contrasena_columna(self):
        self.mostrar_contrasenas = not self.mostrar_contrasenas
        if self.mostrar_contrasenas:
            self.btn_toggle_contrasena.configure(text="Ocultar contraseñas")
        else:
            self.btn_toggle_contrasena.configure(text="Mostrar contraseñas")
        self._refresh_usuarios_table()
    
    def _get_usuarios_tree(self):
        # Devuelve la referencia actual al Treeview de usuarios
        from tkinter import ttk
        for widget in self.usuarios_table_frame.winfo_children():
            if isinstance(widget, ttk.Treeview):
                return widget
        return None

    def _eliminar_usuario_tabla(self):
        tree = self._get_usuarios_tree()
        if not tree:
            return
        sel = tree.selection()
        if not sel:
            return
        for item in sel:
            pk_val = tree.item(item)['values'][0]
            self.db_manager.delete_one("usuarios", {"id": pk_val})
            tree.delete(item)
    
    def _crear_formulario_usuario(self, parent, side="right"):
        form_frame = ct.CTkFrame(parent, fg_color="#111111", border_width=2, border_color="#00FFAA")
        form_frame.pack(side=side, fill="y", expand=True, padx=20, pady=10)
        ct.CTkLabel(
            form_frame, 
            text="Gestión de Usuarios", 
            text_color="#00FFAA", 
            font=("Segoe UI", 14, "bold")
        ).pack(anchor="w", pady=(10, 0))
        self.nuevo_usuario_var = StringVar()
        self.nueva_contraseña_var = StringVar()
        self.nuevo_rol_var = StringVar(value="usuario")
        ct.CTkLabel(
            form_frame, 
            text="Usuario:", 
            text_color="#00FFAA", 
            font=("Segoe UI", 12, "bold")
        ).pack(anchor="w", pady=(5, 0))
        self.nuevo_usuario_entry = ct.CTkEntry(
            form_frame,
            textvariable=self.nuevo_usuario_var,
            font=("Segoe UI", 12),
            width=200,
            height=32,
            corner_radius=8,
            border_width=2,
            border_color="#00FFAA",
            fg_color="#000000",
            text_color="#00FFAA"
        )
        self.nuevo_usuario_entry.pack(anchor="w", pady=(0, 5))
        ct.CTkLabel(
            form_frame, 
            text="Contraseña:", 
            text_color="#00FFAA", 
            font=("Segoe UI", 12, "bold")
        ).pack(anchor="w", pady=(5, 0))
        self.nueva_contraseña_entry = ct.CTkEntry(
            form_frame,
            textvariable=self.nueva_contraseña_var,
            show="*",
            font=("Segoe UI", 12),
            width=200,
            height=32,
            corner_radius=8,
            border_width=2,
            border_color="#00FFAA",
            fg_color="#000000",
            text_color="#00FFAA"
        )
        self.nueva_contraseña_entry.pack(anchor="w", pady=(0, 5))
        ct.CTkLabel(
            form_frame, 
            text="Rol:", 
            text_color="#00FFAA", 
            font=("Segoe UI", 12, "bold")
        ).pack(anchor="w", pady=(5, 0))
        self.nuevo_rol_menu = ct.CTkOptionMenu(
            form_frame,
            variable=self.nuevo_rol_var,
            values=["usuario", "captura", "admin"],
            fg_color="#000000",
            text_color="#00FFAA",
            font=("Segoe UI", 12),
            width=200,
            height=32
        )
        self.nuevo_rol_menu.pack(anchor="w", pady=(0, 10))
        ct.CTkButton(
            form_frame,
            text="Crear Usuario",
            command=self.crear_usuario,
            font=("Segoe UI", 12, "bold"),
            fg_color="#000000",
            hover_color="#111111",
            border_width=2,
            border_color="#00FFAA",
            text_color="#00FFAA",
            corner_radius=12,
            width=150,
            height=32
        ).pack(anchor="w", pady=(0, 10))
    
    def cargar_archivo_contenedor(self):
        """Carga el archivo de contenedor"""
        ruta = filedialog.askopenfilename(
            filetypes=[("Archivos Excel", "*.xls;*.xlsx"), ("Todos", "*.*")],
            title="Seleccionar Archivo Contenedor (CLP)"
        )
        if ruta:
            # Validar archivo
            es_valido, mensaje = Validators.validar_archivo_excel(ruta)
            if es_valido:
                self.config_data["contenedor"] = ruta
                self.ruta_contenedor_var.set(ruta)
                self.guardar_configuracion()
                messagebox.showinfo("Éxito", "Archivo contenedor cargado correctamente")
            else:
                messagebox.showerror("Error", f"Archivo inválido: {mensaje}")
    
    def cargar_archivo_modelos(self):
        """Carga el archivo de modelos (histórico)"""
        ruta = filedialog.askopenfilename(
            filetypes=[("Archivos Excel", "*.xls;*.xlsx"), ("Todos", "*.*")],
            title="Seleccionar Archivo Histórico (Modelos)"
        )
        if ruta:
            # Validar archivo
            es_valido, mensaje = Validators.validar_archivo_excel(ruta)
            if es_valido:
                self.config_data["modelos"] = ruta
                self.ruta_modelos_var.set(ruta)
                self.guardar_configuracion()
                messagebox.showinfo("Éxito", "Archivo histórico cargado correctamente")
            else:
                messagebox.showerror("Error", f"Archivo inválido: {mensaje}")
    
    def guardar_configuracion(self):
        """Guarda la configuración en la base de datos"""
        try:
            # Guardar en base de datos
            for clave, valor in self.config_data.items():
                if valor:  # Solo guardar valores no vacíos
                    data = {"valor": valor}
                    condition = {"clave": clave}
                    
                    # Verificar si existe
                    existing = self.db_manager.execute_query(
                        "SELECT id FROM configuracion WHERE clave = %s",
                        (clave,)
                    )
                    
                    if existing:
                        self.db_manager.update_one("configuracion", data, condition)
                    else:
                        data["clave"] = clave
                        data["descripcion"] = f"Configuración de {clave}"
                        self.db_manager.insert_one("configuracion", data)
            
            messagebox.showinfo("Éxito", "Configuración guardada correctamente")
            self.logger.log_user_action(self.usuario, "Configuración actualizada")
            
        except Exception as e:
            self.logger.error(f"Error guardando configuración: {str(e)}")
            messagebox.showerror("Error", f"Error al guardar configuración: {str(e)}")
    
    def crear_usuario(self):
        """Crea un nuevo usuario"""
        usuario = self.nuevo_usuario_var.get().strip()
        contraseña = self.nueva_contraseña_var.get().strip()
        rol = self.nuevo_rol_var.get().strip()
        if not usuario or not contraseña:
            messagebox.showwarning("Campos vacíos", "Usuario y contraseña son obligatorios")
            return
        es_valido_usuario, mensaje_usuario = Validators.validar_usuario(usuario)
        es_valido_pass, mensaje_pass = Validators.validar_contraseña(contraseña)
        if not es_valido_usuario:
            messagebox.showerror("Error", mensaje_usuario)
            return
        if not es_valido_pass:
            messagebox.showerror("Error", mensaje_pass)
            return
        try:
            if self.usuario_model.crear_usuario(usuario, contraseña, rol):
                messagebox.showinfo("Éxito", f"Usuario {usuario} creado correctamente")
                self.logger.log_user_action(self.usuario, f"Usuario creado: {usuario}")
                self.nuevo_usuario_var.set("")
                self.nueva_contraseña_var.set("")
                self.nuevo_usuario_entry.focus_set()
                self._refresh_usuarios_table()
            else:
                messagebox.showerror("Error", "Error al crear usuario")
        except Exception as e:
            self.logger.error(f"Error creando usuario: {str(e)}")
            messagebox.showerror("Error", f"Error al crear usuario: {str(e)}")
    
    def _restablecer_contrasena_usuario(self):
        from tkinter import simpledialog, messagebox
        tree = self._get_usuarios_tree()
        if not tree:
            messagebox.showwarning("Error", "No se encontró la tabla de usuarios.")
            return
        sel = tree.selection()
        if not sel:
            messagebox.showwarning("Selecciona un usuario", "Debes seleccionar un usuario para restablecer la contraseña.")
            return
        item = sel[0]
        usuario = tree.item(item)['values'][1]
        # Pedir nueva contraseña
        nueva_pass = simpledialog.askstring("Restablecer contraseña", f"Nueva contraseña para '{usuario}':", show='*')
        if not nueva_pass:
            return
        # Validar contraseña
        es_valido, mensaje = Validators.validar_contraseña(nueva_pass)
        if not es_valido:
            messagebox.showerror("Error", mensaje)
            return
        # Hashear y actualizar
        import hashlib
        nueva_hash = hashlib.sha256(nueva_pass.encode()).hexdigest()
        self.db_manager.update_one("usuarios", {"contraseña": nueva_hash}, {"usuario": usuario})
        messagebox.showinfo("Éxito", f"Contraseña restablecida para '{usuario}'.")
        self._refresh_usuarios_table()
    
    def refrescar_base_datos(self):
        # Recarga los datos desde el CLP e histórico
        try:
            ruta_clp = self.config_data.get("contenedor", "")
            if not ruta_clp:
                messagebox.showerror("Error", "No se ha configurado el archivo CLP.")
                return
            resultado = self.codigo_model.cargar_clp(ruta_clp)
            messagebox.showinfo("Éxito", f"Base de datos recargada.\nNuevos registros: {resultado.get('nuevos_registros', 0)}\nTotal procesados: {resultado.get('total_procesados', 0)}")
            self.logger.log_user_action(self.usuario, "Base de datos refrescada")
            # Actualizar tabla de usuarios si está visible
            if hasattr(self, '_refresh_usuarios_table'):
                self._refresh_usuarios_table()
        except Exception as e:
            self.logger.error(f"Error refrescando base de datos: {str(e)}")
            messagebox.showerror("Error", f"Error al refrescar base de datos: {str(e)}")
    
    def aceptar_todas_capturas_pendientes(self):
        # Lógica para aceptar todas las capturas pendientes de otros usuarios
        try:
            self.subir_capturas_offline()
            messagebox.showinfo("Éxito", "Todas las capturas pendientes han sido aceptadas y subidas al histórico.")
        except Exception as e:
            self.logger.error(f"Error aceptando todas las capturas: {str(e)}")
            messagebox.showerror("Error", f"Error al aceptar capturas: {str(e)}")
    
    def _guardar_captura_offline(self, codigo, item, motivo, cumple):
        """Guarda la captura localmente en un archivo JSON por usuario"""
        ruta = f"capturas_pendientes_{self.usuario}.json"
        captura = {
            "codigo": codigo,
            "item": item,
            "motivo": motivo,
            "cumple": cumple,
            "usuario": self.usuario
        }
        try:
            capturas = []
            try:
                with open(ruta, "r", encoding="utf-8") as f:
                    capturas = json.load(f)
            except Exception:
                pass
            capturas.append(captura)
            with open(ruta, "w", encoding="utf-8") as f:
                json.dump(capturas, f, ensure_ascii=False, indent=2)
        except Exception as e:
            self.logger.error(f"Error guardando captura offline: {str(e)}")
    
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
    
    def _buscar_item_automatico(self, *args):
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
        """Ejecuta la búsqueda automática del item"""
        try:
            resultado = self.codigo_model.buscar_codigo(codigo)
            if resultado and resultado.get('item'):
                # Actualizar el campo item en el hilo principal
                self.master.after(0, lambda: self.item_captura_var.set(resultado['item']))
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

if __name__ == "__main__":
    app = EscanerApp()
    app.ejecutar() 
