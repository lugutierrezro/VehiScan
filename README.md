# VehiScan - Sistema Inteligente de Lectura y Monitoreo de Placas

VehiScan es una plataforma web desarrollada en **Elixir (Phoenix Framework)** integrada con procesamiento inteligente de imágenes en **Python** utilizando **YOLOv8** para el seguimiento de vehículos y **EasyOCR** para el reconocimiento óptico de caracteres de placas de vehículos.

---

## Arquitectura del Proyecto

* **`apps/vehiscan`**: Lógica de negocio, base de datos (PostgreSQL, Ecto) y workers en segundo plano (Oban).
* **`apps/vehiscan_web`**: Interfaz de usuario web interactiva (Phoenix LiveView, DaisyUI/Tailwind CSS) y transmisión en vivo de video (MJPEG).
* **`proyecto_sistema_inteligente`**: Módulo en Python que gestiona la detección mediante YOLOv8 y EasyOCR. Se comunica con Phoenix enviando eventos JSON en tiempo real a través de flujos de salida estándar (`stderr`/`stdout`).

---

## Método Recomendado: Ejecución con Docker (Linux y Windows)

El uso de Docker es el método preferido ya que empaqueta automáticamente todas las dependencias del sistema, incluidas las librerías necesarias para procesamiento gráfico (OpenCV, PyTorch, EasyOCR), Elixir, Erlang y PostgreSQL.

### Requisitos Previos

* **Docker Desktop** (con soporte para contenedores Linux activo si estás en Windows o macOS).
* **Docker Compose**.

### Pasos para Ejecutar

1. **Abrir la terminal** (CMD/PowerShell en Windows, o tu shell preferida en Linux) en la raíz del proyecto.
2. **Iniciar los contenedores:**
   ```bash
   docker compose up --build
   ```
   *Este comando construirá la imagen del proyecto, instalará las dependencias de Elixir y de Python en su correspondiente entorno virtual, inicializará la base de datos PostgreSQL, ejecutará las migraciones e insertará las semillas iniciales (seeds).*
3. **Acceder a la aplicación:**
   Abre tu navegador web e ingresa a:
   * **Aplicación Web:** [http://localhost:4000](http://localhost:4000)
   * **Buzón de correos local (Dev):** [http://localhost:4000/dev/mailbox](http://localhost:4000/dev/mailbox)

### Credenciales de Acceso (Semillas del Sistema)

Puedes iniciar sesión con cualquiera de los siguientes usuarios por defecto:

| Rol | Correo Electrónico | Contraseña |
| :--- | :--- | :--- |
| **Administrador** | `admin@vehiscan.local` | `Admin123!` |
| **Operador** | `operator@vehiscan.local` | `Operator123!` |
| **Investigador** | `investigator@vehiscan.local` | `Investigator123!` |
| **Auditor** | `auditor@vehiscan.local` | `Auditor123!` |

---

## Método Alternativo: Ejecución Local (Sin Docker)

Si prefieres ejecutar el sistema de manera nativa en tu sistema operativo, sigue estas instrucciones detalladas según tu plataforma.

### 1. Prerrequisitos Comunes
* **PostgreSQL:** Servidor activo con un usuario `postgres` y contraseña `VehiScan2024!` (o configura tus credenciales en las variables de entorno).
* **Elixir v1.15+** y **Erlang/OTP 26+**.

---

### En Linux (Ubuntu/Debian)

#### Paso 1: Dependencias del Sistema
```bash
sudo apt update
sudo apt install -y python3 python3-pip python3-venv libgl1 libglib2.0-0 build-essential git
```

#### Paso 2: Configurar Entorno Python
```bash
# Navegar al subproyecto de Python
cd proyecto_sistema_inteligente
# Crear el entorno virtual
python3 -m venv .venv
# Activar entorno virtual
source .venv/bin/activate
# Actualizar pip e instalar dependencias
pip install --upgrade pip
pip install ultralytics easyocr opencv-python-headless pandas kedro==1.3.1 kedro-datasets jupyterlab notebook ipython
cd ..
```

#### Paso 3: Configurar e Iniciar Elixir
```bash
# Instalar administradores de paquetes locales de Elixir
mix local.hex --force
mix local.rebar --force

# Obtener dependencias y configurar base de datos y assets
mix setup

# Iniciar el servidor Phoenix
mix phx.server
```

---

### En Windows

#### Paso 1: Dependencias del Sistema
* Instala **Python 3.11 o superior** asegurándote de marcar la opción "Add Python to PATH" durante la instalación.
* Asegúrate de tener instalado un compilador de C++ (como las herramientas de compilación de Visual Studio) para algunas librerías nativas.

#### Paso 2: Configurar Entorno Python (PowerShell)
```powershell
# Navegar al subproyecto de Python
cd proyecto_sistema_inteligente
# Crear entorno virtual
python -m venv .venv
# Activar entorno virtual
.venv\Scripts\Activate.ps1
# Instalar dependencias
python -m pip install --upgrade pip
pip install ultralytics easyocr opencv-python-headless pandas kedro==1.3.1 kedro-datasets jupyterlab notebook ipython
cd ..
```

#### Paso 3: Configurar e Iniciar Elixir
```powershell
mix local.hex --force
mix local.rebar --force
mix setup
mix phx.server
```

---

## Variables de Entorno Disponibles

Puedes personalizar el comportamiento de la base de datos y puertos utilizando variables de entorno en tu sistema o en el archivo `docker-compose.yml`:

* `DATABASE_HOST` (Por defecto: `localhost` / `db` en docker)
* `DATABASE_USER` (Por defecto: `postgres`)
* `DATABASE_PASSWORD` (Por defecto: `VehiScan2024!`)
* `DATABASE_DB` (Por defecto: `vehiscan_dev`)
* `PORT` (Puerto del servidor Phoenix. Por defecto: `4000`)
