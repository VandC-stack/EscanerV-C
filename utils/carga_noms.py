import pandas as pd
from tkinter import filedialog, messagebox
import customtkinter as ct

class ColumnasPopup(ct.CTkToplevel):
    def __init__(self, parent, columnas):
        super().__init__(parent)
        self.title("Selecciona las columnas")
        self.geometry("420x220")
        self.resizable(False, False)
        self.result = None
        ct.CTkLabel(self, text="Selecciona la columna de Ítem:", font=("Segoe UI", 14, "bold"), text_color="#00FFAA").pack(pady=(18, 4))
        self.var_item = ct.StringVar(value=columnas[0] if columnas else "")
        self.menu_item = ct.CTkOptionMenu(self, variable=self.var_item, values=columnas, width=340, fg_color="#000000", text_color="#00FFAA", font=("Segoe UI", 13))
        self.menu_item.pack(pady=(0, 10))
        ct.CTkLabel(self, text="Selecciona la columna de NOM:", font=("Segoe UI", 14, "bold"), text_color="#00FFAA").pack(pady=(0, 4))
        self.var_nom = ct.StringVar(value=columnas[0] if columnas else "")
        self.menu_nom = ct.CTkOptionMenu(self, variable=self.var_nom, values=columnas, width=340, fg_color="#000000", text_color="#00FFAA", font=("Segoe UI", 13))
        self.menu_nom.pack(pady=(0, 16))
        btn = ct.CTkButton(self, text="Aceptar", command=self._aceptar, fg_color="#00FFAA", text_color="#000000", font=("Segoe UI", 13, "bold"), width=120)
        btn.pack(pady=(0, 10))
        self.bind("<Return>", lambda e: self._aceptar())
        self.grab_set()
        self.focus_force()
        self.wait_window()
    def _aceptar(self):
        self.result = (self.var_item.get(), self.var_nom.get())
        self.destroy()

def cargar_noms_embarque(db_manager):
    """
    Permite al usuario cargar un archivo de NOMs, seleccionar columnas y embarque,
    e inserta los datos en la tabla item_nom_embarque.
    """
    # 1. Seleccionar archivo
    file_path = filedialog.askopenfilename(
        title="Selecciona el reporte de NOMs",
        filetypes=[("Archivos Excel", "*.xlsx *.xls"), ("Archivos CSV", "*.csv"), ("Todos los archivos", "*.*")]
    )
    if not file_path:
        return

    # 2. Leer archivo
    try:
        if file_path.endswith((".xlsx", ".xls")):
            df = pd.read_excel(file_path)
        else:
            df = pd.read_csv(file_path)
    except Exception as e:
        messagebox.showerror("Error", f"No se pudo leer el archivo: {e}")
        return

    columnas = list(df.columns)
    root = None
    try:
        import tkinter
        root = tkinter._default_root
    except Exception:
        pass
    # 3. Seleccionar columnas Ítem y NOM en un solo popup
    dlg = ColumnasPopup(root, columnas)
    if not dlg.result or dlg.result[0] not in columnas or dlg.result[1] not in columnas:
        messagebox.showerror("Error", "Debes seleccionar columnas válidas.")
        return
    col_item, col_nom = dlg.result
    # 4. Preguntar embarque (CTkInputDialog)
    embarque = ct.CTkInputDialog(text="Ingresa el nombre del embarque (contenedor):", title="Embarque").get_input()
    if not embarque:
        messagebox.showerror("Error", "Debes ingresar el nombre del embarque.")
        return
    # 5. Insertar en la base de datos
    insertados = 0
    try:
        for _, row in df.iterrows():
            item_id = str(row[col_item]).strip()
            nom = str(row[col_nom]).strip()
            if not item_id or not nom:
                continue
            try:
                db_manager.execute_query(
                    "INSERT INTO item_nom_embarque (item_id, nom, embarque) VALUES (%s, %s, %s) ON CONFLICT (item_id, nom, embarque) DO NOTHING",
                    (item_id, nom, embarque),
                    fetch=False
                )
                insertados += 1
            except Exception as e:
                print(f"Error insertando {item_id}-{nom}: {e}")
        messagebox.showinfo("Carga completada", f"Se insertaron {insertados} registros de NOMs para el embarque {embarque}.")
    except Exception as e:
        messagebox.showerror("Error", f"Error al insertar en la base de datos: {e}") 