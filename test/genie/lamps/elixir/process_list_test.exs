defmodule Genie.Lamps.Elixir.ProcessListTest do
  use ExUnit.Case, async: true

  alias Genie.Lamp.Handler.Context
  alias Genie.Lamps.Elixir.ProcessList

  defp ctx(endpoint_id) do
    %Context{
      lamp_id: "elixir.process.list",
      endpoint_id: endpoint_id,
      session_id: "t",
      trace_id: "trace-1"
    }
  end

  describe "handle_endpoint/3 — list_processes" do
    test "returns ready-list state with a non-empty processes list" do
      assert {:ok, response} = ProcessList.handle_endpoint("list_processes", %{}, ctx("list_processes"))
      assert response["state"] == "ready-list"
      assert is_list(response["processes"])
      assert length(response["processes"]) > 0
    end

    test "each process summary carries the expected keys" do
      {:ok, response} = ProcessList.handle_endpoint("list_processes", %{}, ctx("list_processes"))
      [first | _] = response["processes"]

      assert is_binary(first.pid)
      assert is_binary(first.current_function)
      assert is_integer(first.memory_kb)
      assert is_integer(first.message_queue_len)
    end

    test "defaults filter to 'all' when params empty" do
      {:ok, response} = ProcessList.handle_endpoint("list_processes", %{}, ctx("list_processes"))
      assert response["filter"] == "all"
    end

    test "named filter restricts to registered processes" do
      {:ok, response} =
        ProcessList.handle_endpoint("list_processes", %{"filter" => "named"}, ctx("list_processes"))

      assert response["filter"] == "named"
      assert Enum.all?(response["processes"], &(&1.registered_name != ""))
    end
  end

  describe "handle_endpoint/3 — fetch_process" do
    test "returns ready-detail for a valid pid" do
      self_pid_str = self() |> inspect() |> String.replace_prefix("#PID<", "") |> String.replace_suffix(">", "")

      assert {:ok, response} =
               ProcessList.handle_endpoint(
                 "fetch_process",
                 %{"id" => self_pid_str},
                 ctx("fetch_process")
               )

      assert response["state"] == "ready-detail"
      assert response["process"].pid == self_pid_str
    end

    test "returns failed state for an invalid pid string" do
      assert {:ok, response} =
               ProcessList.handle_endpoint(
                 "fetch_process",
                 %{"id" => "not-a-pid"},
                 ctx("fetch_process")
               )

      assert response["state"] == "failed"
      assert response["error_message"] =~ "Invalid PID"
    end

    test "returns failed state when the pid no longer exists" do
      {:ok, dead_pid} = Task.start(fn -> :ok end)
      Process.sleep(10)
      refute Process.alive?(dead_pid)

      dead_pid_str =
        dead_pid |> inspect() |> String.replace_prefix("#PID<", "") |> String.replace_suffix(">", "")

      {:ok, response} =
        ProcessList.handle_endpoint(
          "fetch_process",
          %{"id" => dead_pid_str},
          ctx("fetch_process")
        )

      assert response["state"] == "failed"
      assert response["error_message"] =~ "no longer exists"
    end
  end
end
