defmodule GenieWeb.HealthController do
  use GenieWeb, :controller

  def index(conn, _params) do
    db_ok = check_db()
    oban_status = check_oban_queues()

    http_status = if db_ok, do: 200, else: 503

    json(conn |> put_status(http_status), %{
      status: if(db_ok, do: "ok", else: "degraded"),
      db: if(db_ok, do: "ok", else: "error"),
      oban_queues: oban_status
    })
  end

  defp check_db do
    case Ecto.Adapters.SQL.query(Genie.Repo, "SELECT 1", []) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp check_oban_queues do
    queues = [:orchestrator, :lamp_actions, :approvals, :notifications]

    Enum.map(queues, fn queue ->
      count =
        case Oban.check_queue(Oban, queue: queue) do
          %{running: running} -> running
          _ -> 0
        end

      {queue, count}
    end)
    |> Map.new()
  end
end
