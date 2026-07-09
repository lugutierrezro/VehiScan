defmodule Vehiscan.Repo.Migrations.CreateOlapCube do
  use Ecto.Migration

  def change do
    create table(:dim_date, primary_key: false) do
      add :id, :date, primary_key: true
      add :year, :integer, null: false
      add :month, :integer, null: false
      add :day, :integer, null: false
      add :day_of_week, :integer, null: false
    end

    create table(:dim_camera, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code, :string, null: false
      add :location_name, :string
      add :zone, :string
    end

    create table(:fact_alpr_readings, primary_key: false) do
      add :id, :serial, primary_key: true
      add :dim_date_id, references(:dim_date, type: :date), null: false
      add :dim_camera_id, references(:dim_camera, type: :binary_id), null: false
      add :total_readings, :integer, default: 0
      add :high_confidence_readings, :integer, default: 0
      add :watchlisted_readings, :integer, default: 0
    end
    
    create unique_index(:fact_alpr_readings, [:dim_date_id, :dim_camera_id])
  end
end
