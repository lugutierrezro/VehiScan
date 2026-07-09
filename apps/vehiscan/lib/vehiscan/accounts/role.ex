defmodule Vehiscan.Accounts.Role do
  @moduledoc """
  Esquema Ecto para los roles del sistema.
  Define los niveles de acceso: Operador, Investigador, Auditor, Administrador.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "roles" do
    field :name, :string
    field :description, :string
    field :permissions, {:array, :string}, default: []
    field :access_level, :integer, default: 0

    has_many :users, Vehiscan.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :description, :permissions, :access_level])
    |> validate_required([:name, :access_level])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_inclusion(:access_level, 0..10)
    |> unique_constraint(:name)
  end
end
