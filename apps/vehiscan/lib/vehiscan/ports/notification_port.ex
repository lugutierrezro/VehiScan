defmodule Vehiscan.Ports.NotificationPort do
  @moduledoc """
  Puerto (interfaz) para el sistema de notificaciones.
  Abstrae el mecanismo de envío de alertas (email, SMS, webhook, etc.).
  """

  @doc "Envía una notificación de alerta crítica al operador responsable."
  @callback send_alert_notification(alert :: map(), recipient :: map()) ::
              {:ok, term()} | {:error, term()}

  @doc "Envía un email genérico del sistema."
  @callback send_email(to :: String.t(), subject :: String.t(), body :: String.t()) ::
              {:ok, term()} | {:error, term()}

  @doc "Envía una notificación de reporte generado al usuario."
  @callback send_report_ready(user :: map(), report :: map()) ::
              {:ok, term()} | {:error, term()}
end
