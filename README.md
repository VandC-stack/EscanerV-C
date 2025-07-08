# Aplicación SQL

Aplicación de gestión y escaneo de códigos de barras con base de datos SQL.

## Características

- Escaneo y registro de códigos de barras e ítems.
- Gestión de usuarios y permisos.
- Exportación de capturas a Excel.
- Estadísticas y reportes.
- Interfaz gráfica intuitiva.
- Registro de consultas y operaciones.

## Estructura del Proyecto

- `config/` — Configuración de la base de datos.
- `models/` — Modelos de datos y lógica de negocio.
- `utils/` — Utilidades y validaciones.
- `resources/` — Imágenes y recursos gráficos.
- `logs/` — Archivos de registro.
- Archivos principales `.py` — Scripts de ejecución y utilidades.

## Instalación

1. Clona el repositorio:
   ```bash
   git clone https://github.com/VandC-stack/EscanerV-C.git
   ```
2. Instala las dependencias:
   ```bash
   pip install -r requirements.txt
   ```
3. Configura la base de datos en `config/database.py`.

## Uso

- Ejecuta la aplicación principal:
  ```bash
  python Escaner_V0.3.2.py
  ```
- Sigue las instrucciones en pantalla para iniciar sesión y comenzar a usar la aplicación.

## Personalización

- Puedes modificar los recursos gráficos en la carpeta `resources/`.
- Ajusta la configuración de la base de datos en `config/database.py`.

## Soporte

Para reportar errores o solicitar nuevas funciones, abre un [issue](https://github.com/VandC-stack/EscanerV-C/issues) en GitHub.

## Licencia

Este proyecto está bajo la licencia MIT.
