defmodule Vehiscan.Ports.IntegrationPort do
  @moduledoc """
  Puerto (interfaz) para integraciones con entidades oficiales externas.
  Abstrae la comunicación con APIs policiales, municipales y gubernamentales.
  """

  @doc "Consulta una placa en el sistema externo de la entidad."
  @callback query_plate(plate :: String.t(), integration :: map()) ::
              {:ok, map()} | {:error, term()}

  @doc "Sincroniza la lista de interés desde la fuente oficial."
  @callback sync_watchlist(integration :: map()) ::
              {:ok, [map()]} | {:error, term()}

  @doc "Verifica el estado de conectividad con el sistema externo."
  @callback health_check(integration :: map()) ::
              {:ok, :connected} | {:error, :unreachable}
end
