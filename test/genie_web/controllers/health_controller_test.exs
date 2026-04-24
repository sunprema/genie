defmodule GenieWeb.HealthControllerTest do
  use GenieWeb.ConnCase, async: true

  describe "GET /health" do
    test "returns 200 with ok status when db is available", %{conn: conn} do
      conn = get(conn, "/health")

      assert conn.status == 200
      body = json_response(conn, 200)
      assert body["status"] == "ok"
      assert body["db"] == "ok"
      assert is_map(body["oban_queues"])
    end

    test "includes oban queue counts in response", %{conn: conn} do
      conn = get(conn, "/health")
      body = json_response(conn, 200)

      assert Map.has_key?(body["oban_queues"], "orchestrator")
      assert Map.has_key?(body["oban_queues"], "lamp_actions")
      assert Map.has_key?(body["oban_queues"], "approvals")
      assert Map.has_key?(body["oban_queues"], "notifications")
    end
  end
end
