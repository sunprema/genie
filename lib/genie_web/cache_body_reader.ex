defmodule GenieWeb.CacheBodyReader do
  @moduledoc "Caches the raw request body in conn.private for webhook HMAC verification."

  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    conn = Plug.Conn.put_private(conn, :raw_body, body)
    {:ok, body, conn}
  end
end
