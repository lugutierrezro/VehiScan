defmodule VehiscanWeb.UsersLive do
  use VehiscanWeb, :live_view

  alias Vehiscan.Repo
  alias Vehiscan.Accounts.{User, Role}
  alias Vehiscan.Governance.AuditLog
  import Ecto.Query

  on_mount {VehiscanWeb.UserAuth, :ensure_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    current_user = Repo.preload(socket.assigns.current_user, :role)

    if current_user.role.name != "admin" do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      # Fetch roles
    roles = Repo.all(Role)
    
    # Fetch users with preloaded roles
    users = Repo.all(from u in User, preload: [:role])

    # Fetch recent audit logs
    audit_logs = Repo.all(
      from a in AuditLog,
      order_by: [desc: a.inserted_at],
      limit: 20
    )

    # Initialize empty form
    changeset = User.changeset(%User{}, %{})

    socket =
      socket
      |> assign(
        current_page: :users,
        page_title: "Gestión de Personal y Auditoría",
        users: users,
        roles: roles,
        audit_logs: audit_logs,
        show_modal: false,
        form_error: nil,
        form: to_form(changeset)
      )
      |> allow_upload(:avatar, accept: ~w(.jpg .jpeg .png), max_entries: 1, max_file_size: 5_000_000)

      {:ok, socket, layout: false}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    if params["action"] == "new" do
      {:noreply, assign(socket, show_modal: true, form_error: nil)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("open-new-user-modal", _, socket) do
    {:noreply, assign(socket, show_modal: true, form_error: nil)}
  end

  @impl true
  def handle_event("close-modal", _, socket) do
    {:noreply, assign(socket, show_modal: false, form_error: nil)}
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = User.changeset(%User{}, user_params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, form: to_form(changeset))}
  end
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("save-user", %{"user" => user_params}, socket) do
    # Assign default password if empty or nil
    password = Map.get(user_params, "password")
    user_params = 
      if password in [nil, ""] do
        Map.put(user_params, "password", "Temporal123!")
      else
        user_params
      end
    
    # Manejar subida de avatar
    uploaded_files =
      consume_uploaded_entries(socket, :avatar, fn %{path: path}, entry ->
        dest = Path.join([:code.priv_dir(:vehiscan_web), "static", "uploads", "#{entry.uuid}-#{entry.client_name}"])
        File.mkdir_p!(Path.dirname(dest))
        File.cp!(path, dest)
        {:ok, "/uploads/#{entry.uuid}-#{entry.client_name}"}
      end)

    user_params =
      case uploaded_files do
        [avatar_url] -> Map.put(user_params, "avatar_url", avatar_url)
        _ -> user_params
      end

    changeset = User.changeset(%User{}, user_params)

    case Repo.insert(changeset) do
      {:ok, user} ->
        # Log creation
        Vehiscan.Governance.log_action(
          socket.assigns.current_user.id,
          "create_user",
          ip_address: socket.assigns.current_ip,
          justification: "Usuario #{user.name} (#{user.email}) creado en el sistema con rol #{user.role_id}"
        )
        
        # Reload lists
        users = Repo.all(from u in User, preload: [:role])
        audit_logs = Repo.all(from a in AuditLog, order_by: [desc: a.inserted_at], limit: 20)
        
        {:noreply, 
          socket
          |> put_flash(:info, "Personal agregado correctamente.")
          |> assign(users: users, audit_logs: audit_logs, show_modal: false)}
      {:error, changeset} ->
        error_msg =
          changeset.errors
          |> Enum.map(fn {k, {msg, opts}} -> 
            msg = Enum.reduce(opts, msg, fn {key, val}, acc -> 
              String.replace(acc, "%{#{key}}", to_string(val))
            end)
            "#{k}: #{msg}" 
          end)
          |> Enum.join(", ")

        {:noreply, assign(socket, form_error: "Error al registrar el usuario: #{error_msg}")}
    end
  end
  defp error_to_string(:too_large), do: "El archivo es demasiado grande."
  defp error_to_string(:too_many_files), do: "Solo puedes subir un archivo."
  defp error_to_string(:not_accepted), do: "Tipo de archivo no permitido."
end
