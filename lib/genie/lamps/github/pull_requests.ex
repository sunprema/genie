defmodule Genie.Lamps.GitHub.PullRequests do
  @moduledoc """
  Inline handler for the `github.pulls.list` lamp. Serves static demo data;
  a future version will call the GitHub REST API.
  """

  use Genie.Lamp.Handler, lamp_id: "github.pulls.list"

  @demo_pulls [
    %{
      "number" => "42",
      "title" => "Add rate limiting to API gateway",
      "author" => "alice",
      "state" => "open",
      "base" => "main",
      "head" => "feature/rate-limiting",
      "updated_at" => "2 hours ago"
    },
    %{
      "number" => "38",
      "title" => "Fix memory leak in worker pool",
      "author" => "bob",
      "state" => "open",
      "base" => "main",
      "head" => "fix/worker-memory-leak",
      "updated_at" => "1 day ago"
    },
    %{
      "number" => "35",
      "title" => "Upgrade Elixir to 1.17",
      "author" => "carol",
      "state" => "closed",
      "base" => "main",
      "head" => "chore/elixir-upgrade",
      "updated_at" => "3 days ago"
    }
  ]

  @endpoint "list_prs"
  def handle_endpoint("list_prs", params, _ctx) do
    repo = Map.get(params, "repo", "acme/platform")
    state_filter = Map.get(params, "state", "open")

    filtered =
      if state_filter == "all" do
        @demo_pulls
      else
        Enum.filter(@demo_pulls, &(&1["state"] == state_filter))
      end

    {:ok, %{"state" => "ready-list", "repo" => repo, "pull_requests" => filtered}}
  end

  @endpoint "fetch_pr_detail"
  def handle_endpoint("fetch_pr_detail", %{"id" => pr_number}, _ctx) do
    {:ok,
     %{
       "state" => "ready-detail",
       "pull_request" => %{
         "number" => pr_number,
         "title" => "Add rate limiting to API gateway",
         "author" => "alice",
         "state" => "open",
         "base" => "main",
         "head" => "feature/rate-limiting",
         "body" =>
           "Implements token-bucket rate limiting at the API gateway layer to prevent abuse.",
         "url" => "https://github.com/acme/platform/pull/#{pr_number}",
         "updated_at" => "2 hours ago"
       }
     }}
  end
end
