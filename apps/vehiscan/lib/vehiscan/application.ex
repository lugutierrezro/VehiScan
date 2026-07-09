defmodule Vehiscan.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Vehiscan.Repo,
      {DNSCluster, query: Application.get_env(:vehiscan, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Vehiscan.PubSub},
      # Oban background job processor (data retention, notifications, reports)
      {Oban, Application.fetch_env!(:vehiscan, Oban)}
    ]

    result = Supervisor.start_link(children, strategy: :one_for_one, name: Vehiscan.Supervisor)

    # Seed default roles on first startup
    seed_roles()

    result
  end

  defp seed_roles do
    try do
      Vehiscan.Accounts.seed_default_roles()
    rescue
      _ -> :ok
    end
  end
end

