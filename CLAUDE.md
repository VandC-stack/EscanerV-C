# Diagrama de Flujo del Funcionamiento de la Aplicación Escaner_V0.3.2

Este reporte detalla el flujo de funcionamiento de la aplicación **Escaner_V0.3.2**, describiendo sus componentes principales, sus responsabilidades y las interacciones clave entre ellos.

## Arquitectura General

La aplicación **Escaner_V0.3.2** sigue una arquitectura modular basada en **CustomTkinter** para la interfaz de usuario y una gestión de datos a través de una base de datos. Se compone de una clase principal que orquesta el inicio y la navegación entre las diferentes vistas (login y ventana principal), y varias clases de modelos y utilidades que manejan la lógica de negocio y la interacción con la base de datos.

### Componentes Principales

*   **EscanerApp** [Escaner_V0.3.2.py](Escaner_V0.3.2.py): La clase principal que inicializa la aplicación, gestiona el ciclo de vida y la navegación entre las ventanas de login y la ventana principal.
*   **LoginWindow** [Escaner_V0.3.2.py](Escaner_V0.3.2.py): Maneja la interfaz y la lógica de autenticación de usuarios.
*   **MainWindow** [Escaner_V0.3.2.py](Escaner_V0.3.2.py): La ventana principal de la aplicación, que se adapta según el rol del usuario y contiene las funcionalidades principales (escáner, captura de datos, gestión de usuarios, base de datos, configuración).
*   **DatabaseManager** [config/database.py](config/database.py): Gestiona la conexión y las operaciones con la base de datos.
*   **Modelos (Usuario, CodigoItem, Captura)**: Clases que encapsulan la lógica de negocio y la interacción con tablas específicas de la base de datos.
    *   **Usuario** [models/usuario.py](models/usuario.py)
    *   **CodigoItem** [models/codigo_item.py](models/codigo_item.py)
    *   **Captura** [models/captura.py](models/captura.py)
*   **Utilidades (AppLogger, Validators)**: Clases auxiliares para el registro de eventos y la validación de datos.
    *   **AppLogger** [utils/logger.py](utils/logger.py)
    *   **Validators** [utils/validators.py](utils/validators.py)

## Flujo de Inicio de la Aplicación

El flujo de inicio de la aplicación se centra en la clase **EscanerApp** [Escaner_V0.3.2.py](Escaner_V0.3.2.py).

### **EscanerApp** [Escaner_V0.3.2.py](Escaner_V0.3.2.py)
*   **Propósito**: Orquestar el inicio de la aplicación, la inicialización de componentes y la gestión de la interfaz de usuario principal.
*   **Partes Internas**:
    *   `__init__`: Constructor que inicializa la ventana principal de CustomTkinter y las variables de estado.
    *   `inicializar_aplicacion`: Método clave que configura la base de datos, los modelos y el logger.
    *   `mostrar_login`: Muestra la ventana de login.
    *   `on_login_success`: Callback ejecutado tras un login exitoso, que lleva a la ventana principal.
    *   `mostrar_ventana_principal`: Muestra la ventana principal de la aplicación.
    *   `ejecutar`: Inicia el bucle principal de la aplicación.
*   **Relaciones Externas**:
    *   Instancia **DatabaseManager** [config/database.py](config/database.py) para la gestión de la base de datos.
    *   Instancia **AppLogger** [utils/logger.py](utils/logger.py) para el registro de eventos.
    *   Instancia los modelos **Usuario** [models/usuario.py](models/usuario.py), **CodigoItem** [models/codigo_item.py](models/codigo_item.py) y **Captura** [models/captura.py](models/captura.py).
    *   Crea y muestra la **LoginWindow** [Escaner_V0.3.2.py](Escaner_V0.3.2.py).
    *   Crea y muestra la **MainWindow** [Escaner_V0.3.2.py](Escaner_V0.3.2.py) después de un login exitoso.

### Flujo Detallado de `inicializar_aplicacion` [Escaner_V0.3.2.py:49](Escaner_V0.3.2.py:49)

1.  **Inicialización de DatabaseManager**: Se crea una instancia de `DatabaseManager` para manejar la conexión a la base de datos.
2.  **Creación de Tablas**: Se llama a `db_manager.create_tables()` para asegurar que las tablas necesarias existan en la base de datos.
3.  **Inserción de Datos por Defecto**: Se ejecuta `db_manager.insert_default_data()` para poblar la base de datos con datos iniciales, incluyendo un usuario administrador.
4.  **Inicialización de AppLogger**: Se configura el sistema de logging de la aplicación.
5.  **Inicialización de Modelos**: Se instancian los modelos `Usuario`, `CodigoItem` y `Captura`, pasándoles el `db_manager` para que puedan interactuar con la base de datos.
6.  **Carga de Configuración**: Se carga la configuración de la aplicación desde la base de datos.
7.  **Mostrar Login**: Finalmente, se invoca `mostrar_login()` para presentar la interfaz de autenticación al usuario.

