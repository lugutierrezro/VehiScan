defmodule Vehiscan.Repo.Migrations.CreateAuditLogs do
  use Ecto.Migration

  def change do
    create table(:audit_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :action, :string, null: false
      add :plate_queried, :string
      add :filters_applied, :map, default: %{}
      add :justification, :text
      add :result_count, :integer
      add :ip_address, :string
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:audit_logs, [:user_id])
    create index(:audit_logs, [:action])
    create index(:audit_logs, [:plate_queried])
    create index(:audit_logs, [:inserted_at])
  end
end
