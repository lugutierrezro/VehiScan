# Script para generar datos simulados masivos para ETL y BI
alias Vehiscan.Repo
alias Vehiscan.Monitoring.{ALPREvent, Watchlist, Alert}
alias Vehiscan.Infrastructure.Camera
alias Vehiscan.Accounts.User

IO.puts "Iniciando generación de datos simulados..."

admin = Repo.get_by!(User, email: "admin@vehiscan.local")
cameras = Repo.all(Camera)
if length(cameras) == 0 do
  IO.puts "Error: No hay cámaras en la BD. Por favor corre mix run priv/repo/seeds.exs primero."
  System.halt(1)
end

# 1. Generar Placas para la Watchlist
IO.puts "Generando 50 placas en Watchlist..."
reasons = ["Robo", "Secuestro", "Orden de captura", "Lavado de activos", "Embargo"]
sources = ["Policía Nacional", "Interpol", "SAT", "Ministerio Público"]
severities = ["low", "medium", "high", "critical"]

watchlists = for i <- 1..50 do
  plate = "WTC#{Enum.random(100..999)}"
  %{
    id: Ecto.UUID.generate(),
    plate: plate,
    reason: Enum.random(reasons),
    source: Enum.random(sources),
    severity: Enum.random(severities),
    status: "active",
    start_date: Date.utc_today(),
    end_date: Date.add(Date.utc_today(), Enum.random(10..100)),
    assigned_by_id: admin.id,
    inserted_at: DateTime.utc_now(),
    updated_at: DateTime.utc_now()
  }
end
Repo.insert_all(Watchlist, watchlists)
watchlist_plates = Enum.map(watchlists, & &1.plate)

# 2. Generar 5000 Eventos ALPR simulados
IO.puts "Generando 5000 lecturas ALPR (históricas)..."
today = DateTime.utc_now()

alpr_events = for _i <- 1..5000 do
  camera = Enum.random(cameras)
  
  # 5% de probabilidad de que sea una placa de la watchlist
  is_watchlist = :rand.uniform() < 0.05
  plate = if is_watchlist, do: Enum.random(watchlist_plates), else: "SIM#{Enum.random(100..999)}"
  
  # Fecha aleatoria en los últimos 30 días
  days_ago = Enum.random(0..30)
  hours_ago = Enum.random(0..23)
  minutes_ago = Enum.random(0..59)
  inserted_at = DateTime.add(today, -(days_ago * 86400 + hours_ago * 3600 + minutes_ago * 60), :second)
  
  %{
    id: Ecto.UUID.generate(),
    normalized_plate: plate,
    original_plate: plate,
    confidence: Enum.random(60..99) + :rand.uniform() * 1.0,
    plate_image_url: "attributes|class:car|color:blue",
    status: if(is_watchlist, do: "alerted", else: "processed"),
    location_name: camera.location_name,
    camera_id: camera.id,
    inserted_at: inserted_at,
    updated_at: inserted_at
  }
end

# Insertar en lotes de 1000
Enum.chunk_every(alpr_events, 1000)
|> Enum.each(fn chunk -> Repo.insert_all(ALPREvent, chunk) end)

IO.puts "Datos simulados creados exitosamente."
