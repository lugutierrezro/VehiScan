defmodule VehiscanWeb.StreamController do
  @moduledoc """
  Controlador que genera un stream MJPEG en tiempo real para una cámara,
  ejecutando un proceso Python con YOLO + EasyOCR.

  Flujo:
    stdout del proceso Python → frames MJPEG → navegador (video en vivo)
    stderr del proceso Python → líneas JSON con detecciones de placas → PubSub → LiveView
  """
  use VehiscanWeb, :controller

  alias Vehiscan.Repo
  alias Vehiscan.Infrastructure.Camera
  alias Vehiscan.Config.Configuration
  alias Vehiscan.Monitoring

  def stream(conn, %{"id" => camera_id}) do
    camera = Repo.get(Camera, camera_id)

    cond do
      is_nil(camera) ->
        conn |> send_resp(404, "Cámara no encontrada")

      (is_nil(camera.stream_url) or camera.stream_url == "") and camera.source_type != "webcam" ->
        conn |> send_resp(400, "La cámara no tiene una fuente de video configurada")

      true ->
        project_path = get_project_path()

        python_exec =
          case :os.type() do
            {:win32, _} -> Path.join([project_path, ".venv", "Scripts", "python.exe"])
            _ -> Path.join([project_path, ".venv", "bin", "python"])
          end

        script_path = Path.join(project_path, "stream_camera.py")

        unless File.exists?(python_exec) do
          conn |> send_resp(500, "Entorno Python no encontrado en #{python_exec}")
        end

        video_source = resolve_video_source(camera, project_path)

        port =
          Port.open(
            {:spawn_executable, python_exec},
            [
              :binary,
              :exit_status,
              :use_stdio,
              args: [script_path, video_source, "12", camera_id],
              cd: to_charlist(project_path),
              env: [
                {~c"PYTHONWARNINGS", ~c"ignore"},
                {~c"PYTHONUNBUFFERED", ~c"1"},
                {~c"VEHISCAN_API_URL", to_charlist("http://127.0.0.1:#{conn.port}")}
              ]
            ]
          )

        # Iniciar el proceso de escucha de detecciones JSON en un proceso separado
        detection_pid = spawn_link(fn ->
          listen_for_plate_detections(port, camera)
        end)

        # Leer hasta que llegue el header MJPEG (en stdout)
        {_header, rest_data} = read_until_first_frame(port)

        conn =
          conn
          |> put_resp_header("content-type", "multipart/x-mixed-replace; boundary=vehiscan_frame")
          |> put_resp_header("cache-control", "no-cache, no-store, must-revalidate")
          |> put_resp_header("pragma", "no-cache")
          |> send_chunked(200)

        if byte_size(rest_data) > 0 do
          chunk(conn, rest_data)
        end

        stream_loop(conn, port)

        # Cuando el stream termina, detener el listener
        Process.exit(detection_pid, :normal)
        conn
    end
  end

  # ─── Streaming de Frames MJPEG ─────────────────────────────────────────────

  defp stream_loop(conn, port) do
    receive do
      {^port, {:data, data}} ->
        case chunk(conn, data) do
          {:ok, conn} -> stream_loop(conn, port)
          {:error, _} ->
            Port.close(port)
            conn
        end

      {^port, {:exit_status, _status}} ->
        conn

    after
      45_000 ->
        Port.close(port)
        conn
    end
  end

  defp read_until_first_frame(port) do
    read_until_first_frame(port, <<>>)
  end

  defp read_until_first_frame(port, acc) do
    receive do
      {^port, {:data, data}} ->
        combined = acc <> data
        case :binary.match(combined, "\r\n\r\n") do
          {pos, len} ->
            header = binary_part(combined, 0, pos)
            rest = binary_part(combined, pos + len, byte_size(combined) - pos - len)
            {header, rest}

          :nomatch ->
            read_until_first_frame(port, combined)
        end

      {^port, {:exit_status, _code}} ->
        {acc, <<>>}

    after
      30_000 ->
        {acc, <<>>}
    end
  end

  # ─── Escucha de Detecciones de Placa (stderr JSON) ─────────────────────────

  defp listen_for_plate_detections(port, camera) do
    # Este proceso recibe mensajes del Port pero filtra solo los de stderr
    # En Elixir, con :use_stdio sin :stderr_to_stdout, los datos stdout y stderr
    # llegan por el mismo canal. Usamos heurística: si la línea empieza con '{'
    # es un JSON de detección, si no es log.
    receive do
      {^port, {:data, data}} ->
        process_port_data(data, camera)
        listen_for_plate_detections(port, camera)

      {^port, {:exit_status, _}} ->
        :ok

      _ ->
        listen_for_plate_detections(port, camera)
    end
  end

  defp process_port_data(data, camera) do
    data
    |> String.split("\n")
    |> Enum.each(fn line ->
      line = String.trim(line)
      if String.starts_with?(line, "{") do
        try_parse_plate_event(line, camera)
      end
    end)
  end

  defp try_parse_plate_event(line, camera) do
    case Jason.decode(line) do
      {:ok, %{"type" => "plate_detected", "plate" => plate, "confidence" => conf, "vehicle_class" => cls} = params} ->
        color = Map.get(params, "vehicle_color", "unknown")
        crop = Map.get(params, "crop_filename")
        register_plate_detection(camera, plate, conf, cls, color, crop)

      _ ->
        :ignore
    end
  end

  defp register_plate_detection(camera, plate, confidence_pct, vehicle_class, vehicle_color \\ "unknown", crop_filename \\ nil) do
    plate_image_url =
      if crop_filename && crop_filename != "" do
        "attributes|class:#{vehicle_class}|color:#{vehicle_color}|crop:#{crop_filename}"
      else
        "attributes|class:#{vehicle_class}|color:#{vehicle_color}"
      end

    attrs = %{
      original_plate: plate,
      normalized_plate: plate,
      confidence: confidence_pct,
      camera_id: camera.id,
      location_name: camera.location_name,
      status: "new",
      plate_image_url: plate_image_url
    }

    case Monitoring.register_alpr_event(attrs) do
      {:ok, %{event: _event}} ->
        IO.puts("StreamController: Placa registrada → #{plate} (#{confidence_pct}%) cam=#{camera.code}")
        # El broadcast via PubSub ya lo hace register_alpr_event/1

      {:error, reason} ->
        IO.inspect(reason, label: "StreamController: Error al registrar placa #{plate}")
    end
  end

  # ─── Helpers ───────────────────────────────────────────────────────────────

  defp resolve_video_source(camera, project_path) do
    url = camera.stream_url

    cond do
      camera.source_type == "webcam" ->
        if is_nil(url) or url == "", do: "0", else: url

      String.starts_with?(url, ["http://", "https://", "rtsp://", "rtmp://"]) ->
        local_copy = Path.join([project_path, "data", "01_raw", "downloaded_stream.mp4"])
        if String.starts_with?(url, ["http://", "https://"]) and File.exists?(local_copy) do
          local_copy
        else
          url
        end

      String.starts_with?(url, "/") or String.match?(url, ~r/^[a-zA-Z]:/) ->
        url

      true ->
        Path.join(project_path, url)
    end
  end

  defp get_project_path do
    Configuration.get_resolved_path()
  end
end
