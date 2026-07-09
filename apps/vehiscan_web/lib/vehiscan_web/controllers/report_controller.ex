defmodule VehiscanWeb.ReportController do
  use VehiscanWeb, :controller

  alias Vehiscan.Repo
  alias Vehiscan.Reporting.Report

  @doc "Sirve el archivo CSV del reporte generado, validando la existencia en disco."
  def download(conn, %{"id" => id}) do
    case Repo.get(Report, id) do
      nil ->
        conn
        |> put_status(404)
        |> text("Reporte no encontrado")

      report ->
        priv_dir =
          case :code.priv_dir(:vehiscan_web) do
            {:error, _} -> Path.expand("../priv", __DIR__)
            path -> path
          end

        file_path = Path.join([priv_dir, "static", "uploads", "reports", "#{report.id}.csv"])

        if File.exists?(file_path) do
          conn
          |> put_resp_content_type("text/csv")
          |> put_resp_header("content-disposition", "attachment; filename=\"vehiscan_report_#{report.id}.csv\"")
          |> send_file(200, file_path)
        else
          conn
          |> put_status(404)
          |> text("El archivo del reporte no existe en el disco")
        end
    end
  end
end
