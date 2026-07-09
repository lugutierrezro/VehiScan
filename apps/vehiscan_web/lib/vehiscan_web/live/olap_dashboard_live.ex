defmodule VehiscanWeb.OlapDashboardLive do
  use VehiscanWeb, :live_view
  alias Vehiscan.Repo

  on_mount {VehiscanWeb.UserAuth, :ensure_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    # 1. Total lecturas por día (Últimos 10 días)
    query_daily = """
      SELECT d.id as date, SUM(f.total_readings) as total
      FROM fact_alpr_readings f
      JOIN dim_date d ON f.dim_date_id = d.id
      GROUP BY d.id
      ORDER BY d.id DESC
      LIMIT 10
    """
    daily_readings = Ecto.Adapters.SQL.query!(Repo, query_daily).rows

    # 2. Top cámaras con más detecciones en watchlist
    query_cameras = """
      SELECT c.location_name, SUM(f.watchlisted_readings) as alerts
      FROM fact_alpr_readings f
      JOIN dim_camera c ON f.dim_camera_id = c.id
      WHERE f.watchlisted_readings > 0
      GROUP BY c.location_name
      ORDER BY alerts DESC
      LIMIT 5
    """
    camera_alerts = Ecto.Adapters.SQL.query!(Repo, query_cameras).rows

    # 3. Métricas generales
    query_kpis = """
      SELECT 
        SUM(total_readings) as total,
        SUM(high_confidence_readings) as high_conf,
        SUM(watchlisted_readings) as alerts
      FROM fact_alpr_readings
    """
    [[total, high_conf, alerts]] = Ecto.Adapters.SQL.query!(Repo, query_kpis).rows

    # 4. Distribución por Color (directo de la tabla de eventos para el gráfico)
    query_colors = """
      SELECT 
        SUBSTRING(plate_image_url FROM 'color:([a-zA-Z]+)') as color,
        COUNT(*) as count
      FROM alpr_events
      WHERE plate_image_url LIKE '%color:%'
      GROUP BY color
      ORDER BY count DESC
      LIMIT 5
    """
    color_distribution = Ecto.Adapters.SQL.query!(Repo, query_colors).rows

    # 5. Distribución por Tipo de Vehículo
    query_classes = """
      SELECT 
        SUBSTRING(plate_image_url FROM 'class:([a-zA-Z]+)') as class,
        COUNT(*) as count
      FROM alpr_events
      WHERE plate_image_url LIKE '%class:%'
      GROUP BY class
      ORDER BY count DESC
      LIMIT 5
    """
    class_distribution = Ecto.Adapters.SQL.query!(Repo, query_classes).rows

    # 6. Día más concurrido
    peak_day = if length(daily_readings) > 0 do
      [day, _] = Enum.max_by(daily_readings, fn [_, total] -> total end)
      day
    else
      "N/A"
    end

    # 7. Tipo de vehículo más frecuente
    top_class = if length(class_distribution) > 0 do
      [[class, _] | _] = class_distribution
      class
    else
      "N/A"
    end

    socket =
      socket
      |> assign(
        current_page: :olap,
        daily_readings: daily_readings, 
        camera_alerts: camera_alerts,
        color_distribution: color_distribution,
        class_distribution: class_distribution,
        total_readings: total || 0,
        high_conf_readings: high_conf || 0,
        total_alerts: alerts || 0,
        peak_day: peak_day,
        top_class: top_class
      )

    {:ok, socket, layout: false}
  end
end
