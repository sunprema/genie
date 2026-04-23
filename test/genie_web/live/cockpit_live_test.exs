defmodule GenieWeb.CockpitLiveTest do
  use GenieWeb.ConnCase, async: false
  use Oban.Testing, repo: Genie.Repo

  import Phoenix.LiveViewTest

  alias Genie.Accounts.{Organisation, User}
  alias Genie.Workers.{LampActionWorker, OrchestratorWorker}

  setup do
    n = System.unique_integer([:positive])

    org =
      Organisation
      |> Ash.Changeset.for_create(:create, %{name: "Org #{n}", slug: "org-#{n}"})
      |> Ash.create!(authorize?: false)

    user =
      User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "user-#{n}@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create!(authorize?: false)

    user =
      user
      |> Ash.Changeset.for_update(:update, %{org_id: org.id})
      |> Ash.update!(authorize?: false)

    # Use the registration token directly — it's stored in the DB via GenerateTokenChange
    token = user.__metadata__.token

    authed_conn =
      build_conn()
      |> Plug.Test.init_test_session(%{"user_token" => token})

    {:ok, conn: authed_conn, user: user}
  end

  describe "mount/3" do
    test "redirects unauthenticated users to sign-in", %{conn: _conn} do
      {:error, {:redirect, %{to: path}}} = live(build_conn(), "/cockpit")
      assert path =~ "/sign-in"
    end

    test "mounts successfully for authenticated users", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/cockpit")
      assert html =~ "Workspace"
      assert html =~ "Ask Genie"
    end
  end

  describe "send_message event" do
    test "inserts an OrchestratorWorker job and appends user message to stream", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cockpit")

      view
      |> form("form[phx-submit='send_message']", %{"message" => "create a bucket"})
      |> render_submit()

      assert_enqueued(worker: OrchestratorWorker, args: %{"user_message" => "create a bucket"})

      html = render(view)
      assert html =~ "create a bucket"
    end

    test "does not insert job for empty message", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cockpit")

      view
      |> form("form[phx-submit='send_message']", %{"message" => "   "})
      |> render_submit()

      refute_enqueued(worker: OrchestratorWorker)
    end
  end

  describe "push_canvas broadcast" do
    test "push_event update_canvas is sent when canvas broadcast received", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cockpit")

      session_id_assign =
        :sys.get_state(view.pid).socket.assigns.session_id

      html = "<div>bucket created</div>"
      GenieWeb.CockpitLive.push_canvas(session_id_assign, html)

      assert_push_event(view, "update_canvas", %{html: ^html})
    end
  end

  describe "lamp_submit event" do
    test "inserts a LampActionWorker job", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cockpit")

      render_hook(view, "lamp_submit", %{
        "lamp_id" => "aws.s3.create-bucket",
        "endpoint_id" => "create_bucket",
        "params" => %{"bucket_name" => "test-bucket"}
      })

      assert_enqueued(worker: LampActionWorker, args: %{"lamp_id" => "aws.s3.create-bucket"})
    end
  end

  describe "handle_info :push_chat" do
    test "appends agent message to stream", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cockpit")

      session_id = :sys.get_state(view.pid).socket.assigns.session_id
      GenieWeb.CockpitLive.push_chat(session_id, "I found the right tool for that.")

      html = render(view)
      assert html =~ "I found the right tool for that."
    end
  end

  describe "handle_info :push_error" do
    test "appends error message to stream and pushes canvas_error event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cockpit")

      session_id = :sys.get_state(view.pid).socket.assigns.session_id
      GenieWeb.CockpitLive.push_error(session_id, "Something went wrong")

      html = render(view)
      assert html =~ "Something went wrong"

      assert_push_event(view, "canvas_error", %{reason: "Something went wrong"})
    end
  end
end
