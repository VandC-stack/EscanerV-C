¡Por supuesto! Aquí tienes un README básico para tu aplicación y, aparte, un comando SQL para crear las tablas principales necesarias para que funcione correctamente.

---

## 📖 README — Escáner de Códigos V&C

### Descripción
Aplicación de escritorio desarrollada en Python con CustomTkinter para la gestión y captura de códigos de barras, usuarios y cumplimiento de ítems. Permite diferentes niveles de usuario (superadmin, admin, captura, usuario) y funcionalidades avanzadas de administración, escaneo, captura y control de base de datos.

### Características principales
- **Login seguro** con roles y contraseñas hasheadas.
- **Gestión de usuarios** (crear, eliminar, restablecer contraseña, ver roles).
- **Escaneo de códigos de barras** y consulta de resultados.
- **Captura de datos** con validación de cumplimiento y motivos.
- **Procesamiento de histórico** y actualización de base de datos.
- **Exportación de capturas** a Excel.
- **Panel de administración** para superadmin.
- **Interfaz moderna** y adaptable.

### Requisitos
- Python 3.8 o superior
- Paquetes: customtkinter, pillow, pandas, openpyxl

Instala los requisitos con:
```bash
pip install customtkinter pillow pandas openpyxl
```

### Ejecución
```bash
python "Aplicacion/Aplicacion SQL/Escaner_V0.3.0.py"
```

### Estructura de carpetas relevante
- `Aplicacion/Aplicacion SQL/` — Código principal y módulos.
- `config/database.py` — Conexión y gestión de la base de datos.
- `models/` — Modelos de usuario, código, captura.
- `utils/` — Utilidades y validadores.

---

## 🗄️ Comando SQL para crear las tablas necesarias

A continuación, un ejemplo de los comandos SQL para crear las tablas principales: `usuarios`, `codigos_items`, `capturas`, y `configuracion`.

```sql
-- Tabla de usuarios
CREATE TABLE IF NOT EXISTS usuarios (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    usuario TEXT UNIQUE NOT NULL,
    contraseña TEXT NOT NULL,
    rol TEXT NOT NULL,
    activo INTEGER DEFAULT 1,
    fecha_creacion TEXT DEFAULT (datetime('now', 'localtime'))
);

-- Tabla de códigos e ítems
CREATE TABLE IF NOT EXISTS codigos_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    codigo TEXT NOT NULL,
    item TEXT NOT NULL,
    resultado TEXT,
    fecha_actualizacion TEXT,
    UNIQUE(codigo, item)
);

-- Tabla de capturas
CREATE TABLE IF NOT EXISTS capturas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    codigo TEXT NOT NULL,
    item TEXT NOT NULL,
    motivo TEXT,
    cumple TEXT NOT NULL,
    usuario TEXT NOT NULL,
    fecha_captura TEXT DEFAULT (datetime('now', 'localtime')),
    estado TEXT DEFAULT 'pendiente'
);

-- Tabla de configuración
CREATE TABLE IF NOT EXISTS configuracion (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    clave TEXT UNIQUE NOT NULL,
    valor TEXT,
    descripcion TEXT
);
```

> **Nota:**  
> - Si usas SQLite, estos comandos funcionarán directamente.  
> - Si usas otro motor de base de datos, puede que necesites ajustar los tipos de datos o funciones de fecha.

---

¿Te gustaría que te agregue ejemplos de inserción de datos por defecto (como el usuario admin) o alguna tabla adicional?
