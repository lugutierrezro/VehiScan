defmodule Vehiscan.Integrations.OfficialIntegration do
  @moduledoc """
  Esquema Ecto para integraciones con entidades oficiales (Policía, Municipio, etc.).
  Las credenciales se almacenan como mapa y deben ser encriptadas en la aplicación
  antes de persistir (usando Cloak o equivalente en Fase 3).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "official_integrations" do
    field :entity_name, :string
    field :type, :string
    field :credentials, :map, default: %{}
    field :agreement_details, :string
    field :status, :string, default: "active"
    field :last_sync_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @valid_types ~w(api sftp webhook)
  @valid_statuses ~w(active inactive suspended)

  @doc false
  def changeset(integration, attrs) do
    integration
    |> cast(attrs, [:entity_name, :type, :credentials, :agreement_details, :status, :last_sync_at])
    |> validate_required([:entity_name, :type])
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint(:entity_name)
  end
end
