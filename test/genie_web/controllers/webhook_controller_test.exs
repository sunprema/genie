defmodule GenieWeb.WebhookControllerTest do
  use GenieWeb.ConnCase, async: true
  use Oban.Testing, repo: Genie.Repo

  @secret "test-secret"
  @lamp_id "pagerduty.incidents.list"

  setup do
    Application.put_env(:genie, :pagerduty_webhook_secret, @secret)
    on_exit(fn -> Application.delete_env(:genie, :pagerduty_webhook_secret) end)
    :ok
  end

  defp sign(body, secret \\ @secret) do
    digest =
      :crypto.mac(:hmac, :sha256, secret, body)
      |> Base.encode16(case: :lower)

    "v1=#{digest}"
  end

  defp post_webhook(conn, body_map, signature) do
    body = Jason.encode!(body_map)

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-pagerduty-signature", signature)
    |> post("/webhooks/#{@lamp_id}", body)
  end

  describe "POST /webhooks/:lamp_id" do
    test "returns 200 and enqueues job with valid signature", %{conn: conn} do
      body = %{"event" => "incident.trigger", "id" => "abc123"}
      sig = sign(Jason.encode!(body))

      conn = post_webhook(conn, body, sig)

      assert conn.status == 200

      assert_enqueued(
        worker: Genie.Workers.LampActionWorker,
        args: %{"lamp_id" => @lamp_id, "trigger" => "webhook"}
      )
    end

    test "returns 401 with invalid signature", %{conn: conn} do
      body = %{"event" => "incident.trigger"}

      conn = post_webhook(conn, body, "v1=invalidsignature")

      assert conn.status == 401
    end

    test "returns 401 with missing signature", %{conn: conn} do
      body = Jason.encode!(%{"event" => "incident.trigger"})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/#{@lamp_id}", body)

      assert conn.status == 401
    end

    test "returns 401 when signature uses wrong secret", %{conn: conn} do
      body = %{"event" => "incident.trigger"}
      wrong_sig = sign(Jason.encode!(body), "wrong-secret")

      conn = post_webhook(conn, body, wrong_sig)

      assert conn.status == 401
    end
  end
end
