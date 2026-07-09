defmodule Vehiscan.Repo.Migrations.AddSourceTypeToCameras do
  use Ecto.Migration

  def change do
    alter table(:cameras) do
      add :source_type, :string, null: false, default: "video"
    end
  end
end