## Flujo de Autenticación de Usuario

El proceso de autenticación es manejado por la clase **LoginWindow** [Escaner_V0.3.2.py](Escaner_V0.3.2.py).

### **LoginWindow** [Escaner_V0.3.2.py:200](Escaner_V0.3.2.py:200)
*   **Propósito**: Proporcionar una interfaz para que los usuarios ingresen sus credenciales y autenticarse contra la base de datos.
*   **Partes Internas**:
    *   `__init__`: Constructor que recibe la ventana maestra, el modelo de usuario, el logger y una función de callback para el éxito del login.
    *   `crear_interfaz`: Construye los elementos visuales del formulario de login (campos de usuario, contraseña, botón).
    *   `try_login`: Valida la entrada del usuario y, en un hilo separado, llama a la función de verificación de credenciales.
    *   `_verificar_credenciales`: Autentica al usuario utilizando el `usuario_model`.
    *   `_login_exitoso`: Ejecuta el callback `on_success` proporcionado por `EscanerApp` si la autenticación es exitosa.
*   **Relaciones Externas**:
    *   Interactúa con **Usuario** [models/usuario.py](models/usuario.py) para autenticar las credenciales.
    *   Utiliza **Validators** [utils/validators.py](utils/validators.py) para validar el formato de usuario y contraseña.
    *   Utiliza **AppLogger** [utils/logger.py](utils/logger.py) para registrar eventos de login.
    *   Notifica a **EscanerApp** [Escaner_V0.3.2.py](Escaner_V0.3.2.py) (a través del callback `on_login_success`) sobre el éxito del login.

## Flujo de la Ventana Principal

Una vez que el usuario se autentica, la aplicación muestra la **MainWindow** [Escaner_V0.3.2.py](Escaner_V0.3.2.py), cuya interfaz y funcionalidades varían según el rol del usuario.

### **MainWindow** [Escaner_V0.3.2.py:300](Escaner_V0.3.2.py:300)
*   **Propósito**: Servir como el centro de operaciones de la aplicación, ofreciendo diferentes funcionalidades a través de pestañas según el rol del usuario.
*   **Partes Internas**:
    *   `__init__`: Constructor que recibe el usuario, su rol, los modelos de datos y el logger.
    *   `crear_interfaz`: Determina qué pestañas mostrar (`_crear_interfaz_superadmin` o `_crear_interfaz_normal`).
    *   `_configurar_tab_escaner`: Configura la pestaña principal de escaneo de códigos.
    *   `_configurar_tab_captura`: Configura la pestaña para la captura de datos.
    *   `_configurar_tab_gestion_usuarios`: Configura la pestaña para la gestión de usuarios (solo superadmin).
    *   `_configurar_tab_base_datos`: Configura la pestaña para la visualización y gestión de tablas de la base de datos (solo superadmin).
    *   `_configurar_tab_configuracion`: Configura la pestaña para la carga de archivos CLP (solo admin).
    *   `buscar_codigo`: Lógica para buscar códigos de barras.
    *   `guardar_captura_offline`: Guarda capturas localmente si no hay conexión.
    *   `subir_capturas_offline`: Sube capturas pendientes a la base de datos.
    *   `cargar_estadisticas`: Actualiza las estadísticas mostradas en la interfaz.
    *   `cerrar_sesion`: Permite al usuario cerrar la sesión y regresar a la pantalla de login.
*   **Relaciones Externas**:
    *   Interactúa con **CodigoItem** [models/codigo_item.py](models/codigo_item.py) para buscar códigos y obtener estadísticas.
    *   Interactúa con **Captura** [models/captura.py](models/captura.py) para registrar consultas y guardar/subir capturas.
    *   Interactúa con **Usuario** [models/usuario.py](models/usuario.py) para la gestión de usuarios.
    *   Utiliza **AppLogger** [utils/logger.py](utils/logger.py) para registrar acciones del usuario y errores.
    *   Utiliza **Validators** [utils/validators.py](utils/validators.py) para validar códigos de barras y configuraciones.
    *   Utiliza **DatabaseManager** [config/database.py](config/database.py) para operaciones directas con la base de datos (ej. mostrar tablas SQL, exportar reportes).

