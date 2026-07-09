defmodule Vehiscan.Repo.Migrations.CreateGeofences do
  use Ecto.Migration

  def change do
    create table(:geofences, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :type, :string, null: false, default: "polygon"
      add :coordinates, :map, null: false
      add :zone, :string
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:geofences, [:name])
    create index(:geofences, [:zone])
    create index(:geofences, [:status])
  end
end
