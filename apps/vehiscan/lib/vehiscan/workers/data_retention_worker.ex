defmodule Vehiscan.Workers.DataRetentionWorker do
  @moduledoc """
  Worker de Oban para la política de retención de datos.

  Se ejecuta cada medianoche y elimina de forma segura:
  - Eventos ALPR con más de N días (por defecto 90, configurable)
  - Imágenes asociadas a eventos expirados
  - Vehículos observados sin actividad reciente y sin interés activo

  Los registros de AuditLog NUNCA se eliminan (inmutables por política).
  Los registros de Alert con status validated/dismissed se archivan, no se borran.
  """
  use Oban.Worker,
    queue: :governance,
    max_attempts: 3,
    unique: [period: 86_400]

  import Ecto.Query
  require Logger

  alias Vehiscan.Repo
  alias Vehiscan.Monitoring.{ALPREvent, ObservedVehicle}
  alias Vehiscan.Config.Configuration

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    retention_days = get_retention_days()
    cutoff = DateTime.add(DateTime.utc_now(), -retention_days * 86_400, :second)

    Logger.info("DataRetentionWorker: Starting cleanup. Cutoff date: #{DateTime.to_iso8601(cutoff)}")

    with {:ok, alpr_count} <- delete_expired_alpr_events(cutoff),
         {:ok, vehicle_count} <- cleanup_stale_observed_vehicles(cutoff) do
      Logger.info(
        "DataRetentionWorker: Cleanup complete. " <>
          "ALPR events deleted: #{alpr_count}. " <>
          "Stale vehicles cleaned: #{vehicle_count}."
      )

      :ok
    else
      {:error, reason} ->
        Logger.error("DataRetentionWorker: Cleanup failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ─── Lógica de limpieza ───────────────────────────────────────────────────────

  defp delete_expired_alpr_events(cutoff) do
    # Solo elimina eventos que NO tienen alertas asociadas pendientes o validadas
    # Los eventos con alertas validadas se preservan por cadena de custodia
    active_alerts_query =
      from(a in Vehiscan.Monitoring.Alert,
        where: a.status in ["pending", "validated"],
        select: a.alpr_event_id
      )

    {count, _} =
      from(e in ALPREvent,
        where: e.inserted_at < ^cutoff,
        where: e.id not in subquery(active_alerts_query)
      )
      |> Repo.delete_all()

    Logger.info("DataRetentionWorker: Deleted #{count} expired ALPR events.")
    {:ok, count}
  rescue
    error ->
      Logger.error("DataRetentionWorker: Error deleting ALPR events: #{inspect(error)}")
      {:error, error}
  end

  defp cleanup_stale_observed_vehicles(cutoff) do
    # Solo limpia vehículos sin interés activo y sin actividad reciente
    {count, _} =
      from(v in ObservedVehicle,
        where: v.last_seen_at < ^cutoff,
        where: v.interest_status == false
      )
      |> Repo.delete_all()

    Logger.info("DataRetentionWorker: Cleaned #{count} stale observed vehicles.")
    {:ok, count}
  rescue
    error ->
      Logger.error("DataRetentionWorker: Error cleaning observed vehicles: #{inspect(error)}")
      {:error, error}
  end

  # ─── Configuración dinámica ───────────────────────────────────────────────────

  defp get_retention_days do
    case Repo.get(Configuration, "data_retention_days") do
      %Configuration{value: value} ->
        String.to_integer(value)

      nil ->
        # Default: 90 days as per governance policy
        90
    end
  end

  @doc """
  Encola el worker para ejecución inmediata (útil para testing y administración).
  """
  def enqueue_now! do
    %{}
    |> __MODULE__.new()
    |> Oban.insert!()
  end

  @doc """
  Devuelve el cron schedule para medianoche diaria.
  Registrar en config/config.exs bajo :oban, crontab.
  """
  def cron_schedule, do: "0 0 * * *"
end