### Flujo de Funcionalidades Clave

#### Búsqueda de Códigos (Pestaña "Escáner")

1.  El usuario ingresa un código de barras en el campo de entrada [Escaner_V0.3.2.py:600](Escaner_V0.3.2.py:600).
2.  Se valida el formato del código utilizando **Validators.validar_codigo_barras** [utils/validators.py](utils/validators.py).
3.  Si es válido, se deshabilita el botón de búsqueda y se inicia una nueva búsqueda en un hilo separado (`_ejecutar_busqueda_nueva`) [Escaner_V0.3.2.py:610](Escaner_V0.3.2.py:610).
4.  El método `_ejecutar_busqueda_nueva` llama a **codigo_model.buscar_codigo** [models/codigo_item.py](models/codigo_item.py) para consultar la base de datos.
5.  El resultado se muestra en la interfaz (`_mostrar_resultado` o `_mostrar_no_encontrado`) [Escaner_V0.3.2.py:630](Escaner_V0.3.2.py:630).
6.  Se registra la consulta en la base de datos utilizando **captura_model.registrar_consulta** [models/captura.py](models/captura.py).
7.  El botón de búsqueda se restaura y el campo de entrada se limpia.

#### Captura de Datos (Pestaña "Captura de Datos")

1.  El usuario ingresa un código de barras y un item, selecciona si "CUMPLE" o "NO CUMPLE", y un motivo si no cumple [Escaner_V0.3.2.py:800](Escaner_V0.3.2.py:800).
2.  Al presionar "Guardar", se llama a `guardar_captura_offline` [Escaner_V0.3.2.py:900](Escaner_V0.3.2.py:900).
3.  La captura se guarda localmente en un archivo JSON (`capturas_pendientes_{usuario}.json`) [Escaner_V0.3.2.py:910](Escaner_V0.3.2.py:910).
4.  El botón "Subir capturas pendientes" se actualiza para mostrar el número de capturas pendientes [Escaner_V0.3.2.py:990](Escaner_V0.3.2.py:990).
5.  Cuando el usuario presiona "Subir capturas pendientes", `subir_capturas_offline` [Escaner_V0.3.2.py:930](Escaner_V0.3.2.py:930) lee el archivo JSON y llama a **captura_model.guardar_captura** [models/captura.py](models/captura.py) para cada captura.
6.  Si todas las capturas se suben exitosamente, el archivo local se elimina.

#### Gestión de Usuarios (Pestaña "Gestión de Usuarios" - Superadmin)

1.  El superadmin puede crear, eliminar y cambiar el estado de los usuarios [Escaner_V0.3.2.py:1200](Escaner_V0.3.2.py:1200).
2.  Las operaciones se realizan a través de **usuario_model** [models/usuario.py](models/usuario.py) (ej. `crear_usuario`, `eliminar_usuario`, `cambiar_estado_usuario`).
3.  La lista de usuarios se carga y refresca utilizando **usuario_model.obtener_todos_usuarios** [models/usuario.py](models/usuario.py).

#### Base de Datos (Pestaña "Base de Datos" - Superadmin)

1.  Permite visualizar el contenido de las tablas `usuarios`, `codigos_items` y `capturas` [Escaner_V0.3.2.py:450](Escaner_V0.3.2.py:450).
2.  Para `codigos_items`, incluye una funcionalidad de búsqueda.
3.  La pestaña de "Capturas" en esta sección permite al superadmin revisar y aceptar/denegar capturas pendientes, moviéndolas a la tabla `codigos_items` o eliminándolas [Escaner_V0.3.2.py:500](Escaner_V0.3.2.py:500).

#### Configuración (Pestaña "Configuración" - Admin)

1.  Permite al administrador seleccionar y cargar archivos CLP (Excel) para actualizar la base de datos de códigos [Escaner_V0.3.2.py:1100](Escaner_V0.3.2.py:1100).
2.  La carga se realiza a través de **codigo_model.cargar_varios_clp** [models/codigo_item.py](models/codigo_item.py).

## Flujo de Cierre de Sesión

El botón "Cerrar Sesión" en la **MainWindow** [Escaner_V0.3.2.py:750](Escaner_V0.3.2.py:750) destruye la ventana actual y reinicia la aplicación, volviendo a mostrar la **LoginWindow** [Escaner_V0.3.2.py](Escaner_V0.3.2.py).

