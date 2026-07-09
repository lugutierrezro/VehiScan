defmodule Vehiscan.Repo.Migrations.CreateCameras do
  use Ecto.Migration

  def change do
    create table(:cameras, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code, :string, null: false
      add :type, :string, null: false
      add :location_name, :string, null: false
      add :latitude, :float
      add :longitude, :float
      add :orientation, :string
      add :status, :string, null: false, default: "active"
      add :stream_url, :string
      add :zone, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:cameras, [:code])
    create index(:cameras, [:zone])
    create index(:cameras, [:status])
  end
end
