defmodule Vehiscan.Governance.AuditLog do
  @moduledoc """
  Esquema Ecto para el log de auditoría inmutable.
  Registra toda acción sensible: búsquedas, reportes y accesos.
  Los registros NUNCA se borran (protegidos a nivel de política de BD).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "audit_logs" do
    field :action, :string
    field :plate_queried, :string
    field :filters_applied, :map, default: %{}
    field :justification, :string
    field :result_count, :integer
    field :ip_address, :string

    belongs_to :user, Vehiscan.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(log, attrs) do
    log
    |> cast(attrs, [:action, :plate_queried, :filters_applied, :justification, :result_count, :ip_address, :user_id])
    |> validate_required([:action, :user_id])
    |> validate_length(:action, min: 3, max: 100)
    |> validate_justification_if_plate_queried()
  end

  @doc """
  Crea un log de auditoría para búsqueda de placas.
  Requiere justificación obligatoria.
  """
  def plate_query_changeset(log, attrs) do
    log
    |> cast(attrs, [:plate_queried, :filters_applied, :justification, :result_count, :ip_address, :user_id])
    |> put_change(:action, "plate_query")
    |> validate_required([:plate_queried, :justification, :user_id, :ip_address])
    |> validate_length(:justification, min: 10, message: "La justificación debe tener al menos 10 caracteres")
  end

  defp validate_justification_if_plate_queried(changeset) do
    plate = get_field(changeset, :plate_queried)
    justification = get_field(changeset, :justification)

    if plate && (is_nil(justification) || String.length(justification) < 10) do
      add_error(changeset, :justification, "es obligatoria cuando se consulta una placa")
    else
      changeset
    end
  end
end
