# Script para poblar la base de datos de Vehiscan.
# Se puede ejecutar con: mix run priv/repo/seeds.exs

alias Vehiscan.Repo
alias Vehiscan.Accounts
alias Vehiscan.Accounts.{User, Role}
alias Vehiscan.Infrastructure.Camera
alias Vehiscan.Monitoring.Watchlist
alias Vehiscan.Config.Configuration

# 1. Asegurar la creación de Roles
IO.puts("Creando roles por defecto...")
Accounts.seed_default_roles()

# Cargar los roles para referencia
roles = Repo.all(Role) |> Map.new(fn r -> {r.name, r.id} end)

# 2. Crear Usuarios por Defecto si no existen
default_users = [
  %{
    name: "Administrador del Sistema",
    email: "admin@vehiscan.local",
    password: "VehiScan2024!",
    role_id: roles["admin"],
    status: "active"
  },
  %{
    name: "Operador de Monitoreo",
    email: "operator@vehiscan.local",
    password: "VehiScan2024!",
    role_id: roles["operator"],
    status: "active"
  },
  %{
    name: "Investigador Especial",
    email: "investigator@vehiscan.local",
    password: "VehiScan2024!",
    role_id: roles["investigator"],
    status: "active"
  },
  %{
    name: "Auditor de Cumplimiento",
    email: "auditor@vehiscan.local",
    password: "VehiScan2024!",
    role_id: roles["auditor"],
    status: "active"
  }
]

IO.puts("Creando usuarios de prueba...")
Enum.each(default_users, fn user_attrs ->
  case Repo.get_by(User, email: user_attrs.email) do
    nil ->
      case Accounts.create_user(user_attrs) do
        {:ok, _user} -> IO.puts("Usuario creado: #{user_attrs.email}")
        {:error, changeset} -> IO.inspect(changeset.errors, label: "Error al crear usuario #{user_attrs.email}")
      end
    _user ->
      IO.puts("Usuario ya existe: #{user_attrs.email}")
  end
end)

# Cargar un usuario administrador para asignaciones de watchlist
admin_user = Repo.get_by!(User, email: "admin@vehiscan.local")

# 3. Crear Cámaras ALPR
default_cameras = [
  %{
    code: "CAM-CHA-01",
    type: "fixed",
    location_name: "Municipalidad de Chaclacayo - Ingreso Principal",
    latitude: -11.9760,
    longitude: -76.7690,
    orientation: "N",
    status: "active",
    stream_url: "C:\\Users\\jory1\\Downloads\\data\\data\\01_raw\\downloaded_stream.mp4",
    zone: "Chaclacayo Centro"
  },
  %{
    code: "CAM-CHA-02",
    type: "fixed",
    location_name: "Carretera Central - Altura Municipalidad",
    latitude: -11.9780,
    longitude: -76.7720,
    orientation: "E",
    status: "active",
    stream_url: "C:\\Users\\jory1\\Downloads\\data\\data\\01_raw\\jane_byrne_traffic.webm",
    zone: "Chaclacayo Carretera"
  },
  %{
    code: "CAM-CHA-03",
    type: "ptz",
    location_name: "Plaza de Armas de Chaclacayo",
    latitude: -11.9750,
    longitude: -76.7700,
    orientation: "S",
    status: "active",
    stream_url: "C:\\Users\\jory1\\Downloads\\data\\data\\01_raw\\person-bicycle-car-detection.mp4",
    zone: "Chaclacayo Centro"
  },
  %{
    code: "CAM-ONLINE",
    type: "fixed",
    location_name: "Monitoreo en Línea (Chaclacayo)",
    latitude: -11.9765,
    longitude: -76.7695,
    orientation: "N",
    status: "active",
    stream_url: "https://assets.ultralytics.com/assets/videos/traffic.mp4",
    zone: "Chaclacayo Centro"
  }
]

IO.puts("Creando cámaras...")
Enum.each(default_cameras, fn cam_attrs ->
  case Repo.get_by(Camera, code: cam_attrs.code) do
    nil ->
      %Camera{}
      |> Camera.changeset(cam_attrs)
      |> Repo.insert!()
      IO.puts("Cámara creada: #{cam_attrs.code}")
    _cam ->
      IO.puts("Cámara ya existe: #{cam_attrs.code}")
  end
end)

# 4. Crear Watchlists
default_watchlists = [
  %{
    plate: "ABC123",
    source: "Policía Nacional - DIVINCE",
    reason: "Secuestro activo - Alerta Amber",
    severity: "high",
    start_date: Date.utc_today(),
    end_date: Date.add(Date.utc_today(), 30),
    status: "active",
    assigned_by_id: admin_user.id
  },
  %{
    plate: "XYZ789",
    source: "SAT - Cobranza Coactiva",
    reason: "Orden de embargo judicial sobre el vehículo",
    severity: "medium",
    start_date: Date.utc_today(),
    end_date: Date.add(Date.utc_today(), 90),
    status: "active",
    assigned_by_id: admin_user.id
  },
  %{
    plate: "FGH456",
    source: "Ministerio Público",
    reason: "Sospechoso en investigación de lavado de activos",
    severity: "high",
    start_date: Date.utc_today(),
    end_date: Date.add(Date.utc_today(), 60),
    status: "active",
    assigned_by_id: admin_user.id
  }
]

IO.puts("Creando lista de interés (Watchlist)...")
Enum.each(default_watchlists, fn watch_attrs ->
  case Repo.get_by(Watchlist, plate: watch_attrs.plate) do
    nil ->
      %Watchlist{}
      |> Watchlist.changeset(watch_attrs)
      |> Repo.insert!()
      IO.puts("Placa agregada a watchlist: #{watch_attrs.plate}")
    _watch ->
      IO.puts("Placa en watchlist ya existe: #{watch_attrs.plate}")
  end
end)

# 5. Crear Configuraciones del Sistema por defecto
IO.puts("Creando configuraciones por defecto...")
Enum.each(Configuration.defaults(), fn conf_attrs ->
  case Repo.get(Configuration, conf_attrs.parameter_key) do
    nil ->
      %Configuration{}
      |> Configuration.changeset(Map.put(conf_attrs, :updated_by_id, admin_user.id))
      |> Repo.insert!()
      IO.puts("Configuración registrada: #{conf_attrs.parameter_key}")
    _conf ->
      IO.puts("Configuración ya existe: #{conf_attrs.parameter_key}")
  end
end)

IO.puts("Sembrado de base de datos finalizado con éxito.")
