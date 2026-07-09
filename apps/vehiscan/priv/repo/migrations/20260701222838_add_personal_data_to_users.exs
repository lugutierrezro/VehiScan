defmodule Vehiscan.Repo.Migrations.AddPersonalDataToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :dni, :string, size: 20
      add :phone, :string, size: 20
    end
    
    create unique_index(:users, [:dni])
  end
end
