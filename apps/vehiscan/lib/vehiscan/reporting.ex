defmodule Vehiscan.Reporting do
  @moduledoc """
  Contexto de Reportes de Vehiscan.

  Permite realizar consultas consolidadas sobre eventos ALPR para generar estadísticas
  y exportar reportes oficiales (CSV) con verificación de integridad digital.
  """

  import Ecto.Query
  alias Vehiscan.Repo
  alias Vehiscan.Monitoring.ALPREvent
  alias Vehiscan.Reporting.Report

  # ─── Gestión de Reportes ───────────────────────────────────────────────────

  @doc "Lista todos los reportes ordenados por fecha de creación desc."
  def list_reports do
    Report
    |> order_by([r], desc: r.inserted_at)
    |> preload(:user)
    |> Repo.all()
  end

  @doc "Obtiene un reporte por ID."
  def get_report!(id), do: Repo.get!(Report, id) |> Repo.preload(:user)

  @doc "Crea un registro de reporte pendiente de generación."
  def create_report(user_id, attrs) do
    %Report{}
    |> Report.changeset(Map.merge(attrs, %{user_id: user_id, status: "pending"}))
    |> Repo.insert()
  end

  # ─── Consultas de Estadísticas ──────────────────────────────────────────────

  @doc """
  Genera estadísticas para visualización web y filtros basados en fecha, cámara y zona.
  """
  def query_alpr_stats(filters \\ %{}) do
    query = build_alpr_query(filters)
    events = query |> Repo.all()

    total_count = length(events)
    successful_count = Enum.count(events, fn e -> e.confidence >= 75.0 end)
    failed_count = total_count - successful_count

    success_rate = if total_count > 0, do: Float.round((successful_count / total_count) * 100, 1), else: 0.0
    failed_rate = if total_count > 0, do: Float.round((failed_count / total_count) * 100, 1), else: 0.0

    # Agrupaciones
    class_distribution =
      events
      |> Enum.map(&ALPREvent.get_class/1)
      |> Enum.frequencies()

    color_distribution =
      events
      |> Enum.map(&ALPREvent.get_color/1)
      |> Enum.frequencies()

    %{
      total_count: total_count,
      successful_count: successful_count,
      failed_count: failed_count,
      success_rate: success_rate,
      failed_rate: failed_rate,
      class_distribution: class_distribution,
      color_distribution: color_distribution,
      events: events
    }
  end

  # ─── Generación de Archivo CSV ─────────────────────────────────────────────

  @doc """
  Genera el archivo CSV oficial, lo almacena localmente y calcula su firma SHA-256.
  """
  def generate_report_csv(report, user_email, filters) do
    stats = query_alpr_stats(filters)
    events = stats.events

    csv_header = [
      "--- REPORTE OFICIAL ALPR VEHISCAN ---",
      "Generado por: #{user_email}",
      "Fecha de Generacion: #{DateTime.utc_now() |> DateTime.to_string()}",
      "Filtro Camara ID: #{filters["camera_id"] || "Todas"}",
      "Filtro Zona: #{filters["zone"] || "Todas"}",
      "Filtro Desde: #{filters["from_date"] || "Inicio"}",
      "Filtro Hasta: #{filters["to_date"] || "Fin"}",
      "Lecturas Totales: #{stats.total_count}",
      "Lecturas Exitosas: #{stats.successful_count} (#{stats.success_rate}%)",
      "Lecturas Fallidas (Baja Confianza): #{stats.failed_count} (#{stats.failed_rate}%)",
      "------------------------------------",
      ""
    ] |> Enum.join("\n")

    data_header = "Fecha y Hora,Camara,Zona,Placa Original,Placa Normalizada,Confianza %,Tipo,Color,Estado de Lectura\n"

    data_rows =
      events
      |> Enum.map(fn e ->
        status_str = if e.confidence >= 75.0, do: "EXITOSA", else: "FALLIDA (BAJA CONFIANZA)"
        original = e.original_plate || ""
        class = ALPREvent.get_class(e)
        color = ALPREvent.get_color(e)

        [
          DateTime.to_string(e.inserted_at),
          e.camera.code,
          e.camera.zone,
          original,
          e.normalized_plate,
          "#{e.confidence}%",
          class,
          color,
          status_str
        ]
        |> Enum.map(&to_csv_field/1)
        |> Enum.join(",")
      end)
      |> Enum.join("\n")

    csv_content = csv_header <> data_header <> data_rows <> "\n"

    priv_dir =
      case :code.priv_dir(:vehiscan_web) do
        {:error, _} -> Path.expand("../vehiscan_web/priv", __DIR__)
        path -> path
      end

    reports_dir = Path.join([priv_dir, "static", "uploads", "reports"])
    File.mkdir_p!(reports_dir)

    file_path = Path.join(reports_dir, "#{report.id}.csv")
    File.write!(file_path, csv_content)

    file_hash = :crypto.hash(:sha256, csv_content) |> Base.encode16(case: :lower)
    file_url = "/reports/download/#{report.id}"

    report
    |> Report.complete_changeset(file_url, file_hash)
    |> Repo.update()
  end

  # ─── Privados ──────────────────────────────────────────────────────────────

  defp build_alpr_query(filters) do
    from(e in ALPREvent, preload: [:camera])
    |> filter_by_camera(filters["camera_id"] || filters[:camera_id])
    |> filter_by_zone(filters["zone"] || filters[:zone])
    |> filter_by_date(
      parse_date(filters["from_date"] || filters[:from_date]),
      parse_end_date(filters["to_date"] || filters[:to_date])
    )
    |> order_by([e], desc: e.inserted_at)
  end

  defp filter_by_camera(query, nil), do: query
  defp filter_by_camera(query, ""), do: query
  defp filter_by_camera(query, camera_id) do
    where(query, [e], e.camera_id == ^camera_id)
  end

  defp filter_by_zone(query, nil), do: query
  defp filter_by_zone(query, ""), do: query
  defp filter_by_zone(query, zone) do
    join(query, :inner, [e], c in assoc(e, :camera))
    |> where([e, c], c.zone == ^zone)
  end

  defp filter_by_date(query, nil, nil), do: query
  defp filter_by_date(query, from, nil) do
    where(query, [e], e.inserted_at >= ^from)
  end
  defp filter_by_date(query, nil, to) do
    where(query, [e], e.inserted_at <= ^to)
  end
  defp filter_by_date(query, from, to) do
    where(query, [e], e.inserted_at >= ^from and e.inserted_at <= ^to)
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> DateTime.new!(date, ~T[00:00:00.000], "Etc/UTC")
      _ -> nil
    end
  end
  defp parse_date(%Date{} = date), do: DateTime.new!(date, ~T[00:00:00.000], "Etc/UTC")
  defp parse_date(dt), do: dt

  defp parse_end_date(nil), do: nil
  defp parse_end_date(""), do: nil
  defp parse_end_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> DateTime.new!(date, ~T[23:59:59.999], "Etc/UTC")
      _ -> nil
    end
  end
  defp parse_end_date(%Date{} = date), do: DateTime.new!(date, ~T[23:59:59.999], "Etc/UTC")
  defp parse_end_date(dt), do: dt

  defp to_csv_field(val) do
    str = to_string(val)
    if String.contains?(str, [",", "\"", "\n"]) do
      "\"" <> String.replace(str, "\"", "\"\"") <> "\""
    else
      str
    end
  end
end
