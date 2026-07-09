defmodule VehiscanWeb.AlertsLive do
  use VehiscanWeb, :live_view

  alias Vehiscan.Repo
  alias Vehiscan.Monitoring
  alias Vehiscan.Monitoring.ALPREvent
  import Ecto.Query

  on_mount {VehiscanWeb.UserAuth, :ensure_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Monitoring.subscribe()

    socket =
      socket
      |> assign(
        current_page: :alerts,
        selected_alert: nil,
        validation_error: nil,
        filter_status: "pending",
        filter_severity: "all"
      )
      |> load_alerts()

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter-change", %{"status" => status, "severity" => severity}, socket) do
    socket =
      socket
      |> assign(filter_status: status, filter_severity: severity)
      |> load_alerts()

    {:noreply, socket}
  end

  @impl true
  def handle_event("select-alert", %{"id" => alert_id}, socket) do
    alert = Monitoring.list_alerts() |> Enum.find(&(&1.id == alert_id))
    {:noreply, assign(socket, :selected_alert, alert)}
  end

  @impl true
  def handle_event("close-modal", _params, socket) do
    {:noreply, assign(socket, selected_alert: nil, validation_error: nil)}
  end

  @impl true
  def handle_event("dismiss-threat-alert", _params, socket) do
    {:noreply, assign(socket, :threat_alert, nil)}
  end

  @impl true
  def handle_event("resolve-alert", %{"status" => status, "details" => details}, socket) do
    alert = socket.assigns.selected_alert
    operator_id = socket.assigns.current_user.id
    ip_address = "127.0.0.1"

    if String.length(details) < 10 do
      {:noreply, assign(socket, :validation_error, "La justificación debe tener al menos 10 caracteres")}
    else
      attrs = %{
        operator_id: operator_id,
        validation_details: details,
        status: status
      }

      case Monitoring.resolve_alert(alert.id, attrs, ip_address) do
        {:ok, _resolved} ->
          socket =
            socket
            |> put_flash(:info, "Alerta procesada correctamente")
            |> assign(:selected_alert, nil)
            |> assign(:validation_error, nil)
            |> load_alerts()

          {:noreply, socket}

        {:error, changeset} ->
          error_msg =
            changeset.errors
            |> Enum.map(fn {k, {msg, _}} -> "#{k}: #{msg}" end)
            |> Enum.join(", ")

          {:noreply, assign(socket, :validation_error, error_msg)}
      end
    end
  end

  @impl true
  def handle_info({:new_alpr_event, _event, alerts}, socket) do
    socket =
      if alerts != [] do
        socket
        |> load_alerts()
        |> push_event("play-threat-alarm", %{})
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:alert_resolved, _resolved_alert}, socket) do
    {:noreply, load_alerts(socket)}
  end

  # ─── Privados ─────────────────────────────────────────────────────────────────

  defp load_alerts(socket) do
    status = socket.assigns.filter_status
    severity = socket.assigns.filter_severity

    alerts = Monitoring.list_alerts(status: status, severity: severity)
    assign(socket, :alerts, alerts)
  end
end
