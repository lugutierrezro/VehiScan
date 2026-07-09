# check_events.exs
alias Vehiscan.Repo
alias Vehiscan.Monitoring.ALPREvent

events = Repo.all(ALPREvent)
Enum.each(events, fn e ->
  IO.puts("Plate: #{e.normalized_plate} | Image URL: #{e.plate_image_url} | Crop URL: #{inspect(ALPREvent.get_crop_url(e))}")
end)
