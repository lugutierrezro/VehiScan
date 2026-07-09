defmodule Vehiscan.Monitoring.Alert do
  @moduledoc """
  Esquema Ecto para las alertas generadas cuando un evento ALPR
  coincide con una placa en la lista de interés (Watchlist).
  Requiere validación humana explícita del operador antes de cualquier acción.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "alerts" do
    field :severity, :string, default: "medium"
    field :status, :string, default: "pending"
    field :validation_details, :string

    belongs_to :alpr_event, Vehiscan.Monitoring.ALPREvent
    belongs_to :watchlist, Vehiscan.Monitoring.Watchlist
    belongs_to :operator, Vehiscan.Accounts.User, foreign_key: :operator_id

    timestamps(type: :utc_datetime_usec)
  end

  @valid_severities ~w(high medium low)
  @valid_statuses ~w(pending validated dismissed)

  @doc false
  def changeset(alert, attrs) do
    alert
    |> cast(attrs, [:severity, :status, :validation_details, :alpr_event_id, :watchlist_id, :operator_id])
    |> validate_required([:alpr_event_id, :watchlist_id])
    |> validate_inclusion(:severity, @valid_severities)
    |> validate_inclusion(:status, @valid_statuses)
  end

  @doc """
  Changeset de validación: requiere que el operador provea detalles antes de cerrar la alerta.
  """
  def validate_changeset(alert, attrs) do
    alert
    |> cast(attrs, [:status, :validation_details, :operator_id])
    |> validate_required([:status, :validation_details, :operator_id])
    |> validate_length(:validation_details, min: 10)
    |> validate_inclusion(:status, ~w(validated dismissed))
  end
end
