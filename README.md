# Gestor de Códigos de Barras

Aplicación de escritorio desarrollada en Python para la gestión integral de códigos de barras, items y cumplimiento de estándares. Permite cargar archivos CLP (Excel), consultar códigos de barras y registrar el estado de cumplimiento con motivos asociados.

## Características Principales

- **Carga de Archivos CLP**: Importa archivos Excel con códigos de barras e items
- **Consulta de Códigos**: Búsqueda rápida de códigos de barras y su información asociada
- **Gestión de Cumplimiento**: Registro de estado "CUMPLE"/"NO CUMPLE" con motivos
- **Base de Datos Centralizada**: Almacenamiento persistente de todos los datos
- **Historial de Actividades**: Registro de consultas y cargas de archivos
- **Interfaz Intuitiva**: Diseño moderno con CustomTkinter

## Requisitos del Sistema

- Python 3.8 o superior
- Windows 10/11
- 4GB RAM mínimo
- 500MB espacio en disco

## Instalación

1. **Clonar el repositorio**:
   ```bash
   git clone [URL_DEL_REPOSITORIO]
   cd Codigos
   ```

2. **Instalar dependencias**:
   ```bash
   pip install -r requirements.txt
   ```

3. **Configurar la base de datos**:
   - La aplicación creará automáticamente la base de datos SQLite en la primera ejecución
   - Los archivos se almacenan en la carpeta `Aplicacion/Aplicacion SQL/`

## Uso de la Aplicación

### Inicio
```bash
cd Aplicacion/Aplicacion SQL
python Escaner_V0.3.2.py
```

### Funcionalidades

#### 1. Carga de Archivos CLP
- Selecciona archivos Excel (.xlsx) con formato específico
- Columna A: Item
- Columna F: Código de barras
- La aplicación suma nuevos códigos sin sobrescribir existentes

#### 2. Consulta de Códigos
- Ingresa un código de barras para buscar
- Visualiza información del item asociado
- Revisa historial de consultas

#### 3. Captura de Cumplimiento
- Registra estado de cumplimiento
- Asigna motivos para casos "NO CUMPLE"
- Guarda en base de datos centralizada

## Estructura de la Base de Datos

### Tablas Principales

- **items**: Información de productos/items
- **codigos_barras**: Códigos de barras asociados a items
- **consultas**: Historial de búsquedas realizadas
- **clp_cargas**: Registro de archivos CLP cargados

### Relaciones
- Un item puede tener múltiples códigos de barras
- Cada código de barras pertenece a un solo item
- Consultas y cargas se registran con timestamp

## Estructura del Proyecto

```
Aplicacion/
├── Aplicacion SQL/
│   ├── Escaner_V0.3.2.py       # Aplicación principal
│   ├── config/
│   │   └── database.py         # Configuración de BD
│   ├── models/                 # Modelos de datos
│   ├── services/               # Lógica de negocio
│   ├── utils/                  # Utilidades
│   └── resources/              # Recursos (iconos, etc.)
├── requirements.txt            # Dependencias Python
└── README.md                   # Este archivo
```

## Configuración

### Variables de Entorno
- La aplicación utiliza SQLite por defecto
- Los logs se guardan en `logs/`
- Configuración de base de datos en `config/database.py`

### Personalización
- Modifica `resources/` para cambiar iconos
- Ajusta validaciones en `utils/validators.py`
- Personaliza logs en `utils/logger.py`

## Funcionalidades Técnicas

- **Validación de Datos**: Verificación de formatos y consistencia
- **Logging**: Registro detallado de operaciones
- **Manejo de Errores**: Gestión robusta de excepciones
- **Interfaz Responsiva**: Adaptable a diferentes resoluciones
- **Persistencia de Datos**: Almacenamiento confiable en SQLite

## Soporte

Para reportar problemas o solicitar nuevas funcionalidades:
- Crear un issue en el repositorio
- Incluir información del sistema y pasos para reproducir
- Adjuntar logs si es necesario

## Licencia

Este proyecto es de uso interno y privado.

## Créditos

Desarrollado con:
- Python 3.x
- CustomTkinter
- SQLite3
- Pandas (para manejo de Excel)

---

**Versión**: 0.3.2  
**Última actualización**: Julio 2024
