defmodule VehiscanWeb.CamerasLive do
  use VehiscanWeb, :live_view

  import Ecto.Query
  alias Vehiscan.Repo
  alias Vehiscan.Infrastructure.Camera
  alias Vehiscan.Monitoring.ALPREvent
  alias Vehiscan.Integrations.ProyectoSistemaInteligente

  on_mount {VehiscanWeb.UserAuth, :ensure_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Vehiscan.Monitoring.subscribe()

    socket =
      socket
      |> assign(:processing_cameras, %{})
      |> assign(:streaming_cameras, %{})
      |> assign(:view_mode, :videowall)
      |> assign(:selected_camera_id, nil)
      |> assign(:selected_camera_events, [])
      |> assign(:threat_alert, nil)
      |> load_cameras()

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("change-view-mode", %{"mode" => mode}, socket) do
    view_mode = String.to_existing_atom(mode)
    {:noreply, assign(socket, :view_mode, view_mode)}
  end

  @impl true
  def handle_event("select-camera-focus", %{"id" => camera_id}, socket) do
    events =
      Repo.all(
        from(e in ALPREvent,
          where: e.camera_id == ^camera_id,
          order_by: [desc: e.inserted_at],
          limit: 10,
          preload: [:camera]
        )
      )

    {:noreply,
     socket
     |> assign(:selected_camera_id, camera_id)
     |> assign(:selected_camera_events, events)}
  end

  @impl true
  def handle_event("toggle-all-streams", %{"action" => "start"}, socket) do
    cameras_with_sources = Enum.filter(socket.assigns.cameras_list, &(&1.camera.stream_url && &1.camera.stream_url != ""))
    streaming = Map.new(cameras_with_sources, fn item -> {item.camera.id, true} end)

    # Focus on the first camera if available
    socket =
      case cameras_with_sources do
        [first | _] ->
          events =
            Repo.all(
              from(e in ALPREvent,
                where: e.camera_id == ^first.camera.id,
                order_by: [desc: e.inserted_at],
                limit: 10,
                preload: [:camera]
              )
            )
          socket
          |> assign(:selected_camera_id, first.camera.id)
          |> assign(:selected_camera_events, events)

        _ ->
          socket
      end

    {:noreply, assign(socket, :streaming_cameras, streaming)}
  end

  @impl true
  def handle_event("toggle-all-streams", %{"action" => "stop"}, socket) do
    {:noreply,
     socket
     |> assign(:streaming_cameras, %{})
     |> assign(:selected_camera_id, nil)
     |> assign(:selected_camera_events, [])}
  end

  @impl true
  def handle_event("sync-camera", %{"id" => camera_id}, socket) do
    case ProyectoSistemaInteligente.sync_detections(camera_id) do
      {:ok, stats} ->
        socket =
          socket
          |> put_flash(:info, "Sincronización exitosa. Nuevas lecturas: #{stats.created}, Omitidas (Duplicados): #{stats.skipped}, Errores: #{stats.errors}.")
          |> load_cameras()

        # Emitir evento global por PubSub para actualizar otros clientes / dashboards
        Phoenix.PubSub.broadcast(
          Vehiscan.PubSub,
          "monitoring:events",
          {:sync_completed, camera_id}
        )

        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "No se encuentra el archivo de procesamiento de imágenes. Por favor ejecute la detección de YOLO/OCR en el módulo de Python o verifique la ruta configurada."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Error al sincronizar: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("process-video", %{"id" => camera_id}, socket) do
    case ProyectoSistemaInteligente.process_camera_video(camera_id) do
      {:ok, _pid} ->
        processing = Map.put(socket.assigns.processing_cameras, camera_id, :started)

        {:noreply,
         socket
         |> put_flash(:info, "Iniciando el motor de visión (YOLO, OCR, Re-ID) en segundo plano para esta cámara...")
         |> assign(:processing_cameras, processing)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
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



    events =
      Repo.all(
        from(e in ALPREvent,
          where: e.camera_id == ^camera_id,
          order_by: [desc: e.inserted_at],
          limit: 10,
          preload: [:camera]
        )
      )

    {:noreply,
     socket
     |> assign(:streaming_cameras, streaming)
     |> assign(:selected_camera_id, camera_id)
     |> assign(:selected_camera_events, events)}
  end

  @impl true
  def handle_event("dismiss-threat-alert", _params, socket) do
    {:noreply, assign(socket, :threat_alert, nil)}
  end

  @impl true
  def handle_info({:pipeline_status, camera_id, :started}, socket) do
    processing = Map.put(socket.assigns.processing_cameras, camera_id, :running)
    {:noreply, assign(socket, :processing_cameras, processing)}
  end

  @impl true
  def handle_info({:pipeline_status, camera_id, {:completed, stats}}, socket) do
    processing = Map.delete(socket.assigns.processing_cameras, camera_id)

    msg =
      if stats.created > 0 do
        "Procesamiento completado. #{stats.created} placa(s) nueva(s) registradas, #{stats.skipped} duplicadas omitidas."
      else
        "Procesamiento completado. No se detectaron placas en esta fuente de video. " <>
          "Verifica que el video tenga vehículos con placas visibles."
      end

    socket =
      socket
      |> put_flash(:info, msg)
      |> assign(:processing_cameras, processing)
      |> load_cameras()

    # Emitir evento global por PubSub para actualizar otros clientes / dashboards
    Phoenix.PubSub.broadcast(
      Vehiscan.PubSub,
      "monitoring:events",
      {:sync_completed, camera_id}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:pipeline_status, camera_id, {:failed, error_msg}}, socket) do
    processing = Map.delete(socket.assigns.processing_cameras, camera_id)
    
    socket =
      socket
      |> put_flash(:error, "El procesamiento de visión artificial falló: #{error_msg}")
      |> assign(:processing_cameras, processing)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_alpr_event, event, alerts}, socket) do
    socket = load_cameras(socket)

    # Si el evento es de la cámara actualmente seleccionada, agregarlo al feed
    socket =
      if socket.assigns.selected_camera_id == event.camera_id do
        updated_events = [event | socket.assigns.selected_camera_events] |> Enum.take(10)
        assign(socket, :selected_camera_events, updated_events)
      else
        socket
      end

    socket =
      socket
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
  def handle_info(_, socket) do
    {:noreply, socket}
  end

  # --- Privados ---

  defp load_cameras(socket) do
    cameras = Repo.all(Camera)

    # Cargar conteo de eventos por cámara
    camera_data =
      Enum.map(cameras, fn c ->
        event_count =
          Repo.one(
            from(e in ALPREvent,
              where: e.camera_id == ^c.id,
              select: count(e.id)
            )
          )

        %{
          camera: c,
          event_count: event_count
        }
      end)

    assign(socket, :cameras_list, camera_data)
  end

  # Helpers para el HTML
  def status_color("active"), do: "badge-success text-success-content"
  def status_color("inactive"), do: "badge-ghost"
  def status_color("maintenance"), do: "badge-warning text-warning-content"
  def status_color("error"), do: "badge-error text-error-content"
  def status_color(_), do: "badge-neutral"

  def camera_icon("ptz"), do: "hero-video-camera-solid"
  def camera_icon("mobile"), do: "hero-truck-solid"
  def camera_icon(_), do: "hero-video-camera"

  def source_type_label("video"), do: "Archivo/URL de Video"
  def source_type_label("directory"), do: "Directorio de Imágenes"
  def source_type_label("youtube"), do: "Transmisión de YouTube"
  def source_type_label("live_stream"), do: "Flujo en Vivo (RTSP/M3U8)"
  def source_type_label(_), do: "Archivo de Video"

  def source_type_icon("video"), do: "hero-film"
  def source_type_icon("directory"), do: "hero-folder-open"
  def source_type_icon("youtube"), do: "hero-play-circle"
  def source_type_icon("live_stream"), do: "hero-signal"
  def source_type_icon(_), do: "hero-document-play"
end
