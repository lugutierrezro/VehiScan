defmodule Vehiscan.Config.Configuration do
  @moduledoc """
  Esquema Ecto para la configuración dinámica del sistema.
  Permite ajustar parámetros operativos (retención de datos, umbrales ALPR, etc.)
  sin necesidad de redeploy. Los cambios quedan registrados con usuario responsable.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:parameter_key, :string, autogenerate: false}
  @foreign_key_type :binary_id

  schema "configurations" do
    field :value, :string
    field :module, :string
    field :updated_at, :utc_datetime_usec

    belongs_to :updated_by, Vehiscan.Accounts.User, foreign_key: :updated_by_id
  end

  @doc false
  def changeset(config, attrs) do
    config
    |> cast(attrs, [:parameter_key, :value, :module, :updated_by_id])
    |> validate_required([:parameter_key, :value, :module])
    |> validate_length(:parameter_key, min: 3, max: 100)
    |> put_change(:updated_at, DateTime.utc_now())
  end

  @doc "Configuraciones por defecto del sistema."
  def defaults do
    [
      %{parameter_key: "data_retention_days", value: "90", module: "governance"},
      %{parameter_key: "alpr_confidence_threshold", value: "75.0", module: "alpr"},
      %{parameter_key: "alert_expiry_hours", value: "48", module: "monitoring"},
      %{parameter_key: "max_search_results", value: "1000", module: "search"},
      %{parameter_key: "report_max_days_range", value: "365", module: "reporting"}
    ]
  end

  @doc """
  Resuelve la ruta del proyecto de Python. Si la ruta almacenada en la base de datos
  es inválida o no contiene los archivos necesarios, se corrige automáticamente
  y se actualiza en la base de datos de manera autocurativa.
  """
  def get_resolved_path do
    default_path = Path.join(File.cwd!(), "proyecto_sistema_inteligente")

    case Vehiscan.Repo.get(__MODULE__, "python_project_path") do
      nil ->
        if File.dir?(default_path) do
          insert_path(default_path)
          default_path
        else
          priv_path = Path.expand("../../../proyecto_sistema_inteligente", :code.priv_dir(:vehiscan))
          insert_path(priv_path)
          priv_path
        end

      config ->
        value = config.value
        if File.dir?(value) and File.exists?(Path.join(value, "stream_camera.py")) do
          value
        else
          # La ruta en DB es inválida o corrupta. Repararla automáticamente.
          if File.dir?(default_path) and File.exists?(Path.join(default_path, "stream_camera.py")) do
            update_path(config, default_path)
            default_path
          else
            priv_path = Path.expand("../../../proyecto_sistema_inteligente", :code.priv_dir(:vehiscan))
            if File.dir?(priv_path) do
              update_path(config, priv_path)
              priv_path
            else
              # Si falla todo, retornar la ruta por defecto
              default_path
            end
          end
        end
    end
  end

  defp insert_path(path) do
    %__MODULE__{}
    |> changeset(%{parameter_key: "python_project_path", value: path, module: "integrations"})
    |> Vehiscan.Repo.insert()
  end

  defp update_path(config, path) do
    config
    |> changeset(%{value: path})
    |> Vehiscan.Repo.update()
  end
end
