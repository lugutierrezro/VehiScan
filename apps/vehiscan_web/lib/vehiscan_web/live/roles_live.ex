defmodule VehiscanWeb.RolesLive do
  use VehiscanWeb, :live_view

  alias Vehiscan.Repo
  alias Vehiscan.Accounts.Role
  import Ecto.Query

  on_mount {VehiscanWeb.UserAuth, :ensure_authenticated}
  # En producción, esto debería usar :ensure_admin para que solo los admins modifiquen roles.

  @impl true
  def mount(_params, _session, socket) do
    roles = Repo.all(from r in Role, order_by: r.access_level)
    
    socket =
      socket
      |> assign(
        current_page: :users,
        roles: roles,
        show_modal: false,
        editing_role: nil,
        form_error: nil,
        available_views: [
          {"dashboard", "Dashboard Principal", "Acceso al panel inicial"},
          {"search", "Buscador de Placas", "Búsqueda de eventos por matrícula"},
          {"reports", "Reportes", "Generación y descarga de PDF"},
          {"olap", "Analítica OLAP", "Métricas avanzadas e inteligencia"},
          {"users", "Gestión Personal", "Directorio y Auditoría"},
          {"cameras", "Cámaras", "Monitoreo en vivo y mapas"},
          {"config", "Configuración", "Ajustes del sistema"}
        ]
      )

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_event("new-role", _, socket) do
    {:noreply, assign(socket, show_modal: true, editing_role: %Role{permissions: []}, form_error: nil)}
  end
  
  @impl true
  def handle_event("edit-role", %{"id" => id}, socket) do
    role = Repo.get!(Role, id)
    {:noreply, assign(socket, show_modal: true, editing_role: role, form_error: nil)}
  end

  @impl true
  def handle_event("close-modal", _, socket) do
    {:noreply, assign(socket, show_modal: false, editing_role: nil, form_error: nil)}
  end
  
  @impl true
  def handle_event("save-role", params, socket) do
    # Extraer permisos de checkboxes dinamicos
    role_params = params["role"]
    permissions = Map.get(params, "permissions", %{}) |> Map.keys()
    
    attrs = %{
      name: role_params["name"],
      description: role_params["description"],
      access_level: String.to_integer(role_params["access_level"] || "0"),
      permissions: permissions
    }
    
    changeset = 
      if socket.assigns.editing_role.id do
        Role.changeset(socket.assigns.editing_role, attrs)
      else
        Role.changeset(%Role{}, attrs)
      end

    case Repo.insert_or_update(changeset) do
      {:ok, role} ->
        Vehiscan.Governance.log_action(socket.assigns.current_user.id, "save_role", justification: "Rol guardado: #{role.name} con #{length(permissions)} permisos.")
        
        roles = Repo.all(from r in Role, order_by: r.access_level)
        {:noreply, 
          socket
          |> put_flash(:info, "Rol guardado exitosamente.")
          |> assign(roles: roles, show_modal: false, editing_role: nil)}
          
      {:error, changeset} ->
        error_msg =
          changeset.errors
          |> Enum.map(fn {k, {msg, _}} -> "#{k}: #{msg}" end)
          |> Enum.join(", ")
        {:noreply, assign(socket, form_error: "Verifique los datos: #{error_msg}")}
    end
  end
end
