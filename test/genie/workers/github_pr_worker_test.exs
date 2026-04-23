defmodule Genie.Workers.GithubPrWorkerTest do
  use Genie.DataCase, async: false

  alias Genie.Accounts.{Organisation, User}
  alias Genie.Lamp.LampRegistry
  alias Genie.Workers.LampActionWorker

  @github_xml File.read!(Path.join([:code.priv_dir(:genie), "lamps", "github_pull_requests.xml"]))

  defp create_org! do
    n = System.unique_integer([:positive])

    Organisation
    |> Ash.Changeset.for_create(:create, %{name: "Org #{n}", slug: "org-#{n}"})
    |> Ash.create!(authorize?: false)
  end

  defp create_user_in_org!(org) do
    n = System.unique_integer([:positive])

    user =
      User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "user-#{n}@example.com",
        password: "password123",
        password_confirmation: "password123"
      })
      |> Ash.create!(authorize?: false)

    user
    |> Ash.Changeset.for_update(:update, %{org_id: org.id, role: :admin})
    |> Ash.update!(authorize?: false)
  end

  defp register_global_lamp! do
    LampRegistry
    |> Ash.Changeset.for_create(:register, %{org_id: nil, xml_source: @github_xml, enabled: true})
    |> Ash.create!(authorize?: false)
  end

  describe "perform/1 — GitHub PR list" do
    test "list_prs renders ready-list table with clickable rows" do
      org = create_org!()
      actor = create_user_in_org!(org)
      register_global_lamp!()
      session_id = Ecto.UUID.generate()

      Phoenix.PubSub.subscribe(Genie.PubSub, "canvas:#{session_id}")

      Req.Test.stub(Genie.Bridge, fn conn ->
        Req.Test.json(conn, %{
          "state" => "ready-list",
          "repo" => "acme/platform",
          "pull_requests" => [
            %{"number" => "42", "title" => "Add rate limiting", "author" => "alice", "state" => "open", "updated_at" => "2 hours ago"},
            %{"number" => "38", "title" => "Fix memory leak", "author" => "bob", "state" => "open", "updated_at" => "1 day ago"}
          ]
        })
      end)

      assert :ok =
               LampActionWorker.perform(%Oban.Job{
                 args: %{
                   "lamp_id" => "github.pulls.list",
                   "endpoint_id" => "list_prs",
                   "params" => %{"repo" => "acme/platform", "state" => "open"},
                   "actor_id" => actor.id,
                   "session_id" => session_id
                 }
               })

      assert_receive {:push_canvas, html}
      assert html =~ "Add rate limiting"
      assert html =~ "Fix memory leak"
      assert html =~ "alice"
      # Row-click attributes present
      assert html =~ "lamp_row_select"
      assert html =~ "phx-value-row-id"
    end

    test "fetch_pr_detail renders ready-detail panel" do
      org = create_org!()
      actor = create_user_in_org!(org)
      register_global_lamp!()
      session_id = Ecto.UUID.generate()

      Phoenix.PubSub.subscribe(Genie.PubSub, "canvas:#{session_id}")

      Req.Test.stub(Genie.Bridge, fn conn ->
        Req.Test.json(conn, %{
          "state" => "ready-detail",
          "pull_request" => %{
            "number" => "42",
            "title" => "Add rate limiting to API gateway",
            "author" => "alice",
            "state" => "open",
            "base" => "main",
            "head" => "feature/rate-limiting",
            "body" => "Implements token-bucket rate limiting.",
            "url" => "https://github.com/acme/platform/pull/42",
            "updated_at" => "2 hours ago"
          }
        })
      end)

      assert :ok =
               LampActionWorker.perform(%Oban.Job{
                 args: %{
                   "lamp_id" => "github.pulls.list",
                   "endpoint_id" => "fetch_pr_detail",
                   "params" => %{"id" => "42"},
                   "actor_id" => actor.id,
                   "session_id" => session_id
                 }
               })

      assert_receive {:push_canvas, html}
      assert html =~ "Add rate limiting to API gateway"
      assert html =~ "alice"
      assert html =~ "feature/rate-limiting"
      assert html =~ "Implements token-bucket rate limiting."
    end
  end
end
