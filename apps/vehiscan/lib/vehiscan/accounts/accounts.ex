defmodule Vehiscan.Accounts do
  @moduledoc """
  Contexto de Cuentas de Vehiscan.
  Gestiona usuarios, roles y autenticación.
  """

  import Ecto.Query
  alias Vehiscan.Repo
  alias Vehiscan.Accounts.{User, Role}

  # ─── Roles ────────────────────────────────────────────────────────────────────

  @doc "Lista todos los roles disponibles."
  def list_roles, do: Repo.all(Role)

  @doc "Crea los roles del sistema por defecto si no existen."
  def seed_default_roles do
    default_roles = [
      %{name: "operator", description: "Monitoreo y validación de alertas", access_level: 1,
        permissions: ["view_dashboard", "validate_alerts", "view_cameras"]},
      %{name: "investigator", description: "Consultas investigativas bajo justificación", access_level: 2,
        permissions: ["view_dashboard", "search_plates", "view_reports", "generate_reports"]},
      %{name: "auditor", description: "Revisión de logs de auditoría", access_level: 3,
        permissions: ["view_audit_logs", "view_dashboard"]},
      %{name: "admin", description: "Administración completa del sistema", access_level: 10,
        permissions: ["*"]}
    ]

    Enum.each(default_roles, fn attrs ->
      case Repo.get_by(Role, name: attrs.name) do
        nil ->
          %Role{} |> Role.changeset(attrs) |> Repo.insert!()
        _ -> :ok
      end
    end)
  end

  # ─── Usuarios ─────────────────────────────────────────────────────────────────

  @doc "Lista todos los usuarios activos con su rol cargado."
  def list_active_users do
    User
    |> where([u], u.status == "active")
    |> preload(:role)
    |> Repo.all()
  end

  @doc "Obtiene un usuario por email."
  def get_user_by_email(email) do
    User
    |> where([u], u.email == ^email)
    |> preload(:role)
    |> Repo.one()
  end

  @doc "Obtiene un usuario por ID con su rol."
  def get_user!(id) do
    User
    |> preload(:role)
    |> Repo.get!(id)
  end

  @doc "Crea un nuevo usuario con el rol especificado."
  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Actualiza los datos de un usuario."
  def update_user(user, attrs) do
    user
    |> User.update_changeset(attrs)
    |> Repo.update()
  end

  @doc "Desactiva un usuario (soft delete)."
  def deactivate_user(user) do
    user
    |> User.update_changeset(%{status: "inactive"})
    |> Repo.update()
  end

  # ─── Autenticación ───────────────────────────────────────────────────────────

  @doc """
  Autentica un usuario por email y contraseña.
  Actualiza `last_login_at` al autenticar exitosamente.
  Devuelve `{:ok, user}` o `{:error, :invalid_credentials}`.
  """
  def authenticate_user(email, password) do
    user = get_user_by_email(email)

    cond do
      is_nil(user) ->
        # Previene timing attacks ejecutando el hash igualmente
        Pbkdf2.no_user_verify()
        {:error, :invalid_credentials}

      user.status != "active" ->
        {:error, :account_inactive}

      not User.verify_password(user, password) ->
        {:error, :invalid_credentials}

      true ->
        record_login(user)
        {:ok, user}
    end
  end

  @doc "Verifica si un usuario tiene un permiso específico."
  def has_permission?(user, permission) do
    user_permissions = user.permissions ++ (user.role.permissions || [])
    "*" in user_permissions or permission in user_permissions
  end

  # ─── Privados ─────────────────────────────────────────────────────────────────

  defp record_login(user) do
    user
    |> Ecto.Changeset.change(%{last_login_at: DateTime.utc_now()})
    |> Repo.update()
  end
end
