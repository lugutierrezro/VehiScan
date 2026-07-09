alias Vehiscan.Repo

IO.puts "Iniciando proceso ETL para el Cubo OLAP..."

# 1. Poblar dim_camera
IO.puts "Extrayendo dimensiones de cámaras..."
query_cameras = "INSERT INTO dim_camera (id, code, location_name, zone) SELECT id, code, location_name, zone FROM cameras ON CONFLICT DO NOTHING"
Ecto.Adapters.SQL.query!(Repo, query_cameras)

# 2. Poblar dim_date
IO.puts "Extrayendo dimensiones de tiempo..."
query_dates = """
  INSERT INTO dim_date (id, year, month, day, day_of_week)
  SELECT DISTINCT 
    DATE(inserted_at), 
    EXTRACT(YEAR FROM inserted_at), 
    EXTRACT(MONTH FROM inserted_at), 
    EXTRACT(DAY FROM inserted_at),
    EXTRACT(DOW FROM inserted_at)
  FROM alpr_events
  ON CONFLICT DO NOTHING
"""
Ecto.Adapters.SQL.query!(Repo, query_dates)

# 3. Poblar fact_alpr_readings
IO.puts "Calculando hechos y métricas (fact_alpr_readings)..."
query_facts = """
  INSERT INTO fact_alpr_readings (dim_date_id, dim_camera_id, total_readings, high_confidence_readings, watchlisted_readings)
  SELECT 
    DATE(inserted_at) as dim_date_id,
    camera_id as dim_camera_id,
    COUNT(*) as total_readings,
    SUM(CASE WHEN confidence >= 75 THEN 1 ELSE 0 END) as high_confidence_readings,
    SUM(CASE WHEN status = 'alerted' THEN 1 ELSE 0 END) as watchlisted_readings
  FROM alpr_events
  GROUP BY DATE(inserted_at), camera_id
  ON CONFLICT (dim_date_id, dim_camera_id) DO UPDATE SET
    total_readings = EXCLUDED.total_readings,
    high_confidence_readings = EXCLUDED.high_confidence_readings,
    watchlisted_readings = EXCLUDED.watchlisted_readings
"""
Ecto.Adapters.SQL.query!(Repo, query_facts)

IO.puts "¡ETL completado exitosamente!"
