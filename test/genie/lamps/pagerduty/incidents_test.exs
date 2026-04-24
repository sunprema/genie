defmodule Genie.Lamps.PagerDuty.IncidentsTest do
  use ExUnit.Case, async: true

  alias Genie.Lamp.Handler.Context
  alias Genie.Lamps.PagerDuty.Incidents

  defp ctx do
    %Context{
      lamp_id: "pagerduty.incidents.list",
      endpoint_id: "list_incidents",
      session_id: "t",
      trace_id: "trace-1"
    }
  end

  test "list_incidents returns ready state with the expected incident shape" do
    assert {:ok, response} = Incidents.handle_endpoint("list_incidents", %{}, ctx())

    assert response["state"] == "ready"
    assert response["count"] == length(response["incidents"])

    [first | _] = response["incidents"]
    assert first["title"]
    assert first["severity"]
    assert first["service"]
    assert first["status"]
  end
end
