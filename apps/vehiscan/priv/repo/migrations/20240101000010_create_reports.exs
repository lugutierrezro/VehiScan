defmodule Vehiscan.Repo.Migrations.CreateReports do
  use Ecto.Migration

  def change do
    create table(:reports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :filters_used, :map, default: %{}
      add :file_url, :string
      add :file_hash, :string
      add :status, :string, null: false, default: "pending"
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:reports, [:user_id])
    create index(:reports, [:status])
    create index(:reports, [:type])
    create index(:reports, [:inserted_at])
  end
end
