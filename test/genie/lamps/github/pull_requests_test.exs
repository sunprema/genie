defmodule Genie.Lamps.GitHub.PullRequestsTest do
  use ExUnit.Case, async: true

  alias Genie.Lamp.Handler.Context
  alias Genie.Lamps.GitHub.PullRequests

  defp ctx(endpoint_id) do
    %Context{
      lamp_id: "github.pulls.list",
      endpoint_id: endpoint_id,
      session_id: "t",
      trace_id: "trace-1"
    }
  end

  describe "handle_endpoint/3 — list_prs" do
    test "filters by state open by default" do
      {:ok, response} = PullRequests.handle_endpoint("list_prs", %{"repo" => "r"}, ctx("list_prs"))
      assert response["state"] == "ready-list"
      assert Enum.all?(response["pull_requests"], &(&1["state"] == "open"))
    end

    test "state=all returns all pulls" do
      {:ok, response} =
        PullRequests.handle_endpoint(
          "list_prs",
          %{"repo" => "r", "state" => "all"},
          ctx("list_prs")
        )

      assert length(response["pull_requests"]) >= 3
    end

    test "propagates the repo param into the response" do
      {:ok, response} =
        PullRequests.handle_endpoint(
          "list_prs",
          %{"repo" => "foo/bar"},
          ctx("list_prs")
        )

      assert response["repo"] == "foo/bar"
    end
  end

  describe "handle_endpoint/3 — fetch_pr_detail" do
    test "returns ready-detail with the requested PR number" do
      {:ok, response} =
        PullRequests.handle_endpoint(
          "fetch_pr_detail",
          %{"id" => "42"},
          ctx("fetch_pr_detail")
        )

      assert response["state"] == "ready-detail"
      assert response["pull_request"]["number"] == "42"
      assert response["pull_request"]["url"] =~ "/pull/42"
    end
  end
end
