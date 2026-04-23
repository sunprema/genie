defmodule GenieWeb.WebhookController do
  use GenieWeb, :controller

  require Logger

  alias Genie.Lamp.LampRegistry
  alias Genie.Workers.LampActionWorker

  @signature_header "x-pagerduty-signature"

  def create(conn, %{"lamp_id" => lamp_id}) do
    raw_body = conn.private[:raw_body] || ""
    signature = conn |> get_req_header(@signature_header) |> List.first()

    case verify_signature(lamp_id, raw_body, signature) do
      :ok ->
        org_id = fetch_lamp_org(lamp_id)

        %{
          "lamp_id" => lamp_id,
          "trigger" => "webhook",
          "payload" => conn.body_params,
          "org_id" => org_id
        }
        |> LampActionWorker.new()
        |> Oban.insert()

        send_resp(conn, 200, "")

      {:error, :invalid_signature} ->
        Logger.warning("Webhook rejected for lamp=#{lamp_id}: invalid signature")
        send_resp(conn, 401, "Invalid signature")
    end
  end

  defp verify_signature(lamp_id, body, signature) do
    secret = webhook_secret(lamp_id)

    expected =
      :crypto.mac(:hmac, :sha256, secret, body)
      |> Base.encode16(case: :lower)

    received = parse_signature(signature)

    if received && Plug.Crypto.secure_compare(expected, received) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  # PagerDuty format: "v1=<hex_digest>"
  defp parse_signature(nil), do: nil
  defp parse_signature("v1=" <> hex), do: hex
  defp parse_signature(hex), do: hex

  defp webhook_secret(_lamp_id) do
    Application.get_env(:genie, :pagerduty_webhook_secret, "dev-secret")
  end

  defp fetch_lamp_org(lamp_id) do
    case LampRegistry.by_lamp_id(lamp_id, authorize?: false) do
      {:ok, record} -> record.org_id
      {:error, _} -> nil
    end
  end
end
