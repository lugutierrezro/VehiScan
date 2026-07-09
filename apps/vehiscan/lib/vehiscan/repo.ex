defmodule Vehiscan.Repo do
  use Ecto.Repo,
    otp_app: :vehiscan,
    adapter: Ecto.Adapters.Postgres
end
