defmodule Vehiscan.Repo.Migrations.CreateAlerts do
  use Ecto.Migration

  def change do
    create table(:alerts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :severity, :string, null: false, default: "medium"
      add :status, :string, null: false, default: "pending"
      add :validation_details, :text
      add :alpr_event_id, references(:alpr_events, type: :binary_id, on_delete: :restrict), null: false
      add :watchlist_id, references(:watchlists, type: :binary_id, on_delete: :restrict), null: false
      add :operator_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:alerts, [:status])
    create index(:alerts, [:severity])
    create index(:alerts, [:alpr_event_id])
    create index(:alerts, [:watchlist_id])
    create index(:alerts, [:operator_id])
    create index(:alerts, [:inserted_at])
  end
end
