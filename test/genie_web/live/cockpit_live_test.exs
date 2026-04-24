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
        "lamp-id" => "aws.s3.create-bucket",
        "endpoint-id" => "create_bucket",
        "destructive" => "false"
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

  describe "lamp_field_change event" do
    test "updates lamp_field_values in assigns", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cockpit")

      render_hook(view, "lamp_field_change", %{
        "bucket_name" => "my-bucket",
        "region" => "us-east-1"
      })

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.lamp_field_values["bucket_name"] == "my-bucket"
      assert assigns.lamp_field_values["region"] == "us-east-1"
    end

    test "merges with existing field values", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cockpit")

      render_hook(view, "lamp_field_change", %{"bucket_name" => "first"})
      render_hook(view, "lamp_field_change", %{"region" => "us-west-2"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.lamp_field_values["bucket_name"] == "first"
      assert assigns.lamp_field_values["region"] == "us-west-2"
    end
  end

  describe "lamp_toggle event" do
    test "updates field value in lamp_field_values", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cockpit")

      render_hook(view, "lamp_toggle", %{"field" => "versioning", "value" => "true"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.lamp_field_values["versioning"] == "true"
    end
  end

  describe "lamp_group_toggle event" do
    test "toggles group state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cockpit")

      render_hook(view, "lamp_group_toggle", %{"group" => "advanced_config"})
      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.lamp_group_states["advanced_config"] == true

      render_hook(view, "lamp_group_toggle", %{"group" => "advanced_config"})
      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.lamp_group_states["advanced_config"] == false
    end
  end

  describe "lamp_submit destructive path" do
    test "destructive submit stores params and pushes lamp_confirm_needed event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cockpit")

      render_hook(view, "lamp_submit", %{
        "lamp-id" => "aws.s3.create-bucket",
        "endpoint-id" => "delete_bucket",
        "destructive" => "true"
      })

      assert_push_event(view, "lamp_confirm_needed", %{lamp_id: _})
      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.pending_destructive_action["destructive"] == "true"
    end

    test "lamp_confirm_destructive enqueues job and clears pending action", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cockpit")

      render_hook(view, "lamp_submit", %{
        "lamp-id" => "aws.s3.create-bucket",
        "endpoint-id" => "delete_bucket",
        "destructive" => "true"
      })

      render_hook(view, "lamp_confirm_destructive", %{})

      assert_enqueued(worker: LampActionWorker)
      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.pending_destructive_action == nil
    end

    test "lamp_confirm_destructive with no pending action does nothing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cockpit")

      render_hook(view, "lamp_confirm_destructive", %{})

      refute_enqueued(worker: LampActionWorker)
    end
  end

  describe "lamp_row_select event" do
    test "enqueues LampActionWorker job with row params", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cockpit")

      render_hook(view, "lamp_row_select", %{
        "lamp-id" => "aws.ec2.list-instances",
        "row-id" => "i-0abc1234",
        "endpoint-id" => "restart_instance"
      })

      assert_enqueued(worker: LampActionWorker, args: %{"lamp_id" => "aws.ec2.list-instances"})
    end
  end

  describe "approve_action event" do
    test "with no pending approval does nothing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cockpit")

      render_hook(view, "approve_action", %{})

      refute_enqueued(worker: Genie.Workers.ApprovalWorker)
    end

    test "with pending approval enqueues ApprovalWorker and clears pending", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cockpit")

      session_id = :sys.get_state(view.pid).socket.assigns.session_id
      GenieWeb.CockpitLive.push_pending_approval(session_id, "action-123")
      render(view)

      render_hook(view, "approve_action", %{})

      assert_enqueued(worker: Genie.Workers.ApprovalWorker, args: %{"decision" => "approve"})
      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.pending_approval == nil
    end
  end

  describe "deny_action event" do
    test "with no pending approval does nothing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cockpit")

      render_hook(view, "deny_action", %{})

      refute_enqueued(worker: Genie.Workers.ApprovalWorker)
    end

    test "with pending approval enqueues deny decision", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cockpit")

      session_id = :sys.get_state(view.pid).socket.assigns.session_id
      GenieWeb.CockpitLive.push_pending_approval(session_id, "action-456")
      render(view)

      render_hook(view, "deny_action", %{})

      assert_enqueued(worker: Genie.Workers.ApprovalWorker, args: %{"decision" => "deny"})
    end
  end

  describe "handle_info :pending_approval" do
    test "sets pending_approval assign", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cockpit")

      session_id = :sys.get_state(view.pid).socket.assigns.session_id
      GenieWeb.CockpitLive.push_pending_approval(session_id, "action-789")

      render(view)
      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.pending_approval == "action-789"
    end
  end
end
