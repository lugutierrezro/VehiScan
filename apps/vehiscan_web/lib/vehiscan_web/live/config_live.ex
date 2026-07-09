defmodule VehiscanWeb.ConfigLive do
  use VehiscanWeb, :live_view

  import Ecto.Query
  alias Vehiscan.Repo
  alias Vehiscan.Infrastructure.Camera
  alias Vehiscan.Monitoring.ALPREvent
  alias Vehiscan.Config.Configuration
  alias Vehiscan.Governance

  on_mount {VehiscanWeb.UserAuth, :ensure_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    python_path = get_python_path()
    cameras = Repo.all(Camera)
    new_camera_changeset = Camera.changeset(%Camera{}, %{})

    socket =
      socket
      |> assign(:page_title, "Configuración del Sistema")
      |> assign(:python_path, python_path)
      |> assign(:cameras, cameras)
      |> assign(:camera_changeset, new_camera_changeset)
      |> assign(:selected_camera, nil)
      |> assign(:error_message, nil)
      |> assign(:detected_webcams, [])

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  # --- Eventos de Configuración de Ruta Python ---

  @impl true
  def handle_event("save-python-path", %{"path" => path}, socket) do
    user_id = socket.assigns.current_user.id
    ip_address = "127.0.0.1"

    config_attrs = %{
      parameter_key: "python_project_path",
      value: path,
      module: "integrations",
      updated_by_id: user_id
    }

    # Insertar o actualizar la configuración
    result =
      case Repo.get(Configuration, "python_project_path") do
        nil ->
          %Configuration{}
          |> Configuration.changeset(config_attrs)
          |> Repo.insert()

        config ->
          config
          |> Configuration.changeset(config_attrs)
          |> Repo.update()
      end

    case result do
      {:ok, _config} ->
        # Log Governance Audit Action
        Governance.log_action(user_id, "update_python_path",
          ip_address: ip_address,
          justification: "Actualización de ruta del proyecto de visión por computadora a: #{path}"
        )

        {:noreply,
         socket
         |> put_flash(:info, "Ruta de proyecto de Python actualizada correctamente.")
         |> assign(:python_path, path)}

      {:error, changeset} ->
        error_msg =
          changeset.errors
          |> Enum.map(fn {k, {msg, _}} -> "#{k}: #{msg}" end)
          |> Enum.join(", ")

        {:noreply, put_flash(socket, :error, "Error al guardar configuración: #{error_msg}")}
    end
  end

  # --- Eventos de Gestión de Cámaras ---

  @impl true
  def handle_event("select-camera", %{"id" => camera_id}, socket) do
    camera = Repo.get!(Camera, camera_id)
    changeset = Camera.changeset(camera, %{})

    {:noreply,
     socket
     |> assign(:selected_camera, camera)
     |> assign(:camera_changeset, changeset)}
  end

  @impl true
  def handle_event("validate-camera", %{"camera" => camera_params}, socket) do
    changeset =
      if camera = socket.assigns.selected_camera do
        Camera.changeset(camera, camera_params)
      else
        Camera.changeset(%Camera{}, camera_params)
      end
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :camera_changeset, changeset)}
  end

  @impl true
  def handle_event("reset-form", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_camera, nil)
     |> assign(:camera_changeset, Camera.changeset(%Camera{}, %{}))}
  end

  @impl true
  def handle_event("save-camera", %{"camera" => camera_params}, socket) do
    user_id = socket.assigns.current_user.id
    ip_address = "127.0.0.1"

    result =
      if camera = socket.assigns.selected_camera do
        # Editar
        camera
        |> Camera.changeset(camera_params)
        |> Repo.update()
      else
        # Crear
        %Camera{}
        |> Camera.changeset(camera_params)
        |> Repo.insert()
      end

    case result do
      {:ok, saved_camera} ->
        action_name = if socket.assigns.selected_camera, do: "edit_camera", else: "create_camera"
        
        # Registrar auditoría de gobernanza
        Governance.log_action(user_id, action_name,
          ip_address: ip_address,
          justification: "Dispositivo #{saved_camera.code} registrado/modificado con origen de video: #{saved_camera.stream_url}"
        )

        socket =
          socket
          |> put_flash(:info, "Cámara #{saved_camera.code} guardada correctamente.")
          |> assign(:cameras, Repo.all(Camera))
          |> assign(:selected_camera, nil)
          |> assign(:camera_changeset, Camera.changeset(%Camera{}, %{}))

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :camera_changeset, changeset)}
    end
  end

  @impl true
  def handle_event("delete-camera", %{"id" => camera_id}, socket) do
    camera = Repo.get!(Camera, camera_id)
    user_id = socket.assigns.current_user.id
    ip_address = "127.0.0.1"

    # Verificar si tiene eventos ALPR asociados
    has_events? = Repo.exists?(from(e in ALPREvent, where: e.camera_id == ^camera.id))

    if has_events? do
      {:noreply, put_flash(socket, :error, "No se puede eliminar la cámara #{camera.code} porque contiene lecturas asociadas en el feed.")}
    else
      case Repo.delete(camera) do
        {:ok, deleted} ->
          Governance.log_action(user_id, "delete_camera",
            ip_address: ip_address,
            justification: "Eliminación de la cámara #{deleted.code}"
          )

          {:noreply,
           socket
           |> put_flash(:info, "Cámara eliminada correctamente.")
           |> assign(:cameras, Repo.all(Camera))
           |> assign(:selected_camera, nil)
           |> assign(:camera_changeset, Camera.changeset(%Camera{}, %{}))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Error al eliminar dispositivo.")}
      end
    end
  end

  @impl true
  def handle_event("webcams-detected", %{"devices" => devices}, socket) do
    # If stream_url is not set yet in the changeset, we can set a default
    changeset = socket.assigns.camera_changeset
    current_url = Ecto.Changeset.get_field(changeset, :stream_url)
    
    socket =
      if is_nil(current_url) or current_url == "" do
        case devices do
          [%{"index" => idx} | _] ->
            # Set default webcam to index 0 (or first detected)
            updated_changeset = Ecto.Changeset.put_change(changeset, :stream_url, idx)
            assign(socket, :camera_changeset, updated_changeset)
          _ ->
            socket
        end
      else
        socket
      end

    {:noreply, assign(socket, :detected_webcams, devices)}
  end

  # --- Privados ---

  defp get_python_path do
    Configuration.get_resolved_path()
  end
end
