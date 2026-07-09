alias Vehiscan.Repo
alias Vehiscan.Infrastructure.Camera

Repo.delete_all(Camera)
IO.puts("Todas las camaras antiguas han sido eliminadas.")
