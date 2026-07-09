defmodule VehiscanWeb.Router do
  use VehiscanWeb, :router

  import VehiscanWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {VehiscanWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Scope de autenticación (sólo para usuarios no autenticados)
  scope "/", VehiscanWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/login", SessionController, :new
    post "/login", SessionController, :create
  end

  # Scope protegido (requiere autenticación)
  scope "/", VehiscanWeb do
    pipe_through [:browser, :require_authenticated_user]

    delete "/logout", SessionController, :delete
    live "/", DashboardLive, :index
    live "/alerts", AlertsLive, :index
    live "/search", SearchLive, :index
    live "/cameras", CamerasLive, :index
    live "/config", ConfigLive, :index
    live "/reports", ReportsLive, :index
    live "/olap", OlapDashboardLive, :index
    live "/users", UsersLive, :index
    live "/audit", AuditLive, :index
    live "/roles", RolesLive, :index
    live "/profile", ProfileLive, :index
    get "/reports/download/:id", ReportController, :download
    get "/stream/:id", StreamController, :stream
    get "/crops/:filename", CropController, :show
  end

  # API interna: recibe detecciones de placas del proceso Python en vivo
  scope "/api", VehiscanWeb do
    pipe_through :api
    post "/plate_event", PlateEventController, :create
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:vehiscan_web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: VehiscanWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
