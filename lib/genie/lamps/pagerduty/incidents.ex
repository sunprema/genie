defmodule Genie.Lamps.PagerDuty.Incidents do
  @moduledoc """
  Inline handler for the `pagerduty.incidents.list` lamp. Currently serves
  static demo data; a future version will call the PagerDuty API.
  """

  use Genie.Lamp.Handler, lamp_id: "pagerduty.incidents.list"

  @endpoint "list_incidents"
  def handle_endpoint("list_incidents", _params, _ctx) do
    {:ok,
     %{
       "state" => "ready",
       "count" => 3,
       "incidents" => [
         %{
           "title" => "Database CPU spike — payments-db",
           "severity" => "high",
           "service" => "payments-db",
           "status" => "triggered",
           "created_at" => "2 min ago"
         },
         %{
           "title" => "Elevated error rate — checkout API",
           "severity" => "medium",
           "service" => "checkout-api",
           "status" => "acknowledged",
           "created_at" => "11 min ago"
         },
         %{
           "title" => "Memory pressure — auth-service pods",
           "severity" => "critical",
           "service" => "auth-service",
           "status" => "triggered",
           "created_at" => "just now"
         }
       ]
     }}
  end
end
