defmodule GenieWeb.PageController do
  use GenieWeb, :controller

  plug :put_root_layout, html: {GenieWeb.Layouts, :landing}
  plug :put_layout, false

  def home(conn, _params) do
    render(conn, :home)
  end
end
