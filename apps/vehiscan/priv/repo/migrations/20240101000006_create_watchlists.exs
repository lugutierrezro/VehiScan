defmodule Vehiscan.Repo.Migrations.CreateWatchlists do
  use Ecto.Migration

  def change do
    create table(:watchlists, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :plate, :string, null: false
      add :source, :string, null: false
      add :reason, :text, null: false
      add :severity, :string, null: false, default: "medium"
      add :start_date, :date
      add :end_date, :date
      add :status, :string, null: false, default: "active"
      add :assigned_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:watchlists, [:plate])
    create index(:watchlists, [:severity])
    create index(:watchlists, [:status])
    create index(:watchlists, [:assigned_by_id])
  end
end
