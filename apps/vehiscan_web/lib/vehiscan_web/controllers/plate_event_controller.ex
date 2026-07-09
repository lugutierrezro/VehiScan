defmodule VehiscanWeb.PlateEventController do
  @moduledoc """
  Endpoint interno que recibe detecciones de placa desde el proceso Python (stream_camera.py).
  Python hace un HTTP POST a /api/plate_event cuando EasyOCR detecta una matrícula con
  suficiente confianza. Este controlador registra el evento en la base de datos y lo
  transmite en tiempo real a todos los LiveViews conectados vía PubSub.
  """
  use VehiscanWeb, :controller

  alias Vehiscan.Repo
  alias Vehiscan.Infrastructure.Camera
  alias Vehiscan.Monitoring

  # Token secreto compartido con stream_camera.py para evitar acceso no autorizado
  @internal_token "vehiscan_stream_internal_2024"

  def create(conn, params) do
    # Verificar token de autenticación interna
    token = get_req_header(conn, "x-internal-token") |> List.first()

    if token != @internal_token do
      conn
      |> put_status(401)
      |> json(%{error: "Unauthorized"})
    else
      handle_plate_event(conn, params)
    end
  end

  defp handle_plate_event(conn, %{
    "plate" => plate,
    "confidence" => confidence,
    "vehicle_class" => vehicle_class,
    "camera_id" => camera_id
  } = params) do
    camera = Repo.get(Camera, camera_id)

    vehicle_color = Map.get(params, "vehicle_color", "unknown")
    crop_filename = Map.get(params, "crop_filename")

    plate_image_url =
      if crop_filename && crop_filename != "" do
        "attributes|class:#{vehicle_class}|color:#{vehicle_color}|crop:#{crop_filename}"
      else
        "attributes|class:#{vehicle_class}|color:#{vehicle_color}"
      end

    attrs = %{
      original_plate: plate,
      normalized_plate: plate,
      confidence: confidence,
      camera_id: camera_id,
      location_name: (if camera, do: camera.location_name, else: "Desconocido"),
      status: "new",
      plate_image_url: plate_image_url
    }

    case Monitoring.register_alpr_event(attrs) do
      {:ok, %{event: event}} ->
        IO.puts("[ALPR] Placa registrada: #{plate} (#{confidence}%) cam=#{if camera, do: camera.code, else: camera_id}")

        conn
        |> put_status(201)
        |> json(%{
          status: "ok",
          event_id: event.id,
          plate: event.normalized_plate
        })

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Enum.reduce(opts, msg, fn {key, value}, acc ->
              String.replace(acc, "%{#{key}}", to_string(value))
            end)
          end)

        IO.inspect(errors, label: "[ALPR] Error al registrar placa #{plate}")

        conn
        |> put_status(422)
        |> json(%{error: errors})
    end
  end

  defp handle_plate_event(conn, params) do
    IO.inspect(params, label: "[ALPR] Parámetros inválidos recibidos")

    conn
    |> put_status(400)
    |> json(%{error: "Parámetros requeridos: plate, confidence, vehicle_class, camera_id"})
  end
end
