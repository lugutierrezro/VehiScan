defmodule Vehiscan.Integrations.ProyectoSistemaInteligente do
  @moduledoc """
  Servicio para sincronizar los resultados de detección del proyecto de Python (YOLO + EasyOCR + Re-ID)
  en el sistema de persistencia y alertas de Vehiscan.
  """

  import Ecto.Query
  require Logger

  alias Vehiscan.Repo
  alias Vehiscan.Monitoring
  alias Vehiscan.Monitoring.ALPREvent
  alias Vehiscan.Infrastructure.Camera
  alias Vehiscan.Config.Configuration

  @doc """
  Sincroniza los resultados de procesamiento de una cámara específica.
  Lee los archivos `plate_readings.csv` y `reid_profiles.csv` desde el proyecto de Python.
  """
  def sync_detections(camera_id) do
    camera = Repo.get!(Camera, camera_id)
    project_path = get_project_path()

    camera_plate_file = "plate_readings_#{camera.code}.csv"
    camera_reid_file = "reid_profiles_#{camera.code}.csv"

    plate_readings_path = 
      case Path.join([project_path, "data", "08_reporting", camera_plate_file]) do
        path -> if File.exists?(path), do: path, else: Path.join([project_path, "data", "08_reporting", "plate_readings.csv"])
      end

    reid_profiles_path = 
      case Path.join([project_path, "data", "08_reporting", camera_reid_file]) do
        path -> if File.exists?(path), do: path, else: Path.join([project_path, "data", "08_reporting", "reid_profiles.csv"])
      end

    with {:ok, plate_lines} <- read_csv_file(plate_readings_path),
         {:ok, reid_map} <- load_reid_profiles(reid_profiles_path) do
      
      # Filtrar cabeceras y líneas vacías
      plate_readings = parse_plate_readings(plate_lines)

      # Registrar cada lectura que no esté duplicada
      results =
        Enum.map(plate_readings, fn reading ->
          %{
            track_id: track_id,
            frame: frame,
            crop_path: crop_path,
            plate_text: plate_text,
            confidence: confidence
          } = reading

          # Buscar Re-ID asociado
          reid = Map.get(reid_map, track_id, %{class: "unknown", color: "unknown"})

          context_img = "frame:#{frame}"

          # Verificar si ya existe este frame para esta cámara para evitar duplicar
          exists? =
            Repo.exists?(
              from(e in ALPREvent,
                where: e.camera_id == ^camera.id and e.context_image_url == ^context_img
              )
            )

          if exists? do
            {:skipped, plate_text}
          else
            # Formatear el plate_image_url para incluir atributos para ObservedVehicle
            attr_string = "attributes|color:#{reid.color}|class:#{reid.class}|crop:#{crop_path}"

            attrs = %{
              original_plate: plate_text,
              normalized_plate: plate_text,
              confidence: confidence,
              plate_image_url: attr_string,
              context_image_url: context_img,
              camera_id: camera.id,
              location_name: camera.location_name,
              status: "new"
            }

            case Monitoring.register_alpr_event(attrs) do
              {:ok, result} -> {:ok, result}
              {:error, reason} -> {:error, reason}
            end
          end
        end)

      # Calcular estadísticas de sincronización
      created = Enum.count(results, &match?({:ok, _}, &1))
      skipped = Enum.count(results, &match?({:skipped, _}, &1))
      errors = Enum.count(results, &match?({:error, _}, &1))

      {:ok, %{created: created, skipped: skipped, errors: errors}}
    else
      {:error, :not_found} ->
        Logger.error("CSV files not found at project path: #{project_path}")
        {:error, :not_found}

      {:error, reason} ->
        Logger.error("Error syncing detections: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # --- Helpers ---

  defp get_project_path do
    Configuration.get_resolved_path()
  end

  defp read_csv_file(path) do
    case File.read(path) do
      {:ok, content} ->
        lines =
          content
          |> String.split(~r/\r?\n/)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        {:ok, lines}

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_reid_profiles(path) do
    case read_csv_file(path) do
      {:ok, lines} ->
        # Saltar cabecera: track_id,vehicle_class,dominant_color,embedding_snippet
        [_header | rest] = lines

        map =
          Enum.reduce(rest, %{}, fn line, acc ->
            case String.split(line, ",") do
              [track_id, class, color | _rest] ->
                Map.put(acc, track_id, %{class: class, color: color})

              _ ->
                acc
            end
          end)

        {:ok, map}

      {:error, :not_found} ->
        # Opcional: si no hay Re-ID, retornar un mapa vacío sin fallar
        {:ok, %{}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_plate_readings(lines) do
    # Cabecera: track_id,frame,crop_path,plate_text,ocr_confidence
    [_header | rest] = lines

    Enum.flat_map(rest, fn line ->
      case String.split(line, ",") do
        [track_id, frame, crop_path, plate_text, ocr_confidence] ->
          case Float.parse(ocr_confidence) do
            {conf_val, _} ->
              # Escalar confianza a 0.0 - 100.0
              scaled_conf = Float.round(conf_val * 100.0, 2)

              [%{
                track_id: track_id,
                frame: frame,
                crop_path: crop_path,
                plate_text: plate_text,
                confidence: scaled_conf
              }]

            _ ->
              []
          end

        _ ->
          []
      end
    end)
  end

  @doc """
  Ejecuta el pipeline de procesamiento de imágenes (YOLO, OCR, Re-ID) de forma asíncrona
  para una cámara específica utilizando su `stream_url` (ruta del video o fuente configurada).
  """
  def process_camera_video(camera_id) do
    camera = Repo.get!(Camera, camera_id)
    project_path = get_project_path()

    # --- Validaciones ANTES de lanzar el Task ---

    # 1. Verificar que el entorno Python existe
    python_exec =
      case :os.type() do
        {:win32, _} -> Path.join([project_path, ".venv", "Scripts", "python.exe"])
        _ -> Path.join([project_path, ".venv", "bin", "python"])
      end

    # Resolve stream_url to default "0" for webcams if empty/nil
    resolved_stream_url =
      if camera.source_type == "webcam" and (is_nil(camera.stream_url) or camera.stream_url == "") do
        "0"
      else
        camera.stream_url
      end

    pre_error =
      cond do
        # Sin URL/fuente configurada
        is_nil(resolved_stream_url) or resolved_stream_url == "" ->
          "Esta cámara no tiene una fuente de video configurada. " <>
            "Ve a Configuración → edita la cámara y asigna un archivo de video local o una URL de stream."

        # Archivo/directorio local que no existe
        camera.source_type in ["video", "directory"] and
          not String.starts_with?(resolved_stream_url, ["http://", "https://"]) and
          not File.exists?(resolved_stream_url) and
          not File.dir?(resolved_stream_url) ->
          "El archivo o directorio configurado no existe en disco: \"#{resolved_stream_url}\". " <>
            "Verifica la ruta en la configuración de esta cámara."

        # Entorno Python no instalado
        not File.exists?(python_exec) ->
          "El entorno virtual de Python no está instalado. " <>
            "Ejecuta: cd proyecto_sistema_inteligente && python3 -m venv .venv && .venv/bin/pip install ."

        true ->
          nil
      end

    if pre_error do
      # Emitir error de inmediato, sin lanzar el Task
      broadcast_pipeline_status(camera.id, {:failed, pre_error})
      {:error, pre_error}
    else
      video_path = resolved_stream_url

      # Rutas de salida para esta cámara
      output_ocr_path = "data/08_reporting/plate_readings_#{camera.code}.csv"
      output_reid_path = "data/08_reporting/reid_profiles_#{camera.code}.csv"
      output_video_path = "data/08_reporting/tracked_traffic_#{camera.code}.mp4"

      params_str =
        "video_path=#{video_path}," <>
        "output_ocr_path=#{output_ocr_path}," <>
        "output_reid_path=#{output_reid_path}," <>
        "output_video_path=#{output_video_path}"

      args = ["-m", "kedro", "run", "--params", params_str]

      # Ejecutar de forma asíncrona en un Task para no bloquear LiveView
      Task.start(fn ->
        broadcast_pipeline_status(camera.id, :started)

        Logger.info(
          "Iniciando procesamiento ALPR para cámara #{camera.code} " <>
          "(#{camera.source_type}): #{video_path}"
        )

        # PYTHONWARNINGS=ignore: Kedro 1.3.x no es compatible con Python 3.14
        # y lanza una advertencia que bloquea la ejecución por defecto.
        cmd_env = %{"PYTHONWARNINGS" => "ignore"}

        case System.cmd(python_exec, args, cd: project_path, env: cmd_env, stderr_to_stdout: true) do
          {_output, 0} ->
            Logger.info("Pipeline ALPR completado para cámara #{camera.code}")

            case sync_detections(camera.id) do
              {:ok, %{created: 0, skipped: 0}} ->
                broadcast_pipeline_status(
                  camera.id,
                  {:completed, %{created: 0, skipped: 0, errors: 0}}
                )

              {:ok, stats} ->
                broadcast_pipeline_status(camera.id, {:completed, stats})

              {:error, reason} ->
                broadcast_pipeline_status(
                  camera.id,
                  {:failed, "Sincronización fallida: #{inspect(reason)}"}
                )
            end

          {output, code} ->
            # Extraer solo las últimas líneas relevantes del error para el mensaje
            error_lines =
              output
              |> String.split("\n")
              |> Enum.filter(&(String.contains?(&1, ["ERROR", "Error", "error", "Exception"])))
              |> Enum.take(-3)
              |> Enum.join(" | ")

            msg =
              if error_lines != "",
                do: "Error en el pipeline (código #{code}): #{error_lines}",
                else: "El pipeline falló con código #{code}. Revisa los logs del servidor."

            Logger.error("Pipeline ALPR falló para #{camera.code} (código #{code}):\n#{output}")
            broadcast_pipeline_status(camera.id, {:failed, msg})
        end
      end)

      {:ok, self()}
    end
  end

  defp broadcast_pipeline_status(camera_id, status) do
    Phoenix.PubSub.broadcast(
      Vehiscan.PubSub,
      "monitoring:events",
      {:pipeline_status, camera_id, status}
    )
  end
end
