alias Vehiscan.Repo
alias Vehiscan.Monitoring.ALPREvent

IO.puts "Actualizando colores y clases aleatorios..."
colors = ["blue", "red", "black", "white", "silver", "gray", "green", "yellow", "brown"]
classes = ["car", "suv", "truck", "van", "motorcycle", "bus"]

events = Repo.all(ALPREvent)
Enum.each(events, fn event -> 
  attr = "attributes|class:#{Enum.random(classes)}|color:#{Enum.random(colors)}"
  Repo.update!(Ecto.Changeset.change(event, plate_image_url: attr))
end)
IO.puts "Colores actualizados correctamente!"
