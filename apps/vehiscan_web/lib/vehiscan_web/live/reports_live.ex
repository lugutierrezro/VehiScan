defmodule VehiscanWeb.ReportsLive do
  use VehiscanWeb, :live_view

  alias Vehiscan.Repo
  alias Vehiscan.Reporting
  alias Vehiscan.Infrastructure.Camera
  alias Vehiscan.Monitoring.ALPREvent

  on_mount {VehiscanWeb.UserAuth, :ensure_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    cameras = Repo.all(Camera)
    zones = Enum.map(cameras, & &1.zone) |> Enum.uniq() |> Enum.reject(&is_nil/1)

    # Rango por defecto: últimos 7 días
    today = Date.utc_today()
    seven_days_ago = Date.add(today, -7)

    from_date_str = Date.to_iso8601(seven_days_ago)
    to_date_str = Date.to_iso8601(today)

    filters = %{
      "from_date" => from_date_str,
      "to_date" => to_date_str,
      "camera_id" => "",
      "zone" => ""
    }

    stats = Reporting.query_alpr_stats(filters)
    reports = Reporting.list_reports()

    socket =
      socket
      |> assign(:page_title, "Reportes y Estadísticas")
      |> assign(:cameras, cameras)
      |> assign(:zones, zones)
      |> assign(:from_date, from_date_str)
      |> assign(:to_date, to_date_str)
      |> assign(:selected_camera_id, "")
      |> assign(:selected_zone, "")
      |> assign(:stats, stats)
      |> assign(:reports, reports)
      |> assign(:active_tab, "success")

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  # Cambio de pestaña para visualización de detalles
  @impl true
  def handle_event("set-tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  # Filtrado dinámico
  @impl true
  def handle_event("update-filters", params, socket) do
    from_date = Map.get(params, "from_date", socket.assigns.from_date)
    to_date = Map.get(params, "to_date", socket.assigns.to_date)
    camera_id = Map.get(params, "camera_id", socket.assigns.selected_camera_id)
    zone = Map.get(params, "zone", socket.assigns.selected_zone)

    filters = %{
      "from_date" => from_date,
      "to_date" => to_date,
      "camera_id" => camera_id,
      "zone" => zone
    }

    stats = Reporting.query_alpr_stats(filters)

    socket =
      socket
      |> assign(:from_date, from_date)
      |> assign(:to_date, to_date)
      |> assign(:selected_camera_id, camera_id)
      |> assign(:selected_zone, zone)
      |> assign(:stats, stats)

    {:noreply, socket}
  end

  # Generación de reporte CSV
  @impl true
  def handle_event("generate-report", %{"type" => type}, socket) do
    user = socket.assigns.current_user

    filters = %{
      "from_date" => socket.assigns.from_date,
      "to_date" => socket.assigns.to_date,
      "camera_id" => socket.assigns.selected_camera_id,
      "zone" => socket.assigns.selected_zone
    }

    case Reporting.create_report(user.id, %{type: type, filters_used: filters, status: "generating"}) do
      {:ok, report} ->
        case Reporting.generate_report_csv(report, user.email, filters) do
          {:ok, _updated_report} ->
            reports = Reporting.list_reports()
            socket =
              socket
              |> assign(:reports, reports)
              |> put_flash(:info, "Reporte oficial generado con éxito. Se ha registrado en la bitácora de auditoría.")

            {:noreply, socket}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Error al generar el archivo del reporte.")}
        end

      {:error, changeset} ->
        error_msg =
          changeset.errors
          |> Enum.map(fn {k, {msg, _}} -> "#{k}: #{msg}" end)
          |> Enum.join(", ")

        {:noreply, put_flash(socket, :error, "Error en validación: #{error_msg}")}
    end
  end
end
