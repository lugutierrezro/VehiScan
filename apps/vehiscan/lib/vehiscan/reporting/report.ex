defmodule Vehiscan.Reporting.Report do
  @moduledoc """
  Esquema Ecto para reportes generados (PDF/CSV).
  Incluye hash SHA-256 para verificación de integridad (cadena de custodia digital).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "reports" do
    field :type, :string
    field :filters_used, :map, default: %{}
    field :file_url, :string
    field :file_hash, :string
    field :status, :string, default: "pending"

    belongs_to :user, Vehiscan.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @valid_types ~w(pdf csv)
  @valid_statuses ~w(pending generating completed failed)

  @doc false
  def changeset(report, attrs) do
    report
    |> cast(attrs, [:type, :filters_used, :file_url, :file_hash, :status, :user_id])
    |> validate_required([:type, :user_id])
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:status, @valid_statuses)
  end

  @doc "Changeset para marcar el reporte como completado con URL e integridad."
  def complete_changeset(report, file_url, file_hash) do
    report
    |> change(%{status: "completed", file_url: file_url, file_hash: file_hash})
    |> validate_required([:file_url, :file_hash])
    |> validate_format(:file_hash, ~r/^[a-f0-9]{64}$/, message: "must be a valid SHA-256 hex string")
  end
end
