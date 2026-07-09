defmodule Vehiscan.Repo.Migrations.CreateAlprEvents do
  use Ecto.Migration

  def change do
    create table(:alpr_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :normalized_plate, :string, null: false
      add :original_plate, :string, null: false
      add :confidence, :float, null: false
      add :plate_image_url, :string
      add :context_image_url, :string
      add :status, :string, null: false, default: "new"
      add :location_name, :string
      add :camera_id, references(:cameras, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    # GIN index for fast plate text searches
    execute(
      "CREATE INDEX alpr_events_normalized_plate_gin_idx ON alpr_events USING gin(normalized_plate gin_trgm_ops)",
      "DROP INDEX IF EXISTS alpr_events_normalized_plate_gin_idx"
    )

    create index(:alpr_events, [:camera_id])
    create index(:alpr_events, [:inserted_at])
    create index(:alpr_events, [:normalized_plate])
    create index(:alpr_events, [:status])
  end
end
