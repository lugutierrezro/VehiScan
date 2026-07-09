defmodule Vehiscan.Monitoring.ObservedVehicle do
  @moduledoc """
  Esquema Ecto para vehículos observados (perfil agregado por placa).
  Acumula estadísticas y atributos detectados de un vehículo a lo largo del tiempo.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:plate, :string, autogenerate: false}

  schema "observed_vehicles" do
    field :detected_attributes, :map, default: %{}
    field :frequency, :integer, default: 0
    field :last_seen_at, :utc_datetime_usec
    field :interest_status, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(vehicle, attrs) do
    vehicle
    |> cast(attrs, [:plate, :detected_attributes, :frequency, :last_seen_at, :interest_status])
    |> validate_required([:plate])
    |> validate_length(:plate, min: 2, max: 20)
    |> validate_number(:frequency, greater_than_or_equal_to: 0)
    |> update_change(:plate, &String.upcase/1)
  end

  @doc "Incrementa la frecuencia de detección y actualiza last_seen_at."
  def increment_detection_changeset(vehicle) do
    now = DateTime.utc_now()

    vehicle
    |> change(%{
      frequency: vehicle.frequency + 1,
      last_seen_at: now
    })
  end
end
