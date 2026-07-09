defmodule Vehiscan.Repo.Migrations.CreateOfficialIntegrations do
  use Ecto.Migration

  def change do
    create table(:official_integrations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :entity_name, :string, null: false
      add :type, :string, null: false
      add :credentials, :map, default: %{}
      add :agreement_details, :text
      add :status, :string, null: false, default: "active"
      add :last_sync_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:official_integrations, [:entity_name])
    create index(:official_integrations, [:status])
    create index(:official_integrations, [:type])
  end
end
