defmodule GenieWeb.PageController do
  use GenieWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
