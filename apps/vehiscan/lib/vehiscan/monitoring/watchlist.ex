defmodule Vehiscan.Monitoring.Watchlist do
  @moduledoc """
  Esquema Ecto para la lista de interés (watchlist).
  Registra placas bajo vigilancia con su fuente institucional, razón y severidad.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "watchlists" do
    field :plate, :string
    field :source, :string
    field :reason, :string
    field :severity, :string, default: "medium"
    field :start_date, :date
    field :end_date, :date
    field :status, :string, default: "active"

    belongs_to :assigned_by, Vehiscan.Accounts.User, foreign_key: :assigned_by_id
    has_many :alerts, Vehiscan.Monitoring.Alert

    timestamps(type: :utc_datetime_usec)
  end

  @valid_severities ~w(high medium low)
  @valid_statuses ~w(active inactive expired)

  @doc false
  def changeset(watchlist, attrs) do
    watchlist
    |> cast(attrs, [:plate, :source, :reason, :severity, :start_date, :end_date, :status, :assigned_by_id])
    |> validate_required([:plate, :source, :reason, :severity])
    |> validate_inclusion(:severity, @valid_severities)
    |> validate_inclusion(:status, @valid_statuses)
    |> update_change(:plate, &String.upcase/1)
    |> validate_date_range()
  end

  defp validate_date_range(changeset) do
    start_date = get_field(changeset, :start_date)
    end_date = get_field(changeset, :end_date)

    if start_date && end_date && Date.compare(end_date, start_date) == :lt do
      add_error(changeset, :end_date, "must be after start_date")
    else
      changeset
    end
  end
end
