defmodule ReceptionistWeb.PageController do
  use ReceptionistWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
