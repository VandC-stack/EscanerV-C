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
try:
    from tkcalendar import DateEntry 
except ImportError:
    DateEntry = None

# Configuración de la aplicación
ct.set_appearance_mode("dark")
ct.set_default_color_theme("dark-blue")

# Constantes de versión
#VERSION_ACTUAL = "0.3.0"
#FECHA_COMPILACION = "2025-01-28"

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
        from tkinter import ttk
        import customtkinter as ct
        # Crear ventana toplevel
        top = ct.CTkToplevel(self.master)
        top.title("Historial del día")
        top.geometry("700x500")
        top.configure(fg_color="#000000")
        top.lift()
        top.attributes('-topmost', True)
        top.focus_force()

        # Frame principal
        main_frame = ct.CTkFrame(top, fg_color="#000000")
        main_frame.pack(fill="both", expand=True, padx=20, pady=20)

        # Sección de cargas CLP
        ct.CTkLabel(
            main_frame, text="Cargas CLP del día:", font=("Segoe UI", 16, "bold"), text_color="#00FFAA", fg_color="#000000"
        ).pack(anchor="w", pady=(0, 5))
        try:
            query_cargas = "SELECT archivo, usuario, fecha_carga, codigos_agregados FROM clp_cargas WHERE fecha_carga::date = CURRENT_DATE ORDER BY fecha_carga DESC"
            cargas = self.db_manager.execute_query(query_cargas)
        except Exception as e:
            cargas = []
        cargas_text = "Sin cargas hoy."
        if cargas:
            cargas_text = "\n".join([
                f"{c['fecha_carga']}: {c['archivo']} (Usuario: {c['usuario']}, Códigos: {c['codigos_agregados']})" for c in cargas
            ])
        cargas_label = ct.CTkTextbox(main_frame, width=650, height=60, fg_color="#111111", text_color="#00FFAA", font=("Segoe UI", 12))
        cargas_label.insert("1.0", cargas_text)
        cargas_label.configure(state="disabled")
        cargas_label.pack(pady=(0, 15))

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

        # Botón cerrar
        cerrar_btn = ct.CTkButton(
            main_frame, text="Cerrar", command=top.destroy,
            font=("Segoe UI", 14, "bold"), fg_color="#00FFAA", text_color="#000000",
            width=200, height=40, corner_radius=12
        )
        cerrar_btn.pack(pady=10)

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
        # NOM oculta por el momento porque me da flojera revisar la logica y no tengo como hacer relacion
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
            hover_color="#111111",
            border_width=2,
            border_color="#00FFAA",
            text_color="#00FFAA",
            corner_radius=12,
            width=200,
            height=32,
            command=self.cerrar_sesion
        )
        self.logout_button.pack(pady=(0, 8))
    
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
            self.exportar_reporte_button.pack(pady=(0, 18))
    
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
    
    def buscar_codigo(self):
        codigo = self.codigo_var.get().strip()
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
            text_color="#00FFAA"
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
        """Guarda la captura offline obteniendo los valores de los campos"""
        codigo = self.codigo_captura_var.get().strip()
        item = self.item_captura_var.get().strip()
        motivo = self.motivo_captura_var.get().strip() if self.cumple_captura_var.get() == "NO CUMPLE" else ""
        cumple = self.cumple_captura_var.get().strip()
        
        if not codigo or not item or not cumple:
            messagebox.showwarning("Campos vacíos", "Código, item y cumple son obligatorios")
            return
        if cumple == "NO CUMPLE" and not motivo:
            messagebox.showwarning("Campos vacíos", "El motivo es obligatorio si el resultado es NO CUMPLE")
            return
        self._guardar_captura_offline(codigo, item, motivo, cumple)
        messagebox.showinfo("Éxito", "Captura guardada offline")
        self.codigo_captura_var.set("")
        self.item_captura_var.set("")
        self.codigo_captura_entry.focus_set()
    
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
            resultado = self.codigo_model.buscar_codigo(codigo)
            if resultado and resultado.get('item'):
                # Actualizar el campo item y resultado en el hilo principal
                self.master.after(0, lambda: self.item_captura_var.set(resultado['item']))
                if 'resultado' in resultado:
                    self.master.after(0, lambda: self.cumple_captura_var.set(resultado['resultado']))
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

    def mostrar_historial_cargas_y_consultas(self):
        import tkinter as tk
        from tkinter import ttk
        import customtkinter as ct
        # Crear ventana toplevel
        top = ct.CTkToplevel(self.master)
        top.title("Historial del día")
        top.geometry("700x500")
        top.configure(fg_color="#000000")
        top.lift()
        top.attributes('-topmost', True)
        top.focus_force()

        # Frame principal
        main_frame = ct.CTkFrame(top, fg_color="#000000")
        main_frame.pack(fill="both", expand=True, padx=20, pady=20)

        # Sección de cargas CLP
        ct.CTkLabel(
            main_frame, text="Cargas CLP del día:", font=("Segoe UI", 16, "bold"), text_color="#00FFAA", fg_color="#000000"
        ).pack(anchor="w", pady=(0, 5))
        try:
            query_cargas = "SELECT archivo, usuario, fecha_carga, codigos_agregados FROM clp_cargas WHERE fecha_carga::date = CURRENT_DATE ORDER BY fecha_carga DESC"
            cargas = self.db_manager.execute_query(query_cargas)
        except Exception as e:
            cargas = []
        cargas_text = "Sin cargas hoy."
        if cargas:
            cargas_text = "\n".join([
                f"{c['fecha_carga']}: {c['archivo']} (Usuario: {c['usuario']}, Códigos: {c['codigos_agregados']})" for c in cargas
            ])
        cargas_label = ct.CTkTextbox(main_frame, width=650, height=60, fg_color="#111111", text_color="#00FFAA", font=("Segoe UI", 12))
        cargas_label.insert("1.0", cargas_text)
        cargas_label.configure(state="disabled")
        cargas_label.pack(pady=(0, 15))

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

        # Botón cerrar
        cerrar_btn = ct.CTkButton(
            main_frame, text="Cerrar", command=top.destroy,
            font=("Segoe UI", 14, "bold"), fg_color="#00FFAA", text_color="#000000",
            width=200, height=40, corner_radius=12
        )
        cerrar_btn.pack(pady=10)

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

    def _crear_formulario_usuario(self, parent, side="left"):
        """Crea el formulario de usuario para superadmin"""
        form_frame = ct.CTkFrame(parent, fg_color="#111111")
        form_frame.pack(side=side, fill="both", expand=True, padx=(0, 10))
        
        # Título del formulario
        ct.CTkLabel(
            form_frame,
            text="Crear/Editar Usuario",
            font=("Segoe UI", 16, "bold"),
            text_color="#00FFAA"
        ).pack(pady=(20, 20))
        
        # Variables
        self.usuario_form_var = StringVar()
        self.password_form_var = StringVar()
        self.rol_form_var = StringVar(value="usuario")
        self.activo_form_var = StringVar(value="activo")
        
        # Usuario
        ct.CTkLabel(form_frame, text="Usuario:", text_color="#00FFAA").pack(anchor="w", padx=20, pady=(0, 5))
        self.usuario_form_entry = ct.CTkEntry(
            form_frame,
            textvariable=self.usuario_form_var,
            width=300,
            height=32
        )
        self.usuario_form_entry.pack(padx=20, pady=(0, 15))
        
        # Contraseña
        ct.CTkLabel(form_frame, text="Contraseña:", text_color="#00FFAA").pack(anchor="w", padx=20, pady=(0, 5))
        self.password_form_entry = ct.CTkEntry(
            form_frame,
            textvariable=self.password_form_var,
            show="*",
            width=300,
            height=32
        )
        self.password_form_entry.pack(padx=20, pady=(0, 15))
        
        # Rol
        ct.CTkLabel(form_frame, text="Rol:", text_color="#00FFAA").pack(anchor="w", padx=20, pady=(0, 5))
        self.rol_form_menu = ct.CTkOptionMenu(
            form_frame,
            variable=self.rol_form_var,
            values=["usuario", "captura", "admin", "superadmin"],
            width=300,
            height=32
        )
        self.rol_form_menu.pack(padx=20, pady=(0, 15))
        
        # Estado
        ct.CTkLabel(form_frame, text="Estado:", text_color="#00FFAA").pack(anchor="w", padx=20, pady=(0, 5))
        self.activo_form_menu = ct.CTkOptionMenu(
            form_frame,
            variable=self.activo_form_var,
            values=["activo", "inactivo"],
            width=300,
            height=32
        )
        self.activo_form_menu.pack(padx=20, pady=(0, 20))
        
        # Botones
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
    
    def _crear_lista_usuarios(self, parent, side="right"):
        """Crea la lista de usuarios para superadmin"""
        list_frame = ct.CTkFrame(parent, fg_color="#111111")
        list_frame.pack(side=side, fill="both", expand=True, padx=(10, 0))
        
        # Título de la lista
        ct.CTkLabel(
            list_frame,
            text="Usuarios Registrados",
            font=("Segoe UI", 16, "bold"),
            text_color="#00FFAA"
        ).pack(pady=(20, 20))
        
        # Frame para la tabla
        table_frame = ct.CTkFrame(list_frame, fg_color="#000000")
        table_frame.pack(fill="both", expand=True, padx=20, pady=(0, 20))
        
        # Crear tabla con ttk.Treeview
        from tkinter import ttk
        
        columns = ("Usuario", "Rol", "Estado", "Último Acceso")
        self.usuarios_tree = ttk.Treeview(table_frame, columns=columns, show="headings", height=15)
        
        # Configurar columnas
        for col in columns:
            self.usuarios_tree.heading(col, text=col)
            self.usuarios_tree.column(col, width=120, anchor="center")
        
        # Estilo de la tabla
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
        
        # Scrollbar
        scrollbar = ttk.Scrollbar(table_frame, orient="vertical", command=self.usuarios_tree.yview)
        self.usuarios_tree.configure(yscrollcommand=scrollbar.set)
        
        # Empaquetar tabla y scrollbar
        self.usuarios_tree.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        
        # Cargar usuarios
        self.cargar_usuarios()
        
        # Evento de selección
        self.usuarios_tree.bind("<<TreeviewSelect>>", self.on_usuario_select)
        
        # Botones de acción
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
            text="Refrescar",
            command=self.cargar_usuarios,
            fg_color="#00AAFF",
            text_color="#FFFFFF",
            width=120,
            height=32
        ).pack(side="left", padx=5)
    
    def cargar_usuarios(self):
        """Carga los usuarios en la tabla"""
        try:
            # Limpiar tabla
            for item in self.usuarios_tree.get_children():
                self.usuarios_tree.delete(item)
            
            # Obtener usuarios de la base de datos
            usuarios = self.usuario_model.obtener_todos_usuarios()
            
            # Insertar en la tabla
            for usuario in usuarios:
                self.usuarios_tree.insert("", "end", values=(
                    usuario.get('usuario', ''),
                    usuario.get('rol', ''),
                    usuario.get('estado', ''),
                    usuario.get('ultimo_acceso', '')
                ))
                
        except Exception as e:
            self.logger.error(f"Error cargando usuarios: {str(e)}")
    
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
                self.logger.log_user_action(self.usuario, f"Usuario creado: {usuario}")
            else:
                messagebox.showerror("Error", "No se pudo crear el usuario")
                
        except Exception as e:
            self.logger.error(f"Error creando usuario: {str(e)}")
            messagebox.showerror("Error", f"Error al crear usuario: {str(e)}")
    
    def limpiar_formulario_usuario(self):
        """Limpia el formulario de usuario"""
        self.usuario_form_var.set("")
        self.password_form_var.set("")
        self.rol_form_var.set("usuario")
        self.activo_form_var.set("activo")
    
    def on_usuario_select(self, event):
        """Maneja la selección de un usuario en la tabla"""
        selection = self.usuarios_tree.selection()
        if selection:
            item = self.usuarios_tree.item(selection[0])
            values = item['values']
            if values:
                self.usuario_form_var.set(values[0])  # Usuario
                self.rol_form_var.set(values[1])      # Rol
                self.activo_form_var.set(values[2])   # Estado
                self.password_form_var.set("")        # No mostrar contraseña
    
    def eliminar_usuario(self):
        """Elimina el usuario seleccionado"""
        selection = self.usuarios_tree.selection()
        if not selection:
            messagebox.showwarning("Sin selección", "Selecciona un usuario para eliminar")
            return
        
        item = self.usuarios_tree.item(selection[0])
        usuario = item['values'][0]
        
        if usuario == self.usuario:
            messagebox.showwarning("Error", "No puedes eliminar tu propio usuario")
            return
        
        if messagebox.askyesno("Confirmar", f"¿Estás seguro de eliminar al usuario '{usuario}'?"):
            try:
                resultado = self.usuario_model.eliminar_usuario(usuario)
                if resultado:
                    messagebox.showinfo("Éxito", "Usuario eliminado correctamente")
                    self.cargar_usuarios()
                    self.limpiar_formulario_usuario()
                    self.logger.log_user_action(self.usuario, f"Usuario eliminado: {usuario}")
                else:
                    messagebox.showerror("Error", "No se pudo eliminar el usuario")
            except Exception as e:
                self.logger.error(f"Error eliminando usuario: {str(e)}")
                messagebox.showerror("Error", f"Error al eliminar usuario: {str(e)}")
    
    def cambiar_estado_usuario(self):
        """Cambia el estado del usuario seleccionado"""
        selection = self.usuarios_tree.selection()
        if not selection:
            messagebox.showwarning("Sin selección", "Selecciona un usuario para cambiar su estado")
            return
        
        item = self.usuarios_tree.item(selection[0])
        usuario = item['values'][0]
        estado_actual = item['values'][2]
        
        nuevo_estado = "inactivo" if estado_actual == "activo" else "activo"
        
        try:
            resultado = self.usuario_model.cambiar_estado_usuario(usuario, nuevo_estado)
            if resultado:
                messagebox.showinfo("Éxito", f"Estado cambiado a {nuevo_estado}")
                self.cargar_usuarios()
                self.logger.log_user_action(self.usuario, f"Estado cambiado para {usuario}: {nuevo_estado}")
            else:
                messagebox.showerror("Error", "No se pudo cambiar el estado")
        except Exception as e:
            self.logger.error(f"Error cambiando estado: {str(e)}")
            messagebox.showerror("Error", f"Error al cambiar estado: {str(e)}")

    # Botón cerrar sesión (logout)
    def cerrar_sesion(self):
        """Cierra la sesión y regresa a la pantalla de login"""
        try:
            self.master.destroy()
            app = EscanerApp()
            app.ejecutar()
        except Exception as e:
            print(f"Error al cerrar sesión: {str(e)}")

if __name__ == "__main__":
    app = EscanerApp()
    app.ejecutar()    