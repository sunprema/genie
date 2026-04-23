defmodule GenieWeb.WebhookController do
  use GenieWeb, :controller

  def create(conn, %{"lamp_id" => _lamp_id}) do
    send_resp(conn, 200, "")
  end
end
