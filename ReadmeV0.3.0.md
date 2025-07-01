# Escáner de Códigos V&C v3.0.0

## Descripción
Aplicación profesional para escaneo y gestión de códigos de barras, con base de datos PostgreSQL, sistema de histórico automático y actualizaciones.

---

## Características Principales

- **Base de datos PostgreSQL**: Toda la información se almacena de forma segura y centralizada.
- **Carga de CLP**: Permite cargar archivos CLP (Excel) para actualizar la relación código ↔ item ↔ resultado.
- **Histórico automático**: El resultado de cada item se toma automáticamente de un archivo histórico fijo, sin intervención manual.
- **Captura de datos**: Registro de cumplimientos, motivos y usuarios, con persistencia y exportación a Excel.
- **Autenticación**: Solo usuarios registrados pueden acceder. Usuario admin por defecto: `admin` / `admin123`.
- **Actualizaciones automáticas**: Sistema preparado para recibir actualizaciones del software.
- **Sin opción de borrar la base de datos**: Solo el administrador del servidor puede hacerlo manualmente.

---

## Instalación y Primer Uso

### 1. Requisitos
- **Python 3.8+**
- **PostgreSQL** instalado y corriendo
- Paquetes Python: ver `requirements.txt`

### 2. Configuración de la base de datos
1. Crea la base de datos en PostgreSQL:
   ```sql
   CREATE DATABASE Escaner;
   ```
2. Configura las credenciales en `config/database.py`:
   ```python
   self.config = {
       "host": "localhost",
       "port": 5432,
       "user": "postgres",
       "password": "TU_PASSWORD",
       "database": "Escaner"
   }
   ```

### 3. Instalación de dependencias
```bash
pip install -r requirements.txt
```

### 4. Primer inicio
```bash
python Escaner_V3.0.0.py
```

---

## Uso de la aplicación

### 1. **Login**
- Ingresa con el usuario `admin` y contraseña `admin123` (puedes crear más usuarios desde la pestaña de configuración).

### 2. **Carga de CLP**
- Ve a la pestaña **Configuración**.
- Carga el archivo CLP (Excel) con la relación código ↔ item.
- El sistema automáticamente relaciona cada item con su resultado usando el histórico fijo (`MODELOS CUMPLIENDO (004).xlsx`).
- No es necesario cargar el histórico manualmente.

### 3. **Escaneo**
- Ve a la pestaña **Escáner**.
- Ingresa o escanea un código de barras.
- El sistema muestra el item y el resultado actual.

### 4. **Captura de datos**
- Ve a la pestaña **Captura de Datos**.
- Registra cumplimientos, motivos y usuario.
- Los datos se guardan en la base de datos y pueden exportarse a Excel.

### 5. **Actualizaciones**
- La aplicación está preparada para recibir actualizaciones automáticas (requiere configuración de servidor).

---

## Seguridad y administración
- **No existe opción de borrar la base de datos desde la app**.
- Solo el administrador del servidor puede eliminar datos directamente en PostgreSQL.
- Los usuarios pueden ser gestionados desde la pestaña de configuración (solo admin).

---

## Notas técnicas
- El histórico se toma siempre de la ruta fija: `C:/Users/bost2/OneDrive/Escritorio/MODELOS CUMPLIENDO (004).xlsx`.
- El CLP puede ser cualquier archivo Excel compatible.
- El sistema es robusto ante errores y muestra mensajes claros al usuario.

---

## Soporte
Para dudas o soporte, contactar al desarrollador principal (admin del sistema). 
