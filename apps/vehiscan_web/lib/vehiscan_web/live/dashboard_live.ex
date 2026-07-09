defmodule VehiscanWeb.DashboardLive do
  use VehiscanWeb, :live_view

  import Ecto.Query
  alias Vehiscan.Repo
  alias Vehiscan.Monitoring
  alias Vehiscan.Monitoring.ALPREvent
  alias Vehiscan.Infrastructure.Camera

  on_mount {VehiscanWeb.UserAuth, :ensure_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Monitoring.subscribe()

    cameras = Repo.all(Camera)
    # Serialize cameras to pass to Leaflet
    cameras_json =
      cameras
      |> Enum.map(fn c ->
        %{code: c.code, location_name: c.location_name, latitude: c.latitude, longitude: c.longitude, status: c.status}
      end)
      |> Jason.encode!()

    pending_alerts = Monitoring.list_pending_alerts()
    recent_events = Monitoring.list_alpr_events(limit: 8)

    socket =
      socket
      |> assign(:page_title, "Dashboard Operativo")
      |> assign(:cameras, cameras)
      |> assign(:cameras_json, cameras_json)
      |> assign(:pending_alerts, pending_alerts)
      |> assign(:recent_events, recent_events)
      |> assign(:stats, load_stats())
      |> assign(:selected_alert, nil)
      |> assign(:validation_error, nil)
      |> assign(:streaming_cameras, %{})
      |> assign(:threat_alert, nil)

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select-alert", %{"id" => alert_id}, socket) do
    alert = Enum.find(socket.assigns.pending_alerts, &(&1.id == alert_id))
    {:noreply, assign(socket, :selected_alert, alert)}
  end

  @impl true
  def handle_event("toggle-stream", %{"id" => camera_id}, socket) do
    streaming = socket.assigns.streaming_cameras

    streaming =
      if Map.has_key?(streaming, camera_id) do
        Map.delete(streaming, camera_id)
      else
        Map.put(streaming, camera_id, true)
      end

    {:noreply, assign(socket, :streaming_cameras, streaming)}
  end

  @impl true
  def handle_event("close-modal", _params, socket) do
    {:noreply, assign(socket, selected_alert: nil, validation_error: nil)}
  end

  @impl true
  def handle_event("dismiss-threat-alert", _params, socket) do
    {:noreply, assign(socket, :threat_alert, nil)}
  end

  @impl true
  def handle_event("resolve-alert", %{"status" => status, "details" => details}, socket) do
    alert = socket.assigns.selected_alert
    operator_id = socket.assigns.current_user.id
    ip_address = "127.0.0.1" # En LiveView se puede obtener de la conexión remota, simplificado para simulación

    if String.length(details) < 10 do
      {:noreply, assign(socket, :validation_error, "La justificación debe tener al menos 10 caracteres")}
    else
      attrs = %{
        operator_id: operator_id,
        validation_details: details,
        status: status
      }

      case Monitoring.resolve_alert(alert.id, attrs, ip_address) do
        {:ok, _resolved} ->
          # Actualizar listas locales
          updated_alerts = Enum.reject(socket.assigns.pending_alerts, &(&1.id == alert.id))

          {:noreply,
           socket
           |> put_flash(:info, "Alerta procesada correctamente")
           |> assign(:pending_alerts, updated_alerts)
           |> assign(:selected_alert, nil)
           |> assign(:validation_error, nil)
           |> assign(:stats, load_stats())}

        {:error, changeset} ->
          error_msg =
            changeset.errors
            |> Enum.map(fn {k, {msg, _}} -> "#{k}: #{msg}" end)
            |> Enum.join(", ")

          {:noreply, assign(socket, :validation_error, error_msg)}
      end
    end
  end

  # ─── Manejo de Eventos en Tiempo Real (PubSub) ───────────────────────────────

  @impl true
  def handle_info({:new_alpr_event, event, alerts}, socket) do
    # Agregar el evento al feed
    updated_events = [event | socket.assigns.recent_events] |> Enum.take(8)

    # Si hay alertas asociadas, agregarlas a la cola
    updated_alerts =
      if alerts != [] do
        (alerts ++ socket.assigns.pending_alerts)
        |> Enum.uniq_by(& &1.id)
      else
        socket.assigns.pending_alerts
      end

    # Notificar al cliente JS (Leaflet) para agregar marcador y centrar
    socket =
      socket
      |> push_event("new-capture", %{
        latitude: event.camera.latitude,
        longitude: event.camera.longitude,
        plate: event.normalized_plate,
        camera_code: event.camera.code,
        location_name: event.camera.location_name
      })
      |> assign(:recent_events, updated_events)
      |> assign(:pending_alerts, updated_alerts)
      |> assign(:stats, load_stats())
      |> assign(:threat_alert, if(alerts != [], do: List.first(alerts), else: socket.assigns.threat_alert))

    socket =
      if alerts != [] do
        push_event(socket, "play-threat-alarm", %{})
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:alert_resolved, resolved_alert}, socket) do
    updated_alerts = Enum.reject(socket.assigns.pending_alerts, &(&1.id == resolved_alert.id))

    {:noreply,
     socket
     |> assign(:pending_alerts, updated_alerts)
     |> assign(:stats, load_stats())}
  end

  # ─── Privados ─────────────────────────────────────────────────────────────────

  defp load_stats do
    today = Date.utc_today()
    start_of_day = DateTime.new!(today, ~T[00:00:00.000], "Etc/UTC")

    alpr_events_today_count =
      Repo.one(
        from(e in Vehiscan.Monitoring.ALPREvent,
          where: e.inserted_at >= ^start_of_day,
          select: count(e.id)
        )
      )

    active_watchlist_count =
      Repo.one(
        from(w in Vehiscan.Monitoring.Watchlist,
          where: w.status == "active",
          select: count(w.id)
        )
      )

    cameras = Repo.all(Camera)
    total_cameras = length(cameras)
    active_cameras = Enum.count(cameras, &(&1.status == "active"))

    %{
      alpr_events_today_count: alpr_events_today_count,
      active_watchlist_count: active_watchlist_count,
      total_cameras: total_cameras,
      active_cameras: active_cameras
    }
  end
end
