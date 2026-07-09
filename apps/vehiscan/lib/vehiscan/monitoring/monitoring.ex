defmodule Vehiscan.Monitoring do
  @moduledoc """
  Contexto de Monitoreo de Vehiscan.

  Gestiona el ciclo de vida de los eventos ALPR, alertas, vehículos observados y watchlist.
  Es el núcleo del dominio: recibe capturas, cruza con watchlist y genera alertas
  que siempre requieren validación humana.
  """

  import Ecto.Query
  alias Vehiscan.Repo
  alias Vehiscan.Monitoring.{ALPREvent, Alert, ObservedVehicle, Watchlist}
  alias Vehiscan.Governance

  # ─── Eventos ALPR ────────────────────────────────────────────────────────────

  @doc """
  Registra un nuevo evento ALPR. Automáticamente:
  1. Normaliza la placa (uppercase, sin caracteres especiales)
  2. Actualiza el perfil del vehículo observado (frecuencia)
  3. Cruza con la watchlist y genera alertas si hay coincidencias
  Devuelve `{:ok, event}` con las alertas generadas en los metadatos.
  """
  def register_alpr_event(attrs) do
    Repo.transaction(fn ->
      with {:ok, event} <- create_alpr_event(attrs),
           :ok <- update_observed_vehicle(event),
           {:ok, alerts} <- check_watchlist_and_alert(event) do
        %{event: event, alerts: alerts}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> broadcast()
  end

  @doc "Crea un evento ALPR (sin transacción, para uso interno)."
  def create_alpr_event(attrs) do
    %ALPREvent{}
    |> ALPREvent.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Lista los eventos ALPR más recientes con filtros opcionales."
  def list_alpr_events(filters \\ []) do
    ALPREvent
    |> filter_events_by_plate(Keyword.get(filters, :plate))
    |> filter_events_by_camera(Keyword.get(filters, :camera_id))
    |> filter_events_by_date(Keyword.get(filters, :from), Keyword.get(filters, :to))
    |> filter_events_by_status(Keyword.get(filters, :status))
    |> order_by([e], desc: e.inserted_at)
    |> limit(^Keyword.get(filters, :limit, 100))
    |> preload(:camera)
    |> Repo.all()
  end

  @doc "Busca eventos ALPR por placa usando el índice GIN trigrama (búsqueda fuzzy)."
  def search_events_by_plate(plate_pattern, user_id, justification, ip_address) do
    normalized = plate_pattern |> String.upcase() |> String.replace(~r/[^A-Z0-9%]/, "")

    # Auditoría obligatoria antes de ejecutar la búsqueda
    case Governance.log_plate_query(%{
           plate_queried: normalized,
           justification: justification,
           user_id: user_id,
           ip_address: ip_address
         }) do
      {:ok, _log} ->
        results =
          from(e in ALPREvent,
            where: like(e.normalized_plate, ^normalized),
            order_by: [desc: e.inserted_at],
            limit: 1000,
            preload: [:camera]
          )
          |> Repo.all()

        # Actualiza el log con el conteo de resultados
        {:ok, results}

      {:error, changeset} ->
        {:error, {:audit_required, changeset}}
    end
  end

  # ─── Alertas ─────────────────────────────────────────────────────────────────

  @doc "Lista alertas pendientes de validación, ordenadas por severidad."
  def list_pending_alerts do
    from(a in Alert,
      where: a.status == "pending",
      order_by: [
        asc:
          fragment(
            "CASE ? WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END",
            a.severity
          ),
        desc: a.inserted_at
      ],
      preload: [[alpr_event: :camera], :watchlist]
    )
    |> Repo.all()
  end

  @doc "Lista alertas con filtros por status y severidad."
  def list_alerts(filters \\ []) do
    query = from(a in Alert, order_by: [desc: a.inserted_at])

    query =
      case Keyword.get(filters, :status, "all") do
        "all" -> query
        status -> from(a in query, where: a.status == ^status)
      end

    query =
      case Keyword.get(filters, :severity, "all") do
        "all" -> query
        severity -> from(a in query, where: a.severity == ^severity)
      end

    query
    |> preload([[alpr_event: :camera], :watchlist, :operator])
    |> Repo.all()
  end

  @doc """
  Valida o descarta una alerta. Requiere:
  - `operator_id`: usuario autenticado que realiza la acción
  - `validation_details`: justificación mínimo 10 caracteres
  - `status`: "validated" | "dismissed"
  """
  def resolve_alert(alert_id, attrs, ip_address) do
    alert = Repo.get!(Alert, alert_id)

    with {:ok, resolved} <-
           alert
           |> Alert.validate_changeset(attrs)
           |> Repo.update(),
         {:ok, _log} <-
           Governance.log_alert_action(
             resolved.operator_id,
             alert_id,
             resolved.status,
             ip_address
           ) do
      {:ok, resolved}
    end
    |> broadcast()
  end

  # ─── Watchlist ────────────────────────────────────────────────────────────────

  @doc "Lista entradas activas de la watchlist, ordenadas por severidad."
  def list_active_watchlist do
    from(w in Watchlist,
      where: w.status == "active",
      order_by: [
        asc:
          fragment(
            "CASE ? WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END",
            w.severity
          )
      ]
    )
    |> Repo.all()
  end

  @doc "Agrega una placa a la watchlist."
  def add_to_watchlist(attrs) do
    %Watchlist{}
    |> Watchlist.changeset(attrs)
    |> Repo.insert()
  end

  # ─── Vehículos Observados ─────────────────────────────────────────────────────

  @doc "Obtiene o crea el perfil de un vehículo observado."
  def get_or_create_observed_vehicle(plate) do
    normalized = String.upcase(plate)

    case Repo.get(ObservedVehicle, normalized) do
      nil ->
        %ObservedVehicle{}
        |> ObservedVehicle.changeset(%{plate: normalized, frequency: 1, last_seen_at: DateTime.utc_now()})
        |> Repo.insert()

      vehicle ->
        vehicle
        |> ObservedVehicle.increment_detection_changeset()
        |> Repo.update()
    end
  end

  # ─── Privados ─────────────────────────────────────────────────────────────────

  defp update_observed_vehicle(%ALPREvent{normalized_plate: plate, plate_image_url: plate_image_url}) do
    case get_or_create_observed_vehicle(plate) do
      {:ok, vehicle} ->
        if plate_image_url && String.starts_with?(plate_image_url, "attributes|") do
          parts = String.split(plate_image_url, "|")

          color =
            Enum.find_value(parts, fn p ->
              if String.starts_with?(p, "color:"), do: String.replace(p, "color:", "")
            end)

          class =
            Enum.find_value(parts, fn p ->
              if String.starts_with?(p, "class:"), do: String.replace(p, "class:", "")
            end)

          attrs = %{
            "class" => class || "unknown",
            "color" => color || "unknown"
          }

          vehicle
          |> ObservedVehicle.changeset(%{detected_attributes: attrs})
          |> Repo.update()

          :ok
        else
          :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_watchlist_and_alert(%ALPREvent{normalized_plate: plate} = event) do
    matching_entries =
      from(w in Watchlist,
        where: w.plate == ^plate and w.status == "active"
      )
      |> Repo.all()

    alerts =
      Enum.map(matching_entries, fn watchlist_entry ->
        {:ok, alert} =
          %Alert{}
          |> Alert.changeset(%{
            alpr_event_id: event.id,
            watchlist_id: watchlist_entry.id,
            severity: watchlist_entry.severity,
            status: "pending"
          })
          |> Repo.insert()

        alert
      end)

    {:ok, alerts}
  end

  defp filter_events_by_plate(query, nil), do: query
  defp filter_events_by_plate(query, plate), do: where(query, [e], e.normalized_plate == ^plate)

  defp filter_events_by_camera(query, nil), do: query
  defp filter_events_by_camera(query, cam_id), do: where(query, [e], e.camera_id == ^cam_id)

  defp filter_events_by_date(query, nil, nil), do: query
  defp filter_events_by_date(query, from, nil), do: where(query, [e], e.inserted_at >= ^from)
  defp filter_events_by_date(query, nil, to), do: where(query, [e], e.inserted_at <= ^to)

  defp filter_events_by_date(query, from, to),
    do: where(query, [e], e.inserted_at >= ^from and e.inserted_at <= ^to)

  defp filter_events_by_status(query, nil), do: query
  defp filter_events_by_status(query, status), do: where(query, [e], e.status == ^status)

  # ─── PubSub Real-time ──────────────────────────────────────────────────────────

  @doc "Suscribe el proceso actual a las alertas y eventos del sistema."
  def subscribe do
    Phoenix.PubSub.subscribe(Vehiscan.PubSub, "monitoring:events")
  end

  defp broadcast({:ok, %{event: event, alerts: alerts}} = result) do
    event_preloaded = Repo.preload(event, :camera)
    # Broadcast individual alerts too, so dashboard client can see them
    alerts_preloaded = Enum.map(alerts, &Repo.preload(&1, [[alpr_event: :camera], :watchlist]))

    Phoenix.PubSub.broadcast(
      Vehiscan.PubSub,
      "monitoring:events",
      {:new_alpr_event, event_preloaded, alerts_preloaded}
    )
    result
  end

  defp broadcast({:ok, resolved} = result) do
    resolved_preloaded = Repo.preload(resolved, [:alpr_event, :watchlist])
    Phoenix.PubSub.broadcast(
      Vehiscan.PubSub,
      "monitoring:events",
      {:alert_resolved, resolved_preloaded}
    )
    result
  end

  defp broadcast(other), do: other
end
