defmodule VehiscanWeb.AuditLive do
  use VehiscanWeb, :live_view

  alias Vehiscan.Repo
  alias Vehiscan.Governance.AuditLog
  alias Vehiscan.Accounts.User
  import Ecto.Query

  on_mount {VehiscanWeb.UserAuth, :ensure_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    # Only Auditors or Admins should ideally see this, but for now we enforce it via layout.
    # We fetch a larger amount of logs or paginated
    audit_logs = fetch_logs()
    users = Repo.all(from u in User, select: {u.name, u.id})

    socket =
      socket
      |> assign(
        current_page: :audit,
        audit_logs: audit_logs,
        users: [{"Todos los Usuarios", ""}] ++ users,
        filter_user: "",
        filter_action: ""
      )

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_event("filter", %{"user" => user_id, "action" => action}, socket) do
    audit_logs = fetch_logs(user_id, action)

    {:noreply,
     socket
     |> assign(filter_user: user_id, filter_action: action, audit_logs: audit_logs)}
  end
  
  @impl true
  def handle_event("clear-filters", _, socket) do
    {:noreply,
     socket
     |> assign(filter_user: "", filter_action: "", audit_logs: fetch_logs())}
  end

  defp fetch_logs(user_id \\ "", action \\ "") do
    query = from a in AuditLog,
            join: u in assoc(a, :user),
            preload: [user: u],
            order_by: [desc: a.inserted_at],
            limit: 200

    query = if user_id != "", do: where(query, [a], a.user_id == ^user_id), else: query
    query = if action != "", do: where(query, [a], a.action == ^action), else: query

    Repo.all(query)
  end
end
