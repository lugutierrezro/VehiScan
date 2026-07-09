defmodule Vehiscan.Repo.Migrations.CreateObservedVehicles do
  use Ecto.Migration

  def change do
    create table(:observed_vehicles, primary_key: false) do
      add :plate, :string, primary_key: true
      add :detected_attributes, :map, default: %{}
      add :frequency, :integer, null: false, default: 0
      add :last_seen_at, :utc_datetime_usec
      add :interest_status, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:observed_vehicles, [:interest_status])
    create index(:observed_vehicles, [:last_seen_at])
    create index(:observed_vehicles, [:frequency])
  end
end
