defmodule Vehiscan.Governance do
  @moduledoc """
  Contexto de Gobernanza y Auditoría de Vehiscan.

  Implementa el sistema de auditoría inmutable que registra toda acción sensible:
  - Búsquedas de placas (con justificación obligatoria)
  - Validación/descarte de alertas
  - Generación y descarga de reportes
  - Cambios de configuración

  Los registros de auditoría NO pueden eliminarse (protegidos por política).
  La retención de OTROS datos se gestiona mediante el worker de Oban.
  """

  import Ecto.Query
  alias Vehiscan.Repo
  alias Vehiscan.Governance.AuditLog

  # ─── Escritura de Logs de Auditoría ──────────────────────────────────────────

  @doc """
  Registra una búsqueda de placa. Requiere justificación obligatoria (mínimo 10 caracteres).
  Devuelve `{:error, changeset}` si la justificación está ausente o es muy corta.
  """
  def log_plate_query(attrs) do
    %AuditLog{}
    |> AuditLog.plate_query_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Registra una acción genérica del sistema (login, logout, cambio de configuración, etc.).
  """
  def log_action(user_id, action, opts \\ []) do
    attrs = %{
      user_id: user_id,
      action: action,
      ip_address: Keyword.get(opts, :ip_address),
      filters_applied: Keyword.get(opts, :filters, %{}),
      result_count: Keyword.get(opts, :result_count),
      justification: Keyword.get(opts, :justification)
    }

    %AuditLog{}
    |> AuditLog.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Registra la validación o descarte de una alerta por un operador.
  """
  def log_alert_action(user_id, alert_id, action, ip_address) do
    log_action(user_id, "alert_#{action}", ip_address: ip_address, filters: %{alert_id: alert_id})
  end

  @doc """
  Registra la descarga de un reporte.
  """
  def log_report_download(user_id, report_id, ip_address) do
    log_action(user_id, "report_download",
      ip_address: ip_address,
      filters: %{report_id: report_id}
    )
  end

  # ─── Consultas de Auditoría ───────────────────────────────────────────────────

  @doc """
  Lista todos los logs de auditoría con filtros opcionales.
  Solo accesible por rol Auditor o Administrador.
  """
  def list_audit_logs(filters \\ []) do
    AuditLog
    |> filter_by_user(Keyword.get(filters, :user_id))
    |> filter_by_action(Keyword.get(filters, :action))
    |> filter_by_plate(Keyword.get(filters, :plate))
    |> filter_by_date_range(
      Keyword.get(filters, :from_date),
      Keyword.get(filters, :to_date)
    )
    |> order_by([l], desc: l.inserted_at)
    |> limit(^Keyword.get(filters, :limit, 500))
    |> Repo.all()
  end

  @doc "Cuenta el total de consultas de placa realizadas por un usuario."
  def count_plate_queries_by_user(user_id) do
    AuditLog
    |> where([l], l.user_id == ^user_id and l.action == "plate_query")
    |> Repo.aggregate(:count, :id)
  end

  @doc "Lista las últimas N consultas de un usuario específico."
  def recent_queries(user_id, limit \\ 10) do
    AuditLog
    |> where([l], l.user_id == ^user_id)
    |> order_by([l], desc: l.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  # ─── Filtros privados ─────────────────────────────────────────────────────────

  defp filter_by_user(query, nil), do: query
  defp filter_by_user(query, user_id), do: where(query, [l], l.user_id == ^user_id)

  defp filter_by_action(query, nil), do: query
  defp filter_by_action(query, action), do: where(query, [l], l.action == ^action)

  defp filter_by_plate(query, nil), do: query
  defp filter_by_plate(query, plate), do: where(query, [l], l.plate_queried == ^plate)

  defp filter_by_date_range(query, nil, nil), do: query

  defp filter_by_date_range(query, from_date, nil),
    do: where(query, [l], l.inserted_at >= ^from_date)

  defp filter_by_date_range(query, nil, to_date),
    do: where(query, [l], l.inserted_at <= ^to_date)

  defp filter_by_date_range(query, from_date, to_date),
    do: where(query, [l], l.inserted_at >= ^from_date and l.inserted_at <= ^to_date)
end
