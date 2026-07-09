defmodule Vehiscan.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :email, :string, null: false
      add :password_hash, :string, null: false
      add :status, :string, null: false, default: "active"
      add :last_login_at, :utc_datetime_usec
      add :permissions, {:array, :string}, default: []
      add :role_id, references(:roles, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:email])
    create index(:users, [:role_id])
    create index(:users, [:status])
  end
end
