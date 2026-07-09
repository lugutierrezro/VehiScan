defmodule Vehiscan.Adapters.SwooshMailer do
  @moduledoc """
  Adaptador de notificaciones usando Swoosh.
  Implementa el puerto `Vehiscan.Ports.NotificationPort`.
  """
  @behaviour Vehiscan.Ports.NotificationPort

  import Swoosh.Email

  @impl true
  def send_alert_notification(alert, recipient) do
    %{email: to_email, name: to_name} = recipient

    email =
      new()
      |> to({to_name, to_email})
      |> from({"Vehiscan Sistema", "no-reply@vehiscan.local"})
      |> subject("[ALERTA #{String.upcase(alert.severity)}] Nueva coincidencia en lista de interés")
      |> html_body(build_alert_html(alert))
      |> text_body(build_alert_text(alert))

    Vehiscan.Mailer.deliver(email)
  end

  @impl true
  def send_email(to, subject, body) do
    email =
      new()
      |> to(to)
      |> from({"Vehiscan Sistema", "no-reply@vehiscan.local"})
      |> subject(subject)
      |> text_body(body)

    Vehiscan.Mailer.deliver(email)
  end

  @impl true
  def send_report_ready(user, report) do
    email =
      new()
      |> to({user.name, user.email})
      |> from({"Vehiscan Reportes", "no-reply@vehiscan.local"})
      |> subject("Reporte #{String.upcase(report.type)} listo para descarga")
      |> html_body(build_report_html(user, report))

    Vehiscan.Mailer.deliver(email)
  end

  # --- HTML builders ---

  defp build_alert_html(alert) do
    """
    <html>
    <body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
      <div style="background: #1a1a2e; padding: 20px; border-radius: 8px;">
        <h1 style="color: #e94560; margin: 0;">⚠️ ALERTA #{String.upcase(alert.severity)}</h1>
      </div>
      <div style="padding: 20px; border: 1px solid #ddd; border-radius: 8px; margin-top: 10px;">
        <p>Se detectó una coincidencia en la lista de interés que requiere validación inmediata.</p>
        <table style="width: 100%; border-collapse: collapse;">
          <tr><td style="padding: 8px; font-weight: bold;">Severidad:</td>
              <td style="padding: 8px; color: #{severity_color(alert.severity)};">#{String.upcase(alert.severity)}</td></tr>
          <tr><td style="padding: 8px; font-weight: bold;">Estado:</td>
              <td style="padding: 8px;">#{alert.status}</td></tr>
        </table>
        <p style="margin-top: 20px; color: #666; font-size: 12px;">
          Este sistema requiere validación humana. No se ejecutarán acciones automáticas.
        </p>
      </div>
    </body>
    </html>
    """
  end

  defp build_alert_text(alert) do
    """
    ALERTA #{String.upcase(alert.severity)} - Sistema Vehiscan

    Se detectó una coincidencia en la lista de interés.
    Severidad: #{alert.severity}
    Estado: #{alert.status}

    Ingrese al sistema para validar esta alerta. Se requiere acción humana.
    """
  end

  defp build_report_html(user, report) do
    """
    <html>
    <body style="font-family: Arial, sans-serif;">
      <h2>Reporte listo - #{String.upcase(report.type)}</h2>
      <p>Hola #{user.name},</p>
      <p>Tu reporte ha sido generado exitosamente y está disponible para descarga.</p>
      <p>Hash SHA-256 para verificación de integridad: <code>#{report.file_hash}</code></p>
    </body>
    </html>
    """
  end

  defp severity_color("high"), do: "#e94560"
  defp severity_color("medium"), do: "#f5a623"
  defp severity_color(_), do: "#4caf50"
end
