defmodule GenieWeb.SecurityIntegrationTest do
  @moduledoc """
  Integration-level security tests — cross-org isolation, AuditLog append-only,
  and destructive lamp confirmation dialog.
  """
  use GenieWeb.ConnCase, async: false
  use Oban.Testing, repo: Genie.Repo

  import Phoenix.LiveViewTest

  alias Genie.Accounts.{Organisation, User}
  alias Genie.Audit.AuditLog
  alias Genie.Conductor
  alias Genie.Lamp.LampRegistry
  alias Genie.Workers.LampActionWorker

  @s3_xml File.read!(Path.join([:code.priv_dir(:genie), "lamps", "aws_s3_create_bucket.xml"]))

  defp create_org! do
    n = System.unique_integer([:positive])

    Organisation
    |> Ash.Changeset.for_create(:create, %{name: "Org #{n}", slug: "org-#{n}"})
    |> Ash.create!(authorize?: false)
  end

  defp create_user_in_org!(org, role \\ :member) do
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
    |> Ash.Changeset.for_update(:update, %{org_id: org.id, role: role})
    |> Ash.update!(authorize?: false)
  end

  defp authed_conn(user) do
    token = user.__metadata__[:token]
    build_conn() |> Plug.Test.init_test_session(%{"user_token" => token})
  end

  # ─── Cross-org isolation ──────────────────────────────────────────────────────

  describe "cross-org actor isolation" do
    test "actor from Org A cannot trigger a lamp action registered for Org B" do
      org_a = create_org!()
      org_b = create_org!()
      actor_a = create_user_in_org!(org_a, :admin)

      LampRegistry
      |> Ash.Changeset.for_create(:register, %{org_id: org_b.id, xml_source: @s3_xml, enabled: true})
      |> Ash.create!(authorize?: false)

      assert {:error, %Ash.Error.Forbidden{}} =
               Conductor.build_action(
                 "aws.s3.create-bucket",
                 "create_bucket",
                 %{"bucket_name" => "cross-org-bucket"},
                 actor: actor_a
               )
    end

    test "actor from Org B cannot build a lamp action registered for Org A" do
      org_a = create_org!()
      org_b = create_org!()
      actor_b = create_user_in_org!(org_b, :admin)

      LampRegistry
      |> Ash.Changeset.for_create(:register, %{org_id: org_a.id, xml_source: @s3_xml, enabled: true})
      |> Ash.create!(authorize?: false)

      assert {:error, %Ash.Error.Forbidden{}} =
               Conductor.build_action(
                 "aws.s3.create-bucket",
                 "create_bucket",
                 %{},
                 actor: actor_b
               )
    end

    test "global lamp (org_id nil) is accessible by any authenticated actor" do
      org = create_org!()
      actor = create_user_in_org!(org, :admin)

      LampRegistry
      |> Ash.Changeset.for_create(:register, %{org_id: nil, xml_source: @s3_xml, enabled: true})
      |> Ash.create!(authorize?: false)

      assert {:ok, _} =
               Conductor.build_action(
                 "aws.s3.create-bucket",
                 "create_bucket",
                 %{},
                 actor: actor
               )
    end
  end

  # ─── AuditLog append-only ─────────────────────────────────────────────────────

  describe "AuditLog append-only policy" do
    test "update action is rejected at policy layer" do
      org = create_org!()
      actor = create_user_in_org!(org)

      {:ok, log} =
        AuditLog
        |> Ash.Changeset.for_create(:create, %{lamp_id: "test.lamp", result: :success})
        |> Ash.create(authorize?: false)

      assert {:error, %Ash.Error.Forbidden{}} =
               log
               |> Ash.Changeset.for_update(:update, %{lamp_id: "tampered"})
               |> Ash.update(actor: actor)
    end

    test "destroy action is rejected at policy layer" do
      org = create_org!()
      actor = create_user_in_org!(org)

      {:ok, log} =
        AuditLog
        |> Ash.Changeset.for_create(:create, %{lamp_id: "test.lamp", result: :success})
        |> Ash.create(authorize?: false)

      assert {:error, %Ash.Error.Forbidden{}} =
               log
               |> Ash.Changeset.for_destroy(:destroy)
               |> Ash.destroy(actor: actor)
    end
  end

  # ─── Browser routes through Bridge ───────────────────────────────────────────

  describe "lamp actions route exclusively through Bridge" do
    test "lamp_submit enqueues LampActionWorker — browser never calls backend directly" do
      org = create_org!()
      user = create_user_in_org!(org)
      conn = authed_conn(user)

      {:ok, view, _html} = live(conn, "/cockpit")

      render_click(view, "lamp_submit", %{
        "lamp_id" => "aws.s3.create-bucket",
        "endpoint_id" => "create_bucket",
        "params" => %{"bucket_name" => "test"}
      })

      assert_enqueued(worker: LampActionWorker)
    end
  end

  # ─── Destructive lamp confirmation ────────────────────────────────────────────

  describe "destructive lamp requires confirmation before LampActionWorker is inserted" do
    test "lamp_submit with destructive=true does NOT immediately enqueue LampActionWorker" do
      org = create_org!()
      user = create_user_in_org!(org)
      conn = authed_conn(user)

      {:ok, view, _html} = live(conn, "/cockpit")

      render_click(view, "lamp_submit", %{
        "lamp_id" => "aws.s3.create-bucket",
        "endpoint_id" => "delete_bucket",
        "destructive" => "true",
        "params" => %{}
      })

      refute_enqueued(worker: LampActionWorker)
    end

    test "lamp_confirm_destructive enqueues LampActionWorker after user confirms" do
      org = create_org!()
      user = create_user_in_org!(org)
      conn = authed_conn(user)

      {:ok, view, _html} = live(conn, "/cockpit")

      render_click(view, "lamp_submit", %{
        "lamp_id" => "aws.s3.create-bucket",
        "endpoint_id" => "delete_bucket",
        "destructive" => "true",
        "params" => %{}
      })

      refute_enqueued(worker: LampActionWorker)

      render_click(view, "lamp_confirm_destructive", %{})

      assert_enqueued(worker: LampActionWorker)
    end

    test "non-destructive lamp_submit enqueues LampActionWorker immediately" do
      org = create_org!()
      user = create_user_in_org!(org)
      conn = authed_conn(user)

      {:ok, view, _html} = live(conn, "/cockpit")

      render_click(view, "lamp_submit", %{
        "lamp_id" => "aws.s3.create-bucket",
        "endpoint_id" => "create_bucket",
        "params" => %{"bucket_name" => "test"}
      })

      assert_enqueued(worker: LampActionWorker)
    end

    test "lamp_confirm_destructive without pending action is a no-op" do
      org = create_org!()
      user = create_user_in_org!(org)
      conn = authed_conn(user)

      {:ok, view, _html} = live(conn, "/cockpit")

      render_click(view, "lamp_confirm_destructive", %{})

      refute_enqueued(worker: LampActionWorker)
    end
  end
end
