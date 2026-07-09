defmodule VehiscanWeb.UserAuth do
  @moduledoc """
  Módulo de ayuda para la autenticación y autorización de usuarios.
  Proporciona plugs para controladores y hooks on_mount para LiveViews.
  """
  use VehiscanWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Vehiscan.Accounts

  # ─── Plugs para Controladores (Rutas tradicionales HTTP) ───────────────────

  @doc """
  Carga el usuario actual a partir de la sesión de forma asíncrona o directa.
  Guarda el usuario en `conn.assigns.current_user`.
  """
  def fetch_current_user(conn, _opts) do
    user_id = get_session(conn, :user_id)
    user = user_id && Accounts.get_user!(user_id)
    assign(conn, :current_user, user)
  end

  @doc """
  Reclama que el usuario esté autenticado. De lo contrario, redirige a la página de login.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "Debe iniciar sesión para acceder a esta página.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  @doc """
  Redirige al dashboard si el usuario ya está autenticado.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: ~p"/")
      |> halt()
    else
      conn
    end
  end

  # ─── Sesión e Inicio/Cierre ───────────────────────────────────────────────

  @doc """
  Inicia sesión de un usuario.
  Renueva la sesión para evitar ataques de fijación de sesión.
  """
  def log_in_user(conn, user, _params \\ %{}) do
    return_to = get_session(conn, :user_return_to)
    ip_address = conn.remote_ip |> :inet.ntoa() |> to_string()

    conn
    |> renew_session()
    |> put_session(:user_id, user.id)
    |> put_session(:user_ip, ip_address)
    |> put_session(:live_socket_id, "users_sessions:#{user.id}")
    |> put_flash(:info, "¡Bienvenido, #{user.name}!")
    |> redirect(to: return_to || ~p"/")
  end

  @doc """
  Cierra la sesión del usuario.
  """
  def log_out_user(conn) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "Sesión cerrada correctamente.")
    |> redirect(to: ~p"/login")
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, conn.request_path)
  end

  defp maybe_store_return_to(conn), do: conn

  # ─── Hooks de Montaje para LiveView (on_mount) ─────────────────────────────

  @doc """
  Hook on_mount para LiveView.
  """
  def on_mount(key, _params, session, socket) do
    case key do
      :mount_current_user ->
        {:cont, mount_current_user(session, socket)}

      :ensure_authenticated ->
        socket = mount_current_user(session, socket)

        if socket.assigns.current_user do
          {:cont, socket}
        else
          socket =
            socket
            |> Phoenix.LiveView.put_flash(:error, "Debe iniciar sesión para acceder.")
            |> Phoenix.LiveView.redirect(to: ~p"/login")

          {:halt, socket}
        end

      :ensure_admin ->
        socket = mount_current_user(session, socket)
        user = socket.assigns.current_user

        if user && Accounts.has_permission?(user, "*") do
          {:cont, socket}
        else
          socket =
            socket
            |> Phoenix.LiveView.put_flash(:error, "Acceso no autorizado.")
            |> Phoenix.LiveView.redirect(to: ~p"/")

          {:halt, socket}
        end
    end
  end

  defp mount_current_user(session, socket) do
    user_ip = Map.get(session, "user_ip", "127.0.0.1")
    socket = Phoenix.Component.assign_new(socket, :current_ip, fn -> user_ip end)

    case session["user_id"] do
      nil ->
        Phoenix.Component.assign_new(socket, :current_user, fn -> nil end)

      user_id ->
        Phoenix.Component.assign_new(socket, :current_user, fn ->
          Accounts.get_user!(user_id)
        end)
    end
  end
end
