defmodule Vehiscan.Geo.Geofence do
  @moduledoc """
  Esquema Ecto para geocercas (áreas geográficas de monitoreo).
  Las coordenadas se almacenan como JSON GeoJSON compatible.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "geofences" do
    field :name, :string
    field :type, :string, default: "polygon"
    field :coordinates, :map
    field :zone, :string
    field :status, :string, default: "active"

    timestamps(type: :utc_datetime_usec)
  end

  @valid_types ~w(polygon circle)
  @valid_statuses ~w(active inactive)

  @doc false
  def changeset(geofence, attrs) do
    geofence
    |> cast(attrs, [:name, :type, :coordinates, :zone, :status])
    |> validate_required([:name, :type, :coordinates])
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint(:name)
    |> validate_coordinates()
  end

  defp validate_coordinates(changeset) do
    case get_change(changeset, :coordinates) do
      nil ->
        changeset

      coords when is_map(coords) ->
        if Map.has_key?(coords, "type") do
          changeset
        else
          add_error(changeset, :coordinates, "must be a valid GeoJSON object with 'type' key")
        end

      _ ->
        add_error(changeset, :coordinates, "must be a map")
    end
  end
end
