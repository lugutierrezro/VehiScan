defmodule Vehiscan.Adapters.OfficialServicesClient do
  @moduledoc """
  Adaptador de integraciones con servicios oficiales (APIs policiales/municipales).
  Implementa el puerto `Vehiscan.Ports.IntegrationPort`.
  Utiliza `Req` como cliente HTTP con reintentos automáticos y timeouts configurables.
  """
  @behaviour Vehiscan.Ports.IntegrationPort

  require Logger

  @default_timeout 10_000
  @max_retries 3

  @impl true
  def query_plate(plate, integration) do
    %{credentials: creds, entity_name: entity} = integration

    Logger.info("Consulting plate #{plate} with #{entity}")

    url = build_url(creds, "/plates/#{plate}")

    case make_request(:get, url, creds) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: 404}} ->
        {:ok, %{found: false, plate: plate}}

      {:ok, %{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        Logger.error("Error consulting #{entity} for plate #{plate}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def sync_watchlist(integration) do
    %{credentials: creds, entity_name: entity} = integration

    Logger.info("Syncing watchlist from #{entity}")

    url = build_url(creds, "/watchlist")

    case make_request(:get, url, creds) do
      {:ok, %{status: 200, body: %{"entries" => entries}}} ->
        {:ok, entries}

      {:ok, %{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        Logger.error("Error syncing watchlist from #{entity}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def health_check(integration) do
    %{credentials: creds, entity_name: entity} = integration

    url = build_url(creds, "/health")

    case make_request(:get, url, creds) do
      {:ok, %{status: status}} when status in 200..299 ->
        {:ok, :connected}

      _ ->
        Logger.warning("Health check failed for #{entity}")
        {:error, :unreachable}
    end
  end

  # --- Private helpers ---

  defp build_url(%{"base_url" => base_url}, path), do: base_url <> path
  defp build_url(_, path), do: "https://localhost#{path}"

  defp make_request(method, url, creds) do
    headers = build_auth_headers(creds)

    Req.request(
      method: method,
      url: url,
      headers: headers,
      receive_timeout: @default_timeout,
      retry: :transient,
      max_retries: @max_retries
    )
  end

  defp build_auth_headers(%{"api_key" => key}),
    do: [{"Authorization", "Bearer #{key}"}]

  defp build_auth_headers(%{"username" => u, "password" => p}) do
    credentials = Base.encode64("#{u}:#{p}")
    [{"Authorization", "Basic #{credentials}"}]
  end

  defp build_auth_headers(_), do: []
end
