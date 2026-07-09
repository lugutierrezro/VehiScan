defmodule VehiscanWeb.PageController do
  use VehiscanWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
