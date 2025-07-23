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
from tkcalendar import DateEntry 

try:
    from tkcalendar import DateEntry
except ImportError:
    DateEntry = None

# Función general para cargar JSON de diseño
def cargar_diseño(path):
    import json
    import os

    if not os.path.exists(path):
        print(f"[ERROR] Archivo de diseño no encontrado: {path}")
        return {}

    try:
        with open(path, 'r', encoding='utf-8') as file:
            return json.load(file)
    except Exception as e:
        print(f"[ERROR] Error cargando diseño desde {path}: {e}")
        return {}

# Constantes de versión
#VERSION_ACTUAL = "0.3.4"
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

print("Default encoding:", sys.getdefaultencoding())
print("Filesystem encoding:", sys.getfilesystemencoding())

# --- Funcion utilitaria para actualizar widgets de forma segura porque me odio ---
def safe_configure(widget, **kwargs):
    try:
        if widget and widget.winfo_exists():
            widget.configure(**kwargs)
    except Exception:
        pass  

class EscanerApp:
    def __init__(self):
        self.root = ct.CTk()
        self.root.title("Escáner V&C v0.3.4")
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
        """Crea la interfaz de login desde JSON"""
        diseño = cargar_diseño("theme/claseLogin.json")

        # Frame principal (fondo blanco)
        self.frame = ct.CTkFrame(self.master, fg_color=diseño["frame"]["fg_color"])
        self.frame.pack(
            fill=diseño["frame"]["fill"],
            expand=diseño["frame"]["expand"],
            padx=diseño["frame"]["padx"],
            pady=diseño["frame"]["pady"]
        )

        # Título centrado en la parte superior
        self.label_title = ct.CTkLabel(
            self.frame,
            text=diseño["titulo"]["text"],
            font=tuple(diseño["titulo"]["font"]),
            text_color=diseño["titulo"]["text_color"]
        )
        self.label_title.pack(pady=tuple(diseño["titulo"]["pady"]))

        # Caja amarilla centrada
        self.form_box = ct.CTkFrame(
            self.frame,
            fg_color=diseño["form_box"]["fg_color"],
            corner_radius=diseño["form_box"]["corner_radius"]
        )
        self.form_box.pack(
            padx=diseño["form_box"]["padx"],
            pady=diseño["form_box"]["pady"]
        )
        self.form_box.grid_propagate(False)
        self.form_box.configure(
            width=diseño["entry"]["width"] + diseño["form_box"]["internal_padx"],
            height=(diseño["entry"]["height"] * 3) + diseño["form_box"]["internal_pady"]
        )

        self.user_var = StringVar()
        self.pass_var = StringVar()

        # Usuario label
        self.label_user = ct.CTkLabel(
            self.form_box,
            text=diseño["labels"][0]["text"],
            text_color=diseño["labels"][0]["text_color"]
        )
        self.label_user.pack(anchor=diseño["labels"][0]["anchor"])

        # Entrada de usuario
        self.entry_user = ct.CTkEntry(
            self.form_box,
            textvariable=self.user_var,
            width=diseño["entry"]["width"],
            height=diseño["entry"]["height"],
            fg_color=diseño["entry"]["fg_color"],
            border_color=diseño["entry"]["border_color"],
            border_width=diseño["entry"]["border_width"],
            corner_radius=diseño["entry"]["corner_radius"],
            text_color=diseño["entry"]["text_color"],
            placeholder_text="👤 Ingresa tu usuario"
        )
        self.entry_user.pack(pady=tuple(diseño["entry_pady"]))

        # Contraseña label
        self.label_pass = ct.CTkLabel(
            self.form_box,
            text=diseño["labels"][1]["text"],
            text_color=diseño["labels"][1]["text_color"]
        )
        self.label_pass.pack(anchor=diseño["labels"][1]["anchor"])

        # Frame contenedor de la contraseña + botón
        self.pass_row = ct.CTkFrame(
            self.form_box,
            fg_color=diseño["pass_row"]["fg_color"]
        )
        self.pass_row.pack(fill="x", pady=tuple(diseño["entry_pady"]))

        # Entrada de contraseña
        self.entry_pass = ct.CTkEntry(
            self.pass_row,
            textvariable=self.pass_var,
            show="*",
            width=diseño["entry"]["width"],
            height=diseño["entry"]["height"],
            fg_color=diseño["entry"]["fg_color"],
            border_color=diseño["entry"]["border_color"],
            border_width=diseño["entry"]["border_width"],
            corner_radius=diseño["entry"]["corner_radius"],
            text_color=diseño["entry"]["text_color"],
            placeholder_text="🔒 Ingresa tu contraseña"
        )
        self.entry_pass.pack(side="left", fill="x", expand=True)

        # Botón de login
        self.login_button = ct.CTkButton(
            self.form_box,
            text=diseño["login_button"]["text"],
            width=diseño["login_button"]["width"],
            height=diseño["login_button"]["height"],
            fg_color=diseño["login_button"]["fg_color"],
            text_color=diseño["login_button"]["text_color"],
            hover_color=diseño["login_button"]["hover_color"],
            border_color=diseño["login_button"]["border_color"],
            border_width=diseño["login_button"]["border_width"],
            corner_radius=diseño["login_button"]["corner_radius"],
            font=tuple(diseño["login_button"]["font"]),
            command=self.try_login
        )
        self.login_button.pack(pady=tuple(diseño["login_button"]["pady"]))

        # Mensaje de error
        self.error_label = ct.CTkLabel(
            self.form_box,
            text=diseño["error_label"]["text"],
            text_color=diseño["error_label"]["text_color"],
            font=tuple(diseño["error_label"]["font"])
        )
        self.error_label.pack(pady=tuple(diseño["error_label"]["pady"]))

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
    # Crear interfaz principal del escaner

    def crear_interfaz(self):
        try:
            diseño = cargar_diseño("theme/main_window.json")
            tabview_conf = diseño["tabview"]

            self.tabview = ct.CTkTabview(
                self.master,
                fg_color=tabview_conf["fg_color"]
            )
            self.tabview.pack(
                fill="both",
                expand=True,
                padx=tabview_conf["padx"],
                pady=tabview_conf["pady"]
            )

            if self.rol == "superadmin":
                self._crear_interfaz_superadmin()
                self.tabview.set("Gestión de Usuarios")
            else:
                self._crear_interfaz_normal()
                self.tabview.set("Escáner")
        except Exception as e:
            self.logger.error(f"Error creando interfaz: {str(e)}")
            raise e
    # Crear interfaz específica para superadmin

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
    # Crear interfaz normal para otros usuarios

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
        diseño = cargar_diseño("theme/main_window.json")
        gestion_conf = diseño["gestion_usuarios"]

        main_frame_conf = gestion_conf["main_frame"]
        main_frame = ct.CTkFrame(
            parent,
            fg_color=main_frame_conf["fg_color"]
        )
        main_frame.pack(
            fill="both",
            expand=True,
            padx=main_frame_conf["padx"],
            pady=main_frame_conf["pady"]
        )

        label_conf = gestion_conf["label"]
        ct.CTkLabel(
            main_frame,
            text=label_conf["text"],
            font=tuple(label_conf["font"]),
            text_color=label_conf["text_color"]
        ).pack(pady=tuple(label_conf["pady"]))

        content_frame_conf = gestion_conf["content_frame"]
        content_frame = ct.CTkFrame(
            main_frame,
            fg_color=content_frame_conf["fg_color"]
        )
        content_frame.pack(fill="both", expand=True)

        self._crear_formulario_usuario(content_frame, side="left")
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

        diseño = cargar_diseño("theme/revision_capturas.json")

        # Frame scrollable principal
        sf_conf = diseño["scroll_frame"]
        scroll_frame = ct.CTkScrollableFrame(
            parent,
            fg_color=sf_conf["fg_color"],
            width=sf_conf["width"],
            height=sf_conf["height"]
        )
        scroll_frame.pack(**sf_conf["pack"])

        # Título
        title_conf = diseño["label_title"]
        ct.CTkLabel(
            scroll_frame,
            text=title_conf["text"],
            font=tuple(title_conf["font"]),
            text_color=title_conf["text_color"]
        ).pack(**title_conf["pack"])

        captura_model = Captura(self.db_manager)
        capturas = captura_model.obtener_todas_capturas()

        if not capturas:
            empty_conf = diseño["label_empty"]
            ct.CTkLabel(
                scroll_frame,
                text=empty_conf["text"],
                font=tuple(empty_conf["font"]),
                text_color=empty_conf["text_color"]
            ).pack(**empty_conf["pack"])
            return

        columns = list(capturas[0].keys())

        # Configurar estilos ttk para Treeview
        style = ttk.Style()
        style.theme_use('default')
        tv_style = diseño["treeview_style"]
        style.configure("Treeview",
                        background=tv_style["background"],
                        foreground=tv_style["foreground"],
                        rowheight=tv_style["rowheight"],
                        fieldbackground=tv_style["fieldbackground"],
                        font=tuple(tv_style["font"]))
        style.configure("Treeview.Heading",
                        background=tv_style["heading_background"],
                        foreground=tv_style["heading_foreground"],
                        font=tuple(tv_style["heading_font"]))
        style.map('Treeview', background=[('selected', tv_style["selected_background"])])

        tv_conf = diseño["treeview"]
        tree = ttk.Treeview(
            scroll_frame,
            columns=columns,
            show=tv_conf["show"],
            height=tv_conf["height"],
            style="Treeview",
            selectmode=tv_conf["selectmode"]
        )
        for col in columns:
            tree.heading(col, text=col)
            tree.column(col, width=120, anchor="center")
        for row in capturas:
            tree.insert("", "end", values=[row[col] for col in columns])
        tree.pack(**tv_conf["pack"])

        instr_conf = diseño["label_select_instruction"]
        ct.CTkLabel(
            scroll_frame,
            text=instr_conf["text"],
            text_color=instr_conf["text_color"]
        ).pack(**instr_conf["pack"])

        btns_conf = diseño["buttons_frame"]
        btns_frame = ct.CTkFrame(scroll_frame, fg_color=btns_conf["fg_color"])
        btns_frame.pack(**btns_conf["pack"])

        def refrescar_codigos_items_tabla():
            try:
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
            messagebox.showinfo(
                "Éxito",
                f"Capturas aceptadas y movidas a codigos_items. Procesadas: {resultado['procesados']}, Actualizadas: {resultado['actualizados']}"
            )
            refrescar_codigos_items_tabla()

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

        aceptar_btn_conf = diseño["button_aceptar"]
        aceptar_btn = ct.CTkButton(
            btns_frame,
            text=aceptar_btn_conf["text"],
            command=aceptar,
            fg_color=aceptar_btn_conf["fg_color"],
            text_color=aceptar_btn_conf["text_color"],
            font=tuple(aceptar_btn_conf["font"]),
            border_width=aceptar_btn_conf["border_width"],
            border_color=aceptar_btn_conf["border_color"],
            corner_radius=aceptar_btn_conf["corner_radius"]
        )
        aceptar_btn.pack(**aceptar_btn_conf["pack"])

        denegar_btn_conf = diseño["button_denegar"]
        denegar_btn = ct.CTkButton(
            btns_frame,
            text=denegar_btn_conf["text"],
            command=denegar,
            fg_color=denegar_btn_conf["fg_color"],
            text_color=denegar_btn_conf["text_color"],
            font=tuple(denegar_btn_conf["font"]),
            border_width=denegar_btn_conf["border_width"],
            border_color=denegar_btn_conf["border_color"],
            corner_radius=denegar_btn_conf["corner_radius"]
        )
        denegar_btn.pack(**denegar_btn_conf["pack"])

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
        diseño = cargar_diseño("theme/tab_escaner.json")

        # Frame principal
        mf_conf = diseño["main_frame"]
        main_frame = ct.CTkFrame(parent, fg_color=mf_conf["fg_color"])
        main_frame.pack(**mf_conf["pack"])

        # Columna izquierda
        lc_conf = diseño["left_col"]
        left_col = ct.CTkFrame(main_frame, fg_color=lc_conf["fg_color"])
        left_col.pack(**lc_conf["pack"])

        self._crear_header(left_col)

        ce_conf = diseño["codigo_entry"]
        self.codigo_var = ct.StringVar()
        self.codigo_entry = ct.CTkEntry(
            left_col,
            textvariable=self.codigo_var,
            font=tuple(ce_conf["font"]),
            width=ce_conf["width"],
            height=ce_conf["height"],
            corner_radius=ce_conf["corner_radius"],
            border_width=ce_conf["border_width"],
            border_color=ce_conf["border_color"],
            fg_color=ce_conf["fg_color"],
            text_color=ce_conf["text_color"],
            placeholder_text=ce_conf["placeholder_text"]
        )
        self.codigo_entry.pack(**ce_conf["pack"])
        self.codigo_entry.bind("<Return>", lambda e: self.buscar_codigo())

        self._crear_botones_escaner(left_col)
        self._crear_resultados_escaner(left_col)
        

        rc_conf = diseño["right_col"]
        right_col = ct.CTkFrame(main_frame, fg_color=rc_conf["fg_color"])
        right_col.pack(**rc_conf["pack"])

        self._crear_estadisticas_escaner(right_col)

        self._crear_botones_adicionales(right_col)
    
    # Crear header (barra latera izquierda con logo y título)
    def _crear_header(self, parent):
        diseño = cargar_diseño("theme/header.json")

        logo_conf = diseño["logo"]
        logo_path = os.path.join(os.path.dirname(__file__), logo_conf["path"])

        if logo_conf["enabled"] and os.path.exists(logo_path):
            try:
                logo_img = ct.CTkImage(
                    light_image=Image.open(logo_path),
                    dark_image=Image.open(logo_path),
                    size=tuple(logo_conf["size"])
                )
                logo_label = ct.CTkLabel(
                    parent,
                    image=logo_img,
                    text="",
                    fg_color=logo_conf["fg_color"]
                )
                logo_label.pack(pady=tuple(logo_conf["pady"]))
            except Exception as e:
                self.logger.error(f"Error cargando logo: {str(e)}")
                self._crear_logo_fallback(parent, logo_conf)
        else:
            self._crear_logo_fallback(parent, logo_conf)

        titulo_conf = diseño["titulo"]
        ct.CTkLabel(
            parent,
            text=titulo_conf["text"],
            font=tuple(titulo_conf["font"]),
            text_color=titulo_conf["text_color"],
            fg_color=titulo_conf["fg_color"]
        ).pack(pady=tuple(titulo_conf["pady"]))

    def _crear_logo_fallback(self, parent, logo_conf):
        """Crea el texto alternativo cuando falla la imagen del logo"""
        ct.CTkLabel(
            parent,
            text=logo_conf["fallback_text"],
            font=tuple(logo_conf["fallback_font"]),
            text_color=logo_conf["fallback_color"],
            fg_color=logo_conf["fg_color"]
        ).pack(pady=tuple(logo_conf["pady"]))

    def _crear_botones_escaner(self, parent):
        diseño = cargar_diseño("theme/tab_escaner.json")
        btn_conf = diseño["search_button"]

        botones_frame = ct.CTkFrame(parent, fg_color=btn_conf["frame_fg_color"])
        botones_frame.pack(**btn_conf["frame_pack"])

        self.search_button = ct.CTkButton(
            botones_frame,
            text=btn_conf["text"],
            font=tuple(btn_conf["font"]),
            fg_color=btn_conf["fg_color"],
            hover_color=btn_conf["hover_color"],
            border_width=btn_conf["border_width"],
            border_color=btn_conf["border_color"],
            text_color=btn_conf["text_color"],
            corner_radius=btn_conf["corner_radius"],
            width=btn_conf["width"],
            height=btn_conf["height"],
            command=self.buscar_codigo
        )
        self.search_button.pack(**btn_conf["pack"])

    def _crear_resultados_escaner(self, parent):
        diseño = cargar_diseño("theme/tab_escaner.json")
        lbl_conf = diseño["labels_resultado"]

        self.clave_valor = ct.CTkLabel(
            parent,
            text="ITEM: ",
            font=tuple(lbl_conf["font_clave"]),
            text_color=lbl_conf["text_color_clave"],
            fg_color=lbl_conf["fg_color"]
        )
        self.clave_valor.pack(pady=tuple(lbl_conf["padys"]["clave"]))

        self.resultado_valor = ct.CTkLabel(
            parent,
            text="RESULTADO: ",
            font=tuple(lbl_conf["font_resultado"]),
            text_color=lbl_conf["text_color_resultado"],
            fg_color=lbl_conf["fg_color"],
            wraplength=lbl_conf["wraplength"]
        )
        self.resultado_valor.pack(pady=tuple(lbl_conf["padys"]["resultado"]))

        self.nom_valor = ct.CTkLabel(
            parent,
            text="NOM: ",
            font=tuple(lbl_conf["font_nom"]),
            text_color=lbl_conf["text_color_nom"],
            fg_color=lbl_conf["fg_color"],
            wraplength=lbl_conf["wraplength"]
        )
        self.nom_valor.pack(pady=tuple(lbl_conf["padys"]["nom"]))

    def _crear_estadisticas_escaner(self, parent):
        diseño = cargar_diseño("theme/tab_escaner.json")
        stats_conf = diseño["estadisticas_labels"]

        labels_text = [
            "Total de códigos: 0",
            "Items en total: 0",
            "Sin resultado: 0",
            "Última actualización: Nunca"
        ]

        for i, text in enumerate(labels_text):
            pady_val = stats_conf["pady_ultima"] if i == 3 else stats_conf["pady"]
            ct.CTkLabel(
                parent,
                text=text,
                font=tuple(stats_conf["font"]),
                text_color=stats_conf["text_color"],
                fg_color=stats_conf["fg_color"]
            ).pack(pady=pady_val)

        logout_conf = diseño["logout_button"]
        self.logout_button = ct.CTkButton(
            parent,
            text=logout_conf["text"],
            font=tuple(logout_conf["font"]),
            fg_color=logout_conf["fg_color"],
            hover_color=logout_conf["hover_color"],
            border_width=logout_conf["border_width"],
            border_color=logout_conf["border_color"],
            text_color=logout_conf["text_color"],
            corner_radius=logout_conf["corner_radius"],
            width=logout_conf["width"],
            height=logout_conf["height"],
            command=self.cerrar_sesion
        )
        self.logout_button.pack(**logout_conf["pack"])

        historial_conf = diseño["historial_button"]
        self.historial_button = ct.CTkButton(
            parent,
            text=historial_conf["text"],
            font=tuple(historial_conf["font"]),
            fg_color=historial_conf["fg_color"],
            hover_color=historial_conf["hover_color"],
            border_width=historial_conf["border_width"],
            border_color=historial_conf["border_color"],
            text_color=historial_conf["text_color"],
            corner_radius=historial_conf["corner_radius"],
            width=historial_conf["width"],
            height=historial_conf["height"],
            command=self.mostrar_historial_cargas_y_consultas
        )
        self.historial_button.pack(**historial_conf["pack"])

        if self.rol == "admin":
            export_conf = diseño["exportar_reporte_button"]
            self.exportar_reporte_button = ct.CTkButton(
                parent,
                text=export_conf["text"],
                font=tuple(export_conf["font"]),
                fg_color=export_conf["fg_color"],
                hover_color=export_conf["hover_color"],
                border_width=export_conf["border_width"],
                border_color=export_conf["border_color"],
                text_color=export_conf["text_color"],
                corner_radius=export_conf["corner_radius"],
                width=export_conf["width"],
                height=export_conf["height"],
                command=self.exportar_reporte_dia
            )
            self.exportar_reporte_button.pack(**export_conf["pack"])

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

    def _crear_estadisticas_escaner(self, parent):
        """Crea las estadísticas del escáner"""
        diseño = cargar_diseño("theme/tab_escaner.json")
        stats_conf = diseño["estadisticas_labels"]

        # Total de códigos
        self.total_codigos_label = ct.CTkLabel(
            parent,
            text="Total de códigos: 0",
            font=tuple(stats_conf["font"]),
            text_color=stats_conf["text_color"],
            fg_color=stats_conf["fg_color"]
        )
        self.total_codigos_label.pack(pady=stats_conf["pady"])

        # Items en total
        self.con_resultado_label = ct.CTkLabel(
            parent,
            text="Items en total: 0",
            font=tuple(stats_conf["font"]),
            text_color=stats_conf["text_color"],
            fg_color=stats_conf["fg_color"]
        )
        self.con_resultado_label.pack(pady=stats_conf["pady"])

        # Sin resultado
        self.sin_resultado_label = ct.CTkLabel(
            parent,
            text="Sin resultado: 0",
            font=tuple(stats_conf["font"]),
            text_color=stats_conf["text_color"],
            fg_color=stats_conf["fg_color"]
        )
        self.sin_resultado_label.pack(pady=stats_conf["pady"])

        # Última actualización
        self.ultima_actualizacion_label = ct.CTkLabel(
            parent,
            text="Última actualización: Nunca",
            font=tuple(stats_conf["font"]),
            text_color=stats_conf["text_color"],
            fg_color=stats_conf["fg_color"]
        )
        self.ultima_actualizacion_label.pack(pady=stats_conf["pady_ultima"])
            
    # Crear botones adicionales (botones de logout, historial, exportar reporte y capturas)
    def _crear_botones_adicionales(self, parent):
        """Crea los botones adicionales (logout, historial, exportar reporte, exportar capturas)"""
        diseño = cargar_diseño("theme/tab_escaner.json")

        # Contenedor de botones
        botonera_frame = ct.CTkFrame(parent, fg_color="#FFFFFF")
        botonera_frame.pack(side="top", anchor="ne", pady=(30, 10), padx=10)

        # Botón Cerrar Sesión
        logout_conf = diseño["logout_button"]
        self.logout_button = ct.CTkButton(
            botonera_frame,
            text=logout_conf["text"],
            font=tuple(logout_conf["font"]),
            fg_color=logout_conf["fg_color"],
            hover_color=logout_conf["hover_color"],
            text_color=logout_conf["text_color"],
            width=logout_conf["width"],
            height=logout_conf["height"],
            corner_radius=logout_conf["corner_radius"],
            command=self.cerrar_sesion
        )
        self.logout_button.pack(**logout_conf["pack"])

        # Botón Historial
        historial_conf = diseño["historial_button"]
        self.historial_button = ct.CTkButton(
            botonera_frame,
            text=historial_conf["text"],
            font=tuple(historial_conf["font"]),
            fg_color=historial_conf["fg_color"],
            hover_color=historial_conf["hover_color"],
            text_color=historial_conf["text_color"],
            width=historial_conf["width"],
            height=historial_conf["height"],
            corner_radius=historial_conf["corner_radius"],
            command=self.mostrar_historial_cargas_y_consultas
        )
        self.historial_button.pack(**historial_conf["pack"])

        # Botón Exportar Reporte (solo admin)
        if self.rol == "admin":
            exportar_conf = diseño["exportar_reporte_button"]
            self.exportar_button = ct.CTkButton(
                botonera_frame,
                text=exportar_conf["text"],
                font=tuple(exportar_conf["font"]),
                fg_color=exportar_conf["fg_color"],
                hover_color=exportar_conf["hover_color"],
                text_color=exportar_conf["text_color"],
                width=exportar_conf["width"],
                height=exportar_conf["height"],
                corner_radius=exportar_conf["corner_radius"],
                command=self.exportar_reporte_dia
            )
            self.exportar_button.pack(**exportar_conf["pack"])

        # Botón Exportar Capturas (para todos)
        capturas_conf = diseño["exportar_capturas_button"]
        self.exportar_capturas_button = ct.CTkButton(
            botonera_frame,
            text=capturas_conf["text"],
            font=tuple(capturas_conf["font"]),
            fg_color=capturas_conf["fg_color"],
            hover_color=capturas_conf["hover_color"],
            text_color=capturas_conf["text_color"],
            border_color=capturas_conf["border_color"],
            border_width=capturas_conf["border_width"],
            width=capturas_conf["width"],
            height=capturas_conf["height"],
            corner_radius=capturas_conf["corner_radius"],
            command=self.exportar_capturas_dia
        )
        self.exportar_capturas_button.pack(**capturas_conf["pack"])

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
   
    def mostrar_historial_cargas_y_consultas(self):
        import tkinter as tk
        from tkinter import ttk, messagebox, filedialog
        import customtkinter as ct
        import pandas as pd

        # Carga el diseño desde JSON
        diseño = cargar_diseño("theme/historial_dia.json")

        # Crear ventana toplevel
        top = ct.CTkToplevel(self.master)
        top.title(diseño["window"]["title"])
        top.geometry(diseño["window"]["geometry"])
        top.configure(fg_color=diseño["window"]["fg_color"])
        top.lift()
        top.attributes('-topmost', True)
        top.focus_force()
        if "minsize" in diseño["window"]:
            top.minsize(*diseño["window"]["minsize"])
        top.resizable(True, True)

        # Frame principal
        main_frame = ct.CTkFrame(top, fg_color=diseño["main_frame"]["fg_color"])
        main_frame.pack(**diseño["main_frame"]["pack"])

        # --- FILTRO ---
        filtro_var = tk.StringVar()

        def actualizar_cargas(*args):
            filtro = filtro_var.get().strip().lower()
            try:
                if filtro:
                    query = "SELECT archivo, usuario, fecha_carga, codigos_agregados FROM clp_cargas WHERE LOWER(archivo) LIKE %s ORDER BY fecha_carga DESC"
                    cargas = self.db_manager.execute_query(query, (f"%{filtro}%",))
                else:
                    query = "SELECT archivo, usuario, fecha_carga, codigos_agregados FROM clp_cargas WHERE fecha_carga::date = CURRENT_DATE ORDER BY fecha_carga DESC"
                    cargas = self.db_manager.execute_query(query)
            except Exception as e:
                cargas = []
                print(f"Error al cargar cargas: {e}")

            texto = "Sin cargas."
            if cargas:
                texto = "\n".join([
                    f"{c['fecha_carga']}: {c['archivo']} (Usuario: {c['usuario']}, Códigos: {c['codigos_agregados']})"
                    for c in cargas
                ])

            cargas_label.configure(state="normal")
            cargas_label.delete("1.0", tk.END)
            cargas_label.insert("1.0", texto)
            cargas_label.configure(state="disabled")

        # Frame filtro
        filtro_frame = ct.CTkFrame(main_frame, fg_color=diseño["filtro_frame"]["fg_color"])
        filtro_frame.pack(**diseño["filtro_frame"]["pack"])

        filtro_label_cfg = diseño["labels"]["filtro"]
        ct.CTkLabel(filtro_frame,
                    text=filtro_label_cfg["text"],
                    text_color=filtro_label_cfg["text_color"],
                    font=tuple(filtro_label_cfg["font"])
                ).pack(side="left", padx=filtro_label_cfg.get("padx", 0))

        filtro_entry_cfg = diseño["entry"]
        filtro_entry = ct.CTkEntry(filtro_frame,
                                textvariable=filtro_var,
                                width=filtro_entry_cfg["width"],
                                height=filtro_entry_cfg.get("height", 28),
                                corner_radius=filtro_entry_cfg["corner_radius"],
                                border_width=filtro_entry_cfg["border_width"],
                                border_color=filtro_entry_cfg["border_color"],
                                fg_color=filtro_entry_cfg["fg_color"],
                                text_color=filtro_entry_cfg["text_color"],
                                font=tuple(filtro_entry_cfg["font"])
                                )
        filtro_entry.pack(side="left")
        filtro_var.trace_add('write', actualizar_cargas)

        # --- CARGAS DEL DÍA ---
        cargas_label_cfg = diseño["labels"]["cargas"]
        ct.CTkLabel(main_frame,
                    text=cargas_label_cfg["text"],
                    font=tuple(cargas_label_cfg["font"]),
                    text_color=cargas_label_cfg["text_color"],
                    fg_color=cargas_label_cfg.get("fg_color", diseño["window"]["fg_color"])
                ).pack(anchor=cargas_label_cfg.get("anchor", "w"),
                        pady=tuple(cargas_label_cfg.get("pady", (0, 5))))

        textbox_cfg = diseño["textbox"]
        cargas_label = ct.CTkTextbox(main_frame,
                                    width=textbox_cfg["width"],
                                    height=textbox_cfg["height"],
                                    fg_color=textbox_cfg["fg_color"],
                                    text_color=textbox_cfg["text_color"],
                                    font=tuple(textbox_cfg["font"]),
                                    corner_radius=textbox_cfg.get("corner_radius", 8),
                                    border_width=textbox_cfg.get("border_width", 1),
                                    border_color=textbox_cfg.get("border_color", "#00FFAA")
                                )
        cargas_label.pack(pady=(0, 15))
        actualizar_cargas()

        # --- CONSULTAS RECIENTES ---
        consultas_label_cfg = diseño["labels"]["consultas"]
        ct.CTkLabel(main_frame,
                    text=consultas_label_cfg["text"],
                    font=tuple(consultas_label_cfg["font"]),
                    text_color=consultas_label_cfg["text_color"],
                    fg_color=consultas_label_cfg.get("fg_color", diseño["window"]["fg_color"])
                ).pack(anchor=consultas_label_cfg.get("anchor", "w"),
                        pady=tuple(consultas_label_cfg.get("pady", (0, 5))))

        try:
            query = "SELECT fecha_hora, usuario, codigo_barras, resultado FROM consultas WHERE fecha_hora::date = CURRENT_DATE ORDER BY fecha_hora DESC LIMIT 50"
            consultas = self.db_manager.execute_query(query)
        except Exception as e:
            consultas = []
            print(f"Error al cargar consultas: {e}")

        # Tabla consultas
        st_cons = diseño["tablas"]["treeview_consultas"]
        table_frame = ct.CTkFrame(main_frame, fg_color=st_cons["background"])
        table_frame.pack(fill="both", expand=True, pady=(0, 10))

        tree = ttk.Treeview(table_frame, columns=st_cons["columns"], show="headings", height=12)

        style = ttk.Style()
        style.theme_use('default')
        style.configure("Treeview",
                        background=st_cons["background"],
                        foreground=st_cons["foreground"],
                        rowheight=st_cons["rowheight"],
                        fieldbackground=st_cons["fieldbackground"],
                        font=tuple(st_cons["font"]),
                        bordercolor=st_cons["bordercolor"],
                        borderwidth=st_cons["borderwidth"])
        style.configure("Treeview.Heading",
                        background=st_cons["heading"]["background"],
                        foreground=st_cons["heading"]["foreground"],
                        font=tuple(st_cons["heading"]["font"]),
                        relief=st_cons["heading"]["relief"])
        style.map('Treeview', background=[('selected', st_cons["selected_bg"])])

        for col in st_cons["columns"]:
            tree.heading(col, text=col)
            width = st_cons.get("columns_width", {}).get(col, 100)
            tree.column(col, width=width, anchor="center")

        for i, c in enumerate(consultas):
            tree.insert("", "end",
                        values=(c['fecha_hora'], c['usuario'], c['codigo_barras'], c['resultado'] or "Sin resultado"),
                        tags=('evenrow' if i % 2 == 0 else 'oddrow',))

        tree.tag_configure('evenrow', background=st_cons.get("evenrow", "#181818"))
        tree.tag_configure('oddrow', background=st_cons.get("oddrow", "#222222"))

        scrollbar = ttk.Scrollbar(table_frame, orient="vertical", command=tree.yview)
        tree.configure(yscrollcommand=scrollbar.set)
        tree.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        # --- CAPTURAS DEL DÍA ---
        capturas_label_cfg = diseño["labels"]["capturas"]
        ct.CTkLabel(main_frame,
                    text=capturas_label_cfg["text"],
                    font=tuple(capturas_label_cfg["font"]),
                    text_color=capturas_label_cfg["text_color"],
                    fg_color=capturas_label_cfg.get("fg_color", diseño["window"]["fg_color"])
                ).pack(anchor="w", pady=(10, 5))

        capturas_frame = ct.CTkFrame(main_frame, fg_color=st_cons["background"])
        capturas_frame.pack(fill="both", expand=True, pady=(0, 10))

        columnas_capturas = ("Fecha/Hora", "Usuario", "Código", "Item", "Resultado", "Motivo")
        capturas_tree = ttk.Treeview(capturas_frame, columns=columnas_capturas, show="headings", height=8)

        for col in columnas_capturas:
            capturas_tree.heading(col, text=col)
            capturas_tree.column(col, width=st_cons.get("columns_width", {}).get(col, 100), anchor="center")

        try:
            query = "SELECT fecha, usuario, codigo, item, cumple, motivo FROM capturas WHERE fecha::date = CURRENT_DATE ORDER BY fecha DESC"
            capturas = self.db_manager.execute_query(query)
        except Exception as e:
            capturas = []
            print(f"Error al cargar capturas: {e}")

        for i, c in enumerate(capturas):
            capturas_tree.insert("", "end",
                                values=(c['fecha'], c['usuario'], c['codigo'], c['item'], c['cumple'], c['motivo'] or ""),
                                tags=('evenrow' if i % 2 == 0 else 'oddrow',))

        capturas_tree.tag_configure('evenrow', background=st_cons.get("evenrow", "#181818"))
        capturas_tree.tag_configure('oddrow', background=st_cons.get("oddrow", "#222222"))

        scrollbar2 = ttk.Scrollbar(capturas_frame, orient="vertical", command=capturas_tree.yview)
        capturas_tree.configure(yscrollcommand=scrollbar2.set)
        capturas_tree.pack(side="left", fill="both", expand=True)
        scrollbar2.pack(side="right", fill="y")

        # --- BOTONES ---
        cerrar_cfg = diseño["botones"]["cerrar"]
        cerrar_btn = ct.CTkButton(main_frame,
                                text=cerrar_cfg["text"],
                                command=top.destroy,
                                font=tuple(cerrar_cfg["font"]),
                                fg_color=cerrar_cfg["fg_color"],
                                text_color=cerrar_cfg["text_color"],
                                width=cerrar_cfg["width"],
                                height=cerrar_cfg["height"],
                                corner_radius=cerrar_cfg["corner_radius"],
                                border_width=cerrar_cfg.get("border_width", 0))
        cerrar_btn.pack(pady=10)

    def mostrar_opciones_exportar(self):
        if hasattr(self, 'exportar_frame') and self.exportar_frame.winfo_exists():
            self.exportar_frame.destroy()  # Limpia si ya existe

        self.exportar_frame = ct.CTkFrame(self.master, fg_color="#FFFFFF")
        self.exportar_frame.pack(pady=12)

        diseño = cargar_diseño("theme/historial_dia.json")

        exportar_capturas_cfg = diseño["botones"]["exportar_capturas"]
        exportar_capturas_btn = ct.CTkButton(self.exportar_frame,
                                            text=exportar_capturas_cfg["text"],
                                            font=tuple(exportar_capturas_cfg["font"]),
                                            fg_color=exportar_capturas_cfg["fg_color"],
                                            border_width=exportar_capturas_cfg["border_width"],
                                            border_color=exportar_capturas_cfg["border_color"],
                                            text_color=exportar_capturas_cfg["text_color"],
                                            hover_color=exportar_capturas_cfg["hover_color"],
                                            corner_radius=exportar_capturas_cfg["corner_radius"],
                                            width=exportar_capturas_cfg["width"],
                                            height=exportar_capturas_cfg["height"],
                                            command=self.exportar_capturas_funcion)  # <- tu lógica aquí
        exportar_capturas_btn.pack(pady=exportar_capturas_cfg["pack"].get("pady", (0, 10)))

        exportar_reporte_cfg = diseño["botones"]["exportar_reporte"]
        exportar_reporte_btn = ct.CTkButton(self.exportar_frame,
                                            text=exportar_reporte_cfg["text"],
                                            font=tuple(exportar_reporte_cfg["font"]),
                                            fg_color=exportar_reporte_cfg["fg_color"],
                                            border_width=exportar_reporte_cfg["border_width"],
                                            border_color=exportar_reporte_cfg["border_color"],
                                            text_color=exportar_reporte_cfg["text_color"],
                                            hover_color=exportar_reporte_cfg["hover_color"],
                                            corner_radius=exportar_reporte_cfg["corner_radius"],
                                            width=exportar_reporte_cfg["width"],
                                            height=exportar_reporte_cfg["height"],
                                            command=self.exportar_reporte_funcion)  # <- tu lógica aquí
        exportar_reporte_btn.pack(pady=exportar_reporte_cfg["pack"].get("pady", (0, 10)))

    def _crear_formulario_usuario(self, parent, side="left"):
        diseño = cargar_diseño_formulario("theme/formulario_usuario.json")

        form_conf = diseño["form_frame"]
        form_frame = ct.CTkFrame(parent, fg_color=form_conf["fg_color"])
        form_frame.pack(side=side, fill=form_conf["pack"]["fill"], expand=form_conf["pack"]["expand"], padx=form_conf["pack"]["padx"])

        title = diseño["title_label"]
        ct.CTkLabel(
            form_frame,
            text=title["text"],
            font=tuple(title["font"]),
            text_color=title["text_color"]
        ).pack(pady=title["pack"]["pady"])

        # Variables
        self.usuario_form_var = StringVar()
        self.password_form_var = StringVar()
        self.rol_form_var = StringVar(value="usuario")
        self.activo_form_var = StringVar(value="activo")

        # Usuario
        campo_usuario = diseño["campos"]["usuario"]
        ct.CTkLabel(
            form_frame,
            text=campo_usuario["label"]["text"],
            text_color=campo_usuario["label"]["text_color"]
        ).pack(**campo_usuario["label"]["pack"])
        self.usuario_form_entry = ct.CTkEntry(
            form_frame,
            textvariable=self.usuario_form_var,
            width=campo_usuario["entry"]["width"],
            height=campo_usuario["entry"]["height"]
        )
        self.usuario_form_entry.pack(**campo_usuario["entry"]["pack"])

        # Contraseña
        campo_password = diseño["campos"]["password"]
        ct.CTkLabel(
            form_frame,
            text=campo_password["label"]["text"],
            text_color=campo_password["label"]["text_color"]
        ).pack(**campo_password["label"]["pack"])
        self.password_form_entry = ct.CTkEntry(
            form_frame,
            textvariable=self.password_form_var,
            show=campo_password["entry"]["show"],
            width=campo_password["entry"]["width"],
            height=campo_password["entry"]["height"]
        )
        self.password_form_entry.pack(**campo_password["entry"]["pack"])

        # Rol
        campo_rol = diseño["campos"]["rol"]
        ct.CTkLabel(
            form_frame,
            text=campo_rol["label"]["text"],
            text_color=campo_rol["label"]["text_color"]
        ).pack(**campo_rol["label"]["pack"])
        self.rol_form_menu = ct.CTkOptionMenu(
            form_frame,
            variable=self.rol_form_var,
            values=campo_rol["optionmenu"]["values"],
            width=campo_rol["optionmenu"]["width"],
            height=campo_rol["optionmenu"]["height"]
        )
        self.rol_form_menu.pack(**campo_rol["optionmenu"]["pack"])

        # Estado
        campo_activo = diseño["campos"]["activo"]
        ct.CTkLabel(
            form_frame,
            text=campo_activo["label"]["text"],
            text_color=campo_activo["label"]["text_color"]
        ).pack(**campo_activo["label"]["pack"])
        self.activo_form_menu = ct.CTkOptionMenu(
            form_frame,
            variable=self.activo_form_var,
            values=campo_activo["optionmenu"]["values"],
            width=campo_activo["optionmenu"]["width"],
            height=campo_activo["optionmenu"]["height"]
        )
        self.activo_form_menu.pack(**campo_activo["optionmenu"]["pack"])

        # Botones
        botones_frame_conf = diseño["buttons_frame"]
        buttons_frame = ct.CTkFrame(form_frame, fg_color=botones_frame_conf["fg_color"])
        buttons_frame.pack(**botones_frame_conf["pack"])

        btn_crear = diseño["buttons"]["crear_usuario"]
        ct.CTkButton(
            buttons_frame,
            text=btn_crear["text"],
            command=self.crear_usuario,
            fg_color=btn_crear["fg_color"],
            text_color=btn_crear["text_color"],
            width=btn_crear["width"],
            height=btn_crear["height"]
        ).pack(**btn_crear["pack"])

        btn_limpiar = diseño["buttons"]["limpiar"]
        ct.CTkButton(
            buttons_frame,
            text=btn_limpiar["text"],
            command=self.limpiar_formulario_usuario,
            fg_color=btn_limpiar["fg_color"],
            text_color=btn_limpiar["text_color"],
            width=btn_limpiar["width"],
            height=btn_limpiar["height"]
        ).pack(**btn_limpiar["pack"])

    def _crear_lista_usuarios(self, parent, side="right"):
        diseño = cargar_diseño_lista_usuarios("theme/lista_usuarios.json")

        lf_conf = diseño["list_frame"]
        list_frame = ct.CTkFrame(parent, fg_color=lf_conf["fg_color"])
        list_frame.pack(side=side, fill=lf_conf["pack"]["fill"], expand=lf_conf["pack"]["expand"], padx=lf_conf["pack"]["padx"])

        title = diseño["title_label"]
        ct.CTkLabel(
            list_frame,
            text=title["text"],
            font=tuple(title["font"]),
            text_color=title["text_color"]
        ).pack(pady=title["pack"]["pady"])

        # Frame para tabla
        tf_conf = diseño["table_frame"]
        table_frame = ct.CTkFrame(list_frame, fg_color=tf_conf["fg_color"])
        table_frame.pack(fill=tf_conf["pack"]["fill"], expand=tf_conf["pack"]["expand"], padx=tf_conf["pack"]["padx"], pady=tf_conf["pack"]["pady"])

        # Crear Treeview
        tree_conf = diseño["treeview"]
        columns = tree_conf["columns"]
        self.usuarios_tree = ttk.Treeview(table_frame, columns=columns, show=tree_conf["show"], height=tree_conf["height"])

        for col in columns:
            self.usuarios_tree.heading(col, text=col)
            cfg = tree_conf["columns_config"][col]
            self.usuarios_tree.column(col, width=cfg["width"], anchor=cfg["anchor"])

        # Configurar estilo ttk
        style = ttk.Style()
        style.theme_use('default')
        style.configure("Treeview",
                        background=tree_conf["style"]["background"],
                        foreground=tree_conf["style"]["foreground"],
                        rowheight=tree_conf["style"]["rowheight"],
                        fieldbackground=tree_conf["style"]["fieldbackground"])
        style.configure("Treeview.Heading",
                        background=tree_conf["style"]["heading_background"],
                        foreground=tree_conf["style"]["heading_foreground"],
                        font=tuple(tree_conf["style"]["heading_font"]))
        style.map('Treeview', background=[('selected', tree_conf["style"]["selected_background"])])

        # Scrollbar
        scrollbar = ttk.Scrollbar(table_frame, orient="vertical", command=self.usuarios_tree.yview)
        self.usuarios_tree.configure(yscrollcommand=scrollbar.set)
        self.usuarios_tree.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        self.cargar_usuarios()

        self.usuarios_tree.bind("<<TreeviewSelect>>", self.on_usuario_select)

        # Botones
        af_conf = diseño["action_frame"]
        action_frame = ct.CTkFrame(list_frame, fg_color=af_conf["fg_color"])
        action_frame.pack(pady=af_conf["pack"]["pady"])

        btns = diseño["buttons"]

        ct.CTkButton(
            action_frame,
            text=btns["eliminar_usuario"]["text"],
            command=self.eliminar_usuario,
            fg_color=btns["eliminar_usuario"]["fg_color"],
            text_color=btns["eliminar_usuario"]["text_color"],
            width=btns["eliminar_usuario"]["width"],
            height=btns["eliminar_usuario"]["height"]
        ).pack(**btns["eliminar_usuario"]["pack"])

        ct.CTkButton(
            action_frame,
            text=btns["cambiar_estado"]["text"],
            command=self.cambiar_estado_usuario,
            fg_color=btns["cambiar_estado"]["fg_color"],
            text_color=btns["cambiar_estado"]["text_color"],
            width=btns["cambiar_estado"]["width"],
            height=btns["cambiar_estado"]["height"]
        ).pack(**btns["cambiar_estado"]["pack"])

        ct.CTkButton(
            action_frame,
            text=btns["refrescar"]["text"],
            command=self.cargar_usuarios,
            fg_color=btns["refrescar"]["fg_color"],
            text_color=btns["refrescar"]["text_color"],
            width=btns["refrescar"]["width"],
            height=btns["refrescar"]["height"]
        ).pack(**btns["refrescar"]["pack"])

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
    

        """Cierra la sesión y regresa a la pantalla de login"""
        try:
            self.master.destroy()
            app = EscanerApp()
            app.ejecutar()
        except Exception as e:
            print(f"Error al cerrar sesión: {str(e)}")

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
        diseño = cargar_diseño("theme/tab_captura.json")

        main_frame_conf = diseño["main_frame"]
        main_frame = ct.CTkScrollableFrame(parent, fg_color=main_frame_conf["fg_color"],
                                        width=main_frame_conf["width"], height=main_frame_conf["height"])
        main_frame.pack(fill="both", expand=True, padx=main_frame_conf["padx"], pady=main_frame_conf["pady"])

        # Título
        label_conf = diseño["labels"]["titulo"]
        ct.CTkLabel(
            main_frame,
            text=label_conf["text"],
            font=tuple(label_conf["font"]),
            text_color=label_conf["text_color"]
        ).pack(pady=tuple(label_conf["pady"]))

        # Botón subir capturas pendientes
        if self.rol in ["admin", "captura"]:
            btn_conf = diseño["buttons"]["subir_pendientes"]
            self.subir_pendientes_btn = ct.CTkButton(
                main_frame,
                text=btn_conf["text"],
                command=self.subir_capturas_offline,
                font=tuple(btn_conf["font"]),
                fg_color=btn_conf["fg_color"],
                text_color=btn_conf["text_color"],
                border_width=btn_conf["border_width"],
                border_color=btn_conf["border_color"],
                corner_radius=btn_conf["corner_radius"]
            )
            self.subir_pendientes_btn.pack(pady=tuple(btn_conf["pady"]))
            self._actualizar_estado_pendientes()

        # Variables
        self.codigo_captura_var = StringVar()
        self.item_captura_var = StringVar()
        self.motivo_captura_var = StringVar(value="Instrucciones de cuidado")
        self.cumple_captura_var = StringVar(value="NO CUMPLE")

        frame_conf = diseño["frame"]
        campos_frame = ct.CTkFrame(main_frame, fg_color=frame_conf["fg_color"])
        campos_frame.pack(fill="x", pady=tuple(frame_conf["pady_campos"]))

        # Código de barras label y entry
        label_cb_conf = diseño["labels"]["codigo_barras"]
        ct.CTkLabel(
            campos_frame,
            text=label_cb_conf["text"],
            font=tuple(label_cb_conf["font"]),
            text_color=label_cb_conf["text_color"]
        ).pack(anchor=label_cb_conf["anchor"], padx=label_cb_conf["padx"], pady=tuple(label_cb_conf["pady"]))

        entry_conf = diseño["entries"]
        self.codigo_captura_entry = ct.CTkEntry(
            campos_frame,
            textvariable=self.codigo_captura_var,
            font=tuple(entry_conf["font"]),
            width=entry_conf["width"],
            height=entry_conf["height"],
            corner_radius=entry_conf["corner_radius"],
            border_width=entry_conf["border_width"],
            border_color=entry_conf["border_color"],
            fg_color=entry_conf["fg_color"],
            text_color=entry_conf["text_color"]
        )
        self.codigo_captura_entry.pack(fill="x", padx=10, pady=(0, 8))
        self.codigo_captura_entry.bind("<Return>", lambda e: self._buscar_item_automatico())

        # Item label y entry
        label_item_conf = diseño["labels"]["item"]
        ct.CTkLabel(
            campos_frame,
            text=label_item_conf["text"],
            font=tuple(label_item_conf["font"]),
            text_color=label_item_conf["text_color"]
        ).pack(anchor=label_item_conf["anchor"], padx=label_item_conf["padx"], pady=tuple(label_item_conf["pady"]))

        self.item_captura_entry = ct.CTkEntry(
            campos_frame,
            textvariable=self.item_captura_var,
            font=tuple(entry_conf["font"]),
            width=entry_conf["width"],
            height=entry_conf["height"],
            corner_radius=entry_conf["corner_radius"],
            border_width=entry_conf["border_width"],
            border_color=entry_conf["border_color"],
            fg_color=entry_conf["fg_color"],
            text_color=entry_conf["text_color"]
        )
        self.item_captura_entry.pack(fill="x", padx=10, pady=(0, 8))

        # ¿Cumple? label y OptionMenu
        label_cumple_conf = diseño["labels"]["cumple"]
        ct.CTkLabel(
            campos_frame,
            text=label_cumple_conf["text"],
            font=tuple(label_cumple_conf["font"]),
            text_color=label_cumple_conf["text_color"]
        ).pack(anchor=label_cumple_conf["anchor"], padx=label_cumple_conf["padx"], pady=tuple(label_cumple_conf["pady"]))

        optionmenu_conf = diseño["optionmenu"]
        self.cumple_captura_menu = ct.CTkOptionMenu(
            campos_frame,
            variable=self.cumple_captura_var,
            values=["CUMPLE", "NO CUMPLE"],
            fg_color=optionmenu_conf["fg_color"],
            text_color=optionmenu_conf["text_color"],
            font=tuple(optionmenu_conf["font"]),
            width=optionmenu_conf["width"],
            height=optionmenu_conf["height"]
        )
        self.cumple_captura_menu.pack(fill="x", padx=10, pady=(0, 8))

        # Frame motivo y botón guardar
        motivo_guardar_frame = ct.CTkFrame(campos_frame, fg_color=frame_conf["fg_color"])
        motivo_guardar_frame.pack(fill="x", pady=tuple(frame_conf["pady_motivo_guardar"]))

        # Motivo label y OptionMenu
        motivo_label_conf = diseño["labels"]["motivo"]
        self.motivo_label = ct.CTkLabel(
            motivo_guardar_frame,
            text=motivo_label_conf["text"],
            font=tuple(motivo_label_conf["font"]),
            text_color=motivo_label_conf["text_color"]
        )
        self.motivo_label.pack(anchor=motivo_label_conf["anchor"], padx=motivo_label_conf["padx"], pady=tuple(motivo_label_conf["pady"]))

        motivo_options = [
            "Instrucciones de cuidado",
            "Insumos",
            "Pais de origen",
            "Talla",
            "Importador",
            "Marca"
        ]
        self.motivo_captura_var.set(motivo_options[0])
        self.motivo_captura_menu = ct.CTkOptionMenu(
            motivo_guardar_frame,
            variable=self.motivo_captura_var,
            values=motivo_options,
            fg_color=optionmenu_conf["fg_color"],
            text_color=optionmenu_conf["text_color"],
            font=tuple(optionmenu_conf["font"]),
            width=optionmenu_conf["width"],
            height=optionmenu_conf["height"]
        )
        self.motivo_captura_menu.pack(fill="x", padx=10, pady=(0, 8))

        # Lógica para habilitar/deshabilitar motivo según cumple
        def on_cumple_change(*args):
            if self.cumple_captura_var.get() == "NO CUMPLE":
                self.motivo_captura_menu.configure(state="normal", text_color="#00FFAA")
                self.motivo_label.configure(text_color="#00FFAA")
            else:
                self.motivo_captura_menu.configure(state="disabled", text_color="#888888")
                self.motivo_label.configure(text_color="#888888")

        self.cumple_captura_var.trace_add('write', on_cumple_change)
        on_cumple_change()

        # Botón guardar
        guardar_btn_conf = diseño["buttons"]["guardar"]
        self.guardar_btn = ct.CTkButton(
            motivo_guardar_frame,
            text=guardar_btn_conf["text"],
            command=self.guardar_captura_offline,
            font=tuple(guardar_btn_conf["font"]),
            fg_color=guardar_btn_conf["fg_color"],
            text_color=guardar_btn_conf["text_color"],
            border_width=guardar_btn_conf["border_width"],
            border_color=guardar_btn_conf["border_color"],
            corner_radius=guardar_btn_conf["corner_radius"]
        )
        self.guardar_btn.pack(pady=tuple(guardar_btn_conf["pady"]))

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
        # Guardar en historial de capturas, divividido por usuarios porque me gusta ver el mundo arder
        self.codigo_model.db.execute_query(
            "INSERT INTO capturas (codigo, item, motivo, cumple, usuario, fecha) VALUES (%s, %s, %s, %s, %s, NOW())",
            (codigo, item, motivo, cumple, self.usuario), fetch=False)
        messagebox.showinfo("Éxito", "Captura guardada y actualizada en ítems")
        self.codigo_captura_var.set("")
        self.item_captura_var.set("")
        self.codigo_captura_entry.focus_set()
   
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
  
    #Ventana para configurar la carga de archivos CLP
    def _configurar_tab_configuracion(self, parent):
        diseño = cargar_diseño("theme/tab_configuracion.json")

        main_frame_conf = diseño["main_frame"]
        main_frame = ct.CTkFrame(parent, fg_color=main_frame_conf["fg_color"])
        main_frame.pack(**main_frame_conf["pack"])

        title_conf = diseño["title_label"]
        ct.CTkLabel(
            main_frame,
            text=title_conf["text"],
            font=tuple(title_conf["font"]),
            text_color=title_conf["text_color"]
        ).pack(**title_conf["pack"])

        archivos_frame_conf = diseño["archivos_frame"]
        archivos_frame = ct.CTkFrame(main_frame, fg_color=archivos_frame_conf["fg_color"])
        archivos_frame.pack(**archivos_frame_conf["pack"])

        archivos_label_conf = diseño["archivos_label"]
        ct.CTkLabel(
            archivos_frame,
            text=archivos_label_conf["text"],
            font=tuple(archivos_label_conf["font"]),
            text_color=archivos_label_conf["text_color"]
        ).pack(**archivos_label_conf["pack"])

        self.rutas_clp_var = StringVar(value="No hay archivos seleccionados")
        rutas_clp_label_conf = diseño["rutas_clp_label"]
        self.rutas_clp_label = ct.CTkLabel(
            archivos_frame,
            textvariable=self.rutas_clp_var,
            text_color=rutas_clp_label_conf["text_color"],
            wraplength=rutas_clp_label_conf["wraplength"],
            fg_color=rutas_clp_label_conf["fg_color"]
        )
        self.rutas_clp_label.pack(**rutas_clp_label_conf["pack"])

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

        btn_sel_conf = diseño["botones"]["seleccionar_archivos"]
        ct.CTkButton(
            archivos_frame,
            text=btn_sel_conf["text"],
            command=seleccionar_archivos,
            font=tuple(btn_sel_conf["font"]),
            fg_color=btn_sel_conf["fg_color"],
            hover_color=btn_sel_conf["hover_color"],
            border_width=btn_sel_conf["border_width"],
            border_color=btn_sel_conf["border_color"],
            text_color=btn_sel_conf["text_color"],
            corner_radius=btn_sel_conf["corner_radius"],
            width=btn_sel_conf["width"],
            height=btn_sel_conf["height"]
        ).pack(**btn_sel_conf["pack"])

        def cargar_archivos_clp():
            if not hasattr(self, "rutas_clp") or not self.rutas_clp:
                messagebox.showerror("Error", "No hay archivos CLP seleccionados.")
                return
            resultado = self.codigo_model.cargar_varios_clp(self.rutas_clp, self.usuario)
            if not isinstance(resultado, dict):
                resultado = {'procesados': 0, 'nuevos_items': 0, 'nuevos_codigos': 0, 'clp_registros': []}
            mensaje = (f"Carga completada.\n"
                    f"Nuevos items: {resultado.get('nuevos_items', 0)}\n"
                    f"Nuevos códigos: {resultado.get('nuevos_codigos', 0)}\n"
                    f"Total procesados: {resultado.get('procesados', 0)}")
            messagebox.showinfo("Éxito", mensaje)
            self.rutas_clp_var.set("No hay archivos seleccionados")
            self.rutas_clp = []
            self.cargar_estadisticas()

        btn_cargar_conf = diseño["botones"]["cargar_archivos_clp"]
        ct.CTkButton(
            archivos_frame,
            text=btn_cargar_conf["text"],
            command=cargar_archivos_clp,
            font=tuple(btn_cargar_conf["font"]),
            fg_color=btn_cargar_conf["fg_color"],
            text_color=btn_cargar_conf["text_color"],
            border_width=btn_cargar_conf["border_width"],
            border_color=btn_cargar_conf["border_color"],
            corner_radius=btn_cargar_conf["corner_radius"],
            width=btn_cargar_conf["width"],
            height=btn_cargar_conf["height"]
        ).pack(**btn_cargar_conf["pack"])

    #Ventana para exportar reporte de consultas del día
    def exportar_reporte_dia(self):
        import tkinter as tk
        from tkinter import messagebox, filedialog
        from tkcalendar import DateEntry
        import pandas as pd

        diseño = cargar_diseño("theme/exportar_reporte_dia.json")

        top = tk.Toplevel(self.master)
        top.title(diseño["window"]["title"])
        top.geometry(diseño["window"]["geometry"])
        top.configure(bg=diseño["window"]["bg"])

        # Label principal
        label_conf = diseño["label"]
        label = tk.Label(
            top,
            text=label_conf["text"],
            font=tuple(label_conf["font"]),
            fg=label_conf["fg"],
            bg=label_conf["bg"]
        )
        label.pack(**label_conf["pack"])

        cal = None
        if DateEntry:
            cal_conf = diseño["calendar"]
            cal = DateEntry(
                top,
                width=cal_conf["width"],
                background=cal_conf["background"],
                foreground=cal_conf["foreground"],
                borderwidth=cal_conf["borderwidth"],
                date_pattern=cal_conf["date_pattern"],
                font=tuple(cal_conf["font"]),
                headersbackground=cal_conf["headersbackground"],
                headersforeground=cal_conf["headersforeground"],
                selectbackground=cal_conf["selectbackground"],
                selectforeground=cal_conf["selectforeground"]
            )
            cal.pack(**cal_conf["pack"])
        else:
            lw_conf = diseño["label_warning"]
            tk.Label(
                top,
                text=lw_conf["text"],
                fg=lw_conf["fg"],
                bg=lw_conf["bg"],
                font=tuple(lw_conf["font"])
            ).pack(**lw_conf["pack"])

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

        # Botón de exportar (fuera de la función exportar)
        btn_conf = diseño["button"]
        export_btn = tk.Button(
            top,
            text=btn_conf["text"],
            font=tuple(btn_conf["font"]),
            bg=btn_conf["bg"],
            fg=btn_conf["fg"],
            activebackground=btn_conf["activebackground"],
            activeforeground=btn_conf["activeforeground"],
            relief=btn_conf["relief"],
            borderwidth=btn_conf["borderwidth"],
            width=btn_conf["width"],
            height=btn_conf["height"],
            command=exportar
        )
        export_btn.pack(**btn_conf["pack"])

    #Ventana para exportar capturas del día
    def exportar_capturas_dia(self):
        import tkinter as tk
        from tkinter import filedialog, messagebox
        from tkcalendar import DateEntry
        import pandas as pd

        diseño = cargar_diseño("theme/exportar_capturas_dia.json")

        # Ventana principal
        top = tk.Toplevel(self.master)
        top.title(diseño["window"]["title"])
        top.geometry(diseño["window"]["geometry"])
        top.configure(bg=diseño["window"]["bg"])

        # Etiqueta
        label_conf = diseño["label"]
        label = tk.Label(
            top,
            text=label_conf["text"],
            font=tuple(label_conf["font"]),
            fg=label_conf["fg"],
            bg=label_conf["bg"]
        )
        label.pack(**label_conf["pack"])

        # Calendario o advertencia
        if DateEntry:
            cal_conf = diseño["calendar"]
            cal = DateEntry(
                top,
                width=cal_conf["width"],
                background=cal_conf["background"],
                foreground=cal_conf["foreground"],
                borderwidth=cal_conf["borderwidth"],
                date_pattern=cal_conf["date_pattern"],
                font=tuple(cal_conf["font"]),
                headersbackground=cal_conf["headersbackground"],
                headersforeground=cal_conf["headersforeground"],
                selectbackground=cal_conf["selectbackground"],
                selectforeground=cal_conf["selectforeground"]
            )
            cal.pack(**cal_conf["pack"])
        else:
            warn_conf = diseño["label_warning"]
            tk.Label(
                top,
                text=warn_conf["text"],
                fg=warn_conf["fg"],
                bg=warn_conf["bg"],
                font=tuple(warn_conf["font"])
            ).pack(**warn_conf["pack"])
            cal = None

        # Acción exportar
        def exportar():
            fecha = cal.get_date().strftime('%Y-%m-%d') if cal else None
            if not fecha:
                messagebox.showerror("Error", "Selecciona una fecha válida.")
                return
            try:
                query = "SELECT fecha, usuario, codigo, item, cumple, motivo FROM capturas WHERE fecha::date = %s ORDER BY fecha DESC"
                capturas = self.db_manager.execute_query(query, (fecha,))
            except Exception:
                capturas = []
            if not capturas:
                messagebox.showinfo("Sin datos", f"No hay capturas para el día {fecha}")
                return
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

        # Botón exportar
        btn_conf = diseño["button"]
        export_btn = tk.Button(
            top,
            text=btn_conf["text"],
            command=exportar,
            font=tuple(btn_conf["font"]),
            bg=btn_conf["bg"],
            fg=btn_conf["fg"],
            activebackground=btn_conf["activebackground"],
            activeforeground=btn_conf["activeforeground"],
            relief=btn_conf["relief"],
            borderwidth=btn_conf["borderwidth"],
            width=btn_conf["width"],
            height=btn_conf["height"],
            padx=btn_conf["padx"],
            pady=btn_conf["pady"]
        )
        export_btn.pack(**btn_conf["pack"])

    # Botón cerrar sesión (logout)
    def cerrar_sesion(self):
        """Cierra la sesión y regresa a la pantalla de login"""
        try:
            self.logger.log_user_action(self.usuario, "Cerrar sesión")
            self.master.destroy()
            app = EscanerApp()
            app.ejecutar()
        except Exception as e:
            print(f"Error al cerrar sesión: {str(e)}")

if __name__ == "__main__":
    app = EscanerApp()
    app.ejecutar()