defmodule VehiscanWeb.SessionController do
  use VehiscanWeb, :controller

  alias Vehiscan.Accounts
  alias Vehiscan.Governance
  alias VehiscanWeb.UserAuth

  def new(conn, _params) do
    render(conn, :new, error_message: nil)
  end

  def create(conn, %{"email" => email, "password" => password}) do
    ip = get_ip(conn)

    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        # Log the login action with the user's IP
        Vehiscan.Governance.log_action(user.id, "login", ip_address: ip, justification: "Inicio de sesión en el sistema")

        UserAuth.log_in_user(conn, user)

      {:error, reason} ->
        error_msg =
          case reason do
            :invalid_credentials -> "Credenciales incorrectas"
            :account_inactive -> "Cuenta inactiva. Contacte al administrador."
            _ -> "Error de autenticación"
          end

        render(conn, :new, error_message: error_msg)
    end
  end

  def delete(conn, _params) do
    if user = conn.assigns[:current_user] do
      ip = get_ip(conn)
      Governance.log_action(user.id, "user_logout", ip_address: ip)
    end

    UserAuth.log_out_user(conn)
  end

  defp get_ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end
end
