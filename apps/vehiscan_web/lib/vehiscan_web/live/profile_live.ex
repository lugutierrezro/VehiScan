defmodule VehiscanWeb.ProfileLive do
  use VehiscanWeb, :live_view

  alias Vehiscan.Repo
  alias Vehiscan.Accounts.User

  on_mount {VehiscanWeb.UserAuth, :ensure_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    # Allow uploads for the avatar
    socket =
      socket
      |> assign(:current_page, :profile)
      |> allow_upload(:avatar, accept: ~w(.jpg .jpeg .png), max_entries: 1, max_file_size: 5_000_000)

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", _params, socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :avatar, fn %{path: path}, entry ->
        dest = Path.join([:code.priv_dir(:vehiscan_web), "static", "uploads", "#{entry.uuid}-#{entry.client_name}"])
        # Ensure uploads dir exists
        File.mkdir_p!(Path.dirname(dest))
        File.cp!(path, dest)
        {:ok, "/uploads/#{entry.uuid}-#{entry.client_name}"}
      end)

    socket =
      case uploaded_files do
        [avatar_url] ->
          # Update the user in the database
          user = socket.assigns.current_user
          changeset = User.update_changeset(user, %{avatar_url: avatar_url})
          
          case Repo.update(changeset) do
            {:ok, updated_user} ->
              Vehiscan.Governance.log_action(user.id, "update_profile", justification: "El usuario actualizó su foto de perfil.")
              
              socket
              |> assign(:current_user, updated_user)
              |> put_flash(:info, "Foto de perfil actualizada correctamente.")
            {:error, _} ->
              put_flash(socket, :error, "Error al actualizar el perfil.")
          end

        [] ->
          socket
      end

    {:noreply, socket}
  end

  defp error_to_string(:too_large), do: "El archivo es demasiado grande (máximo 5MB)."
  defp error_to_string(:too_many_files), do: "Solo puedes subir un archivo."
  defp error_to_string(:not_accepted), do: "Tipo de archivo no permitido. Sube un JPG o PNG."
end
