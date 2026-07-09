defmodule VehiscanWeb.SearchLive do
  use VehiscanWeb, :live_view

  import Ecto.Query
  alias Vehiscan.Repo
  alias Vehiscan.Monitoring
  alias Vehiscan.Monitoring.ALPREvent
  alias Vehiscan.Infrastructure.Camera
  alias Vehiscan.Governance

  on_mount {VehiscanWeb.UserAuth, :ensure_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    cameras = Repo.all(Camera)
    zones = Enum.map(cameras, & &1.zone) |> Enum.uniq() |> Enum.reject(&is_nil/1)

    socket =
      socket
      |> assign(:page_title, "Búsqueda Investigativa")
      |> assign(:cameras, cameras)
      |> assign(:zones, zones)
      |> assign(:results, [])
      |> assign(:active_tab, "table")
      |> assign(:plate_query, "")
      |> assign(:selected_camera_id, "")
      |> assign(:selected_zone, "")
      |> assign(:from_date, "")
      |> assign(:to_date, "")
      |> assign(:justification, "")
      |> assign(:show_justification_modal, false)
      |> assign(:validation_error, nil)
      # Reconstrucción de ruta
      |> assign(:route_events, [])
      |> assign(:reconstructed_plate, nil)
      |> assign(:current_replay_index, nil)
      |> assign(:replay_timer, nil)

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  # Tab Switcher
  @impl true
  def handle_event("set-tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  # Form Submission - Triggers Justification Modal if needed
  @impl true
  def handle_event("submit-search", %{
        "plate" => plate,
        "camera_id" => camera_id,
        "zone" => zone,
        "from_date" => from_date,
        "to_date" => to_date
      }, socket) do
    
    # Store filters in assigns
    socket =
      socket
      |> assign(:plate_query, plate)
      |> assign(:selected_camera_id, camera_id)
      |> assign(:selected_zone, zone)
      |> assign(:from_date, from_date)
      |> assign(:to_date, to_date)

    if String.trim(plate) == "" and camera_id == "" and zone == "" and from_date == "" and to_date == "" do
      {:noreply, put_flash(socket, :error, "Debe seleccionar al menos un criterio de búsqueda.")}
    else
      # Justificación es obligatoria para cualquier consulta de investigación
      {:noreply, assign(socket, :show_justification_modal, true)}
    end
  end

  # Perform actual search after justification is submitted
  @impl true
  def handle_event("confirm-search", %{"justification" => justification}, socket) do
    if String.length(justification) < 10 do
      {:noreply, assign(socket, :validation_error, "La justificación debe tener al menos 10 caracteres")}
    else
      user_id = socket.assigns.current_user.id
      ip_address = "127.0.0.1"

      plate = socket.assigns.plate_query

      # Si se especifica placa, se delega al método de dominio auditado
      result =
        if String.trim(plate) != "" do
          case Monitoring.search_events_by_plate(plate, user_id, justification, ip_address) do
            {:ok, events} ->
              # Aplicar filtros adicionales sobre los resultados
              filtered = filter_results(events, socket.assigns)
              {:ok, filtered}

            {:error, {:audit_required, changeset}} ->
              {:error, changeset}
          end
        else
          # Búsqueda avanzada sin placa - Registrar log genérico
          filters = %{
            camera_id: socket.assigns.selected_camera_id,
            zone: socket.assigns.selected_zone,
            from_date: socket.assigns.from_date,
            to_date: socket.assigns.to_date
          }

          case Governance.log_action(user_id, "investigative_search",
                 ip_address: ip_address,
                 justification: justification,
                 filters: filters
               ) do
            {:ok, _log} ->
              events = fetch_advanced_events(filters)
              {:ok, events}

            {:error, changeset} ->
              {:error, changeset}
          end
        end

      case result do
        {:ok, events} ->
          # Cargar mapa de Leaflet con nuevos resultados si la pestaña activa es mapa
          socket =
            socket
            |> assign(:results, events)
            |> assign(:show_justification_modal, false)
            |> assign(:justification, justification)
            |> assign(:validation_error, nil)
            |> assign(:route_events, [])
            |> assign(:reconstructed_plate, nil)
            |> assign(:current_replay_index, nil)
            |> put_flash(:info, "Búsqueda completada exitosamente. Resultados auditados.")
            
          # Notificar al cliente JS de los nuevos marcadores
          socket = push_events_to_map(socket, events)

          {:noreply, socket}

        {:error, changeset} ->
          error_msg =
            changeset.errors
            |> Enum.map(fn {k, {msg, _}} -> "#{k}: #{msg}" end)
            |> Enum.join(", ")

          {:noreply, assign(socket, :validation_error, error_msg)}
      end
    end
  end

  @impl true
  def handle_event("close-modal", _params, socket) do
    {:noreply, assign(socket, show_justification_modal: false, validation_error: nil)}
  end

  # Reconstrucción de Ruta y Simulación paso a paso
  @impl true
  def handle_event("reconstruct-route", %{"plate" => plate}, socket) do
    # Buscar detecciones para una placa en orden cronológico ascendente
    events =
      ALPREvent
      |> where([e], e.normalized_plate == ^plate)
      |> order_by([e], asc: e.inserted_at)
      |> preload(:camera)
      |> Repo.all()

    if events == [] do
      {:noreply, put_flash(socket, :error, "No hay eventos para la placa #{plate}")}
    else
      # Detener temporizador previo si existe
      if socket.assigns.replay_timer, do: :timer.cancel(socket.assigns.replay_timer)

      socket =
        socket
        |> assign(:route_events, events)
        |> assign(:reconstructed_plate, plate)
        |> assign(:current_replay_index, 0)
        |> assign(:active_tab, "map")
        |> put_flash(:info, "Ruta de #{plate} cargada. Iniciando reproducción paso a paso.")

      # Emitir primer punto al mapa
      first_event = Enum.at(events, 0)
      socket = push_replay_event(socket, first_event, 0)

      # Iniciar loop de reproducción con timer de LiveView
      if length(events) > 1 do
        Process.send_after(self(), :tick_replay, 2000)
      end

      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:tick_replay, socket) do
    index = socket.assigns.current_replay_index
    events = socket.assigns.route_events

    if index && index < length(events) - 1 do
      next_index = index + 1
      next_event = Enum.at(events, next_index)

      socket = 
        socket
        |> assign(:current_replay_index, next_index)
        |> push_replay_event(next_event, next_index)

      # Programar siguiente paso
      Process.send_after(self(), :tick_replay, 2000)

      {:noreply, socket}
    else
      {:noreply, assign(socket, :current_replay_index, nil) |> put_flash(:info, "Reproducción de ruta finalizada.")}
    end
  end

  # ─── Auxiliares de consulta ───────────────────────────────────────────────────

  defp filter_results(events, assigns) do
    events
    |> Enum.filter(fn e ->
      cond do
        assigns.selected_camera_id != "" and e.camera_id != assigns.selected_camera_id -> false
        assigns.selected_zone != "" and e.camera.zone != assigns.selected_zone -> false
        true -> true
      end
    end)
  end

  defp fetch_advanced_events(filters) do
    query = from(e in ALPREvent, order_by: [desc: e.inserted_at], limit: 1000, preload: [:camera])

    query =
      if filters.camera_id != "" do
        where(query, [e], e.camera_id == ^filters.camera_id)
      else
        query
      end

    query =
      if filters.zone != "" do
        join(query, :inner, [e], c in assoc(e, :camera), on: c.zone == ^filters.zone)
      else
        query
      end

    query =
      if filters.from_date != "" do
        {:ok, from_dt} = Date.from_iso8601(filters.from_date)
        from_naive = DateTime.new!(from_dt, ~T[00:00:00.000], "Etc/UTC")
        where(query, [e], e.inserted_at >= ^from_naive)
      else
        query
      end

    query =
      if filters.to_date != "" do
        {:ok, to_dt} = Date.from_iso8601(filters.to_date)
        to_naive = DateTime.new!(to_dt, ~T[23:59:59.999], "Etc/UTC")
        where(query, [e], e.inserted_at <= ^to_naive)
      else
        query
      end

    Repo.all(query)
  end

  defp push_events_to_map(socket, events) do
    points =
      events
      |> Enum.filter(&(&1.camera.latitude && &1.camera.longitude))
      |> Enum.map(fn e ->
        %{
          latitude: e.camera.latitude,
          longitude: e.camera.longitude,
          plate: e.normalized_plate,
          camera_code: e.camera.code,
          location_name: e.camera.location_name
        }
      end)

    push_event(socket, "load-markers", %{markers: points})
  end

  defp push_replay_event(socket, event, index) do
    push_event(socket, "new-capture", %{
      latitude: event.camera.latitude,
      longitude: event.camera.longitude,
      plate: "#{event.normalized_plate} (Paso #{index + 1})",
      camera_code: event.camera.code,
      location_name: event.camera.location_name
    })
  end
end
