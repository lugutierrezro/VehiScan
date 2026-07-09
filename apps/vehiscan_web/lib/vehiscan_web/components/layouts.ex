defmodule VehiscanWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use VehiscanWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <.theme_toggle />
          </li>
          <li>
            <a href="https://hexdocs.pm/phoenix/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end

  attr :current_page, :atom, required: true
  attr :current_user, :map, required: true

  def navigation_bar(assigns) do
    ~H"""
    <header class="navbar bg-base-100 border-b border-base-content/10 px-6 py-3 flex-none justify-between items-center shadow-lg">
      <div class="flex items-center gap-3">
        <div class="p-2 bg-primary/10 rounded-xl text-primary">
          <.icon name="hero-shield-check-solid" class="w-8 h-8" />
        </div>
        <div>
          <h1 class="text-xl font-extrabold tracking-tight font-heading">Vehiscan</h1>
          <p class="text-xs opacity-60">Centro de Monitoreo Metropolitano</p>
        </div>
      </div>

      <nav class="flex gap-1">
        <.link navigate={~p"/"} class={"btn btn-sm #{if @current_page == :dashboard, do: "btn-primary", else: "btn-ghost"}"}>
          <.icon name="hero-home" class="w-4 h-4 mr-1" />
          Dashboard
        </.link>
        
        <.link navigate={~p"/alerts"} class={"btn btn-sm #{if @current_page == :alerts, do: "btn-primary", else: "btn-ghost"}"}>
          <.icon name="hero-bell-alert" class="w-4 h-4 mr-1" />
          Alertas
        </.link>

        <.link navigate={~p"/search"} class={"btn btn-sm #{if @current_page == :search, do: "btn-primary", else: "btn-ghost"}"}>
          <.icon name="hero-magnifying-glass" class="w-4 h-4 mr-1" />
          Buscador
        </.link>

        <div class="dropdown dropdown-hover">
          <div tabindex="0" role="button" class={"btn btn-sm #{if @current_page == :reports, do: "btn-primary", else: "btn-ghost"}"}>
            <.icon name="hero-document-chart-bar" class="w-4 h-4 mr-1" />
            Reportes
            <.icon name="hero-chevron-down" class="w-3 h-3 ml-1 opacity-50" />
          </div>
          <ul tabindex="0" class="dropdown-content z-[100] menu p-2 shadow-2xl bg-base-100 rounded-box w-52 border border-base-content/10 mt-0">
            <li><.link navigate={~p"/reports"}><.icon name="hero-document-plus" class="w-4 h-4" /> Generar Reporte</.link></li>
            <li><.link navigate={~p"/reports"}><.icon name="hero-archive-box" class="w-4 h-4" /> Historial Descargas</.link></li>
          </ul>
        </div>

        <div class="dropdown dropdown-hover">
          <div tabindex="0" role="button" class={"btn btn-sm #{if @current_page == :olap, do: "btn-primary", else: "btn-ghost"}"}>
            <.icon name="hero-presentation-chart-line" class="w-4 h-4 mr-1" />
            Analítica
            <.icon name="hero-chevron-down" class="w-3 h-3 ml-1 opacity-50" />
          </div>
          <ul tabindex="0" class="dropdown-content z-[100] menu p-2 shadow-2xl bg-base-100 rounded-box w-52 border border-base-content/10 mt-0">
            <li><.link navigate={~p"/olap"}><.icon name="hero-chart-pie" class="w-4 h-4" /> Dashboard Ejecutivo</.link></li>
            <li><.link navigate={~p"/olap"}><.icon name="hero-arrow-trending-up" class="w-4 h-4" /> Tendencias</.link></li>
          </ul>
        </div>

        <div class="dropdown dropdown-hover">
          <div tabindex="0" role="button" class={"btn btn-sm #{if @current_page == :users, do: "btn-primary", else: "btn-ghost"}"}>
            <.icon name="hero-users" class="w-4 h-4 mr-1" />
            Gestión Personal
            <.icon name="hero-chevron-down" class="w-3 h-3 ml-1 opacity-50" />
          </div>
          <ul tabindex="0" class="dropdown-content z-[100] menu p-2 shadow-2xl bg-base-100 rounded-box w-60 border border-base-content/10 mt-0">
            <li><.link navigate={~p"/users"}><.icon name="hero-user-group" class="w-4 h-4" /> Directorio de Usuarios</.link></li>
            <li><.link navigate={~p"/users?action=new"}><.icon name="hero-user-plus" class="w-4 h-4" /> Crear Nuevo Usuario</.link></li>
            <li><.link navigate={~p"/roles"}><.icon name="hero-shield-check" class="w-4 h-4" /> Roles y Permisos</.link></li>
            <li><.link navigate={~p"/audit"}><.icon name="hero-clipboard-document-list" class="w-4 h-4" /> Historial de Auditoría</.link></li>
          </ul>
        </div>

        <div class="dropdown dropdown-hover">
          <div tabindex="0" role="button" class={"btn btn-sm #{if @current_page == :cameras, do: "btn-primary", else: "btn-ghost"}"}>
            <.icon name="hero-video-camera" class="w-4 h-4 mr-1" />
            Cámaras
            <.icon name="hero-chevron-down" class="w-3 h-3 ml-1 opacity-50" />
          </div>
          <ul tabindex="0" class="dropdown-content z-[100] menu p-2 shadow-2xl bg-base-100 rounded-box w-52 border border-base-content/10 mt-0">
            <li><.link navigate={~p"/cameras"}><.icon name="hero-map" class="w-4 h-4" /> Mapa de Monitoreo</.link></li>
            <li><.link navigate={~p"/cameras"}><.icon name="hero-cog" class="w-4 h-4" /> Mantenimiento</.link></li>
          </ul>
        </div>

        <.link navigate={~p"/config"} class={"btn btn-sm #{if @current_page == :config, do: "btn-primary", else: "btn-ghost"}"}>
          <.icon name="hero-cog-6-tooth" class="w-4 h-4 mr-1" />
          Configuración
        </.link>
      </nav>

      <div class="flex items-center gap-4">
        <div class="text-right hidden sm:block">
          <p class="text-sm font-semibold">{@current_user.name}</p>
          <span class="badge badge-secondary badge-xs py-1.5 uppercase font-bold text-[10px] tracking-wider">{@current_user.role.name}</span>
        </div>

        <div class="dropdown dropdown-end">
          <div tabindex="0" role="button" class="btn btn-ghost btn-circle avatar placeholder">
            <%= if @current_user.avatar_url do %>
              <div class="w-10 rounded-full">
                <img src={@current_user.avatar_url} />
              </div>
            <% else %>
              <div class="bg-neutral text-neutral-content rounded-full w-10">
                <span class="text-xs font-bold uppercase"><%= String.slice(@current_user.name, 0, 2) %></span>
              </div>
            <% end %>
          </div>
          <ul tabindex="0" class="menu menu-sm dropdown-content mt-3 z-50 p-2 shadow-2xl bg-base-200 border border-base-content/10 rounded-box w-52">
            <li><span class="text-xs opacity-60 font-semibold uppercase px-3 py-1">Opciones</span></li>
            <li>
              <.link navigate={~p"/profile"} class="font-medium">
                <.icon name="hero-user" class="w-4 h-4 mr-1" />
                Mi Perfil
              </.link>
            </li>
            <li>
              <.link href={~p"/logout"} method="delete" class="text-error font-medium">
                <.icon name="hero-arrow-right-end-on-rectangle" class="w-4 h-4 mr-1" />
                Cerrar Sesión
              </.link>
            </li>
          </ul>
        </div>
      </div>
    </header>
    """
  end
end
