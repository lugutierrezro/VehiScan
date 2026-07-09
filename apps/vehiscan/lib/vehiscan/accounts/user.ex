defmodule Vehiscan.Accounts.User do
  @moduledoc """
  Esquema Ecto para los usuarios del sistema.
  Utiliza pbkdf2_elixir para el hashing seguro de contraseñas.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :name, :string
    field :email, :string
    field :password, :string, virtual: true
    field :password_hash, :string
    field :avatar_url, :string
    field :dni, :string
    field :phone, :string
    field :status, :string, default: "active"
    field :last_login_at, :utc_datetime_usec
    field :permissions, {:array, :string}, default: []

    belongs_to :role, Vehiscan.Accounts.Role
    has_many :audit_logs, Vehiscan.Governance.AuditLog
    has_many :watchlists_assigned, Vehiscan.Monitoring.Watchlist, foreign_key: :assigned_by_id
    has_many :alerts_operated, Vehiscan.Monitoring.Alert, foreign_key: :operator_id
    has_many :reports, Vehiscan.Reporting.Report

    timestamps(type: :utc_datetime_usec)
  end

  @valid_statuses ~w(active inactive suspended)

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :password, :status, :permissions, :role_id, :avatar_url, :dni, :phone])
    |> validate_required([:name, :email, :password, :role_id, :dni, :phone])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_length(:email, max: 160)
    |> validate_length(:password, min: 8, max: 72)
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint(:email)
    |> unique_constraint(:dni)
    |> hash_password()
  end

  @doc false
  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :status, :permissions, :role_id, :avatar_url, :dni, :phone])
    |> validate_required([:name, :role_id])
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint(:dni)
  end

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    changeset
    |> put_change(:password_hash, Pbkdf2.hash_pwd_salt(password))
    |> delete_change(:password)
  end

  defp hash_password(changeset), do: changeset

  @doc "Verifica si la contraseña proporcionada coincide con el hash almacenado."
  def verify_password(user, password) do
    Pbkdf2.verify_pass(password, user.password_hash)
  end
end
