defmodule Vehiscan.Repo.Migrations.CreateConfigurations do
  use Ecto.Migration

  def change do
    create table(:configurations, primary_key: false) do
      add :parameter_key, :string, primary_key: true
      add :value, :text, null: false
      add :module, :string, null: false
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :updated_at, :utc_datetime_usec, null: false
    end

    create index(:configurations, [:module])
    create index(:configurations, [:updated_by_id])
  end
end
