defmodule VehiscanWeb.CropController do
  use VehiscanWeb, :controller

  alias Vehiscan.Repo
  alias Vehiscan.Config.Configuration

  # Solo permitir nombres de archivo de crops válidos para evitar directory traversal
  @crop_regex ~r/^vehicle_-?\d+_frame_\d+\.(jpg|jpeg|png)$/i

  def show(conn, %{"filename" => filename}) do
    IO.inspect(filename, label: "CROP_CONTROLLER_FILENAME")
    if String.match?(filename, @crop_regex) do
      project_path = get_project_path()
      # En Windows y UNIX, Path.join maneja separadores correctamente
      crops_dir = Path.join([project_path, "data", "02_intermediate", "crops"])
      full_path = Path.join(crops_dir, filename)

      if File.exists?(full_path) do
        conn
        |> put_resp_content_type("image/jpeg")
        |> send_file(200, full_path)
      else
        conn
        |> send_resp(404, "Crop image not found on disk")
      end
    else
      conn
      |> send_resp(400, "Invalid crop filename format")
    end
  end

  defp get_project_path do
    Configuration.get_resolved_path()
  end
end
