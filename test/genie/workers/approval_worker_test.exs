defmodule Genie.Workers.ApprovalWorkerTest do
  use Genie.DataCase, async: false

  require Ash.Query

  alias Genie.Accounts.{Organisation, User}
  alias Genie.Audit.AuditLog
  alias Genie.Conductor
  alias Genie.Lamp.LampRegistry
  alias Genie.Workers.ApprovalWorker

  @valid_xml File.read!(Path.join([:code.priv_dir(:genie), "lamps", "aws_s3_create_bucket.xml"]))

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
    |> Ash.Changeset.for_create(:register, %{org_id: nil, xml_source: @valid_xml, enabled: true})
    |> Ash.create!(authorize?: false)
  end

  describe "perform/1 on denial" do
    test "writes a denied AuditLog entry" do
      org = create_org!()
      actor = create_user_in_org!(org)
      register_global_lamp!()

      {:ok, lamp_action} =
        Conductor.build_action("aws.s3.create-bucket", "create_bucket", %{}, actor: actor)

      assert :ok =
               ApprovalWorker.perform(%Oban.Job{
                 args: %{
                   "action_id" => lamp_action.id,
                   "approver_id" => actor.id,
                   "decision" => "deny"
                 }
               })

      assert {:ok, [audit_entry]} =
               AuditLog
               |> Ash.Query.filter(lamp_id == ^lamp_action.lamp_id and result == :denied)
               |> Ash.read(authorize?: false)

      assert audit_entry.result == :denied
      assert audit_entry.lamp_id == "aws.s3.create-bucket"
    end

    test "notifies the requester session with push_error on denial" do
      org = create_org!()
      actor = create_user_in_org!(org)
      register_global_lamp!()

      session_id = Ecto.UUID.generate()

      {:ok, lamp_action} =
        Conductor.build_action("aws.s3.create-bucket", "create_bucket", %{},
          actor: actor,
          session_id: session_id
        )

      Phoenix.PubSub.subscribe(Genie.PubSub, "canvas:#{session_id}")
      Phoenix.PubSub.subscribe(Genie.PubSub, "chat:#{session_id}")

      assert :ok =
               ApprovalWorker.perform(%Oban.Job{
                 args: %{
                   "action_id" => lamp_action.id,
                   "approver_id" => actor.id,
                   "decision" => "deny"
                 }
               })

      assert_receive {:push_error, :denied}
    end
  end

  describe "perform/1 on pending" do
    test "does nothing and returns :ok" do
      assert :ok =
               ApprovalWorker.perform(%Oban.Job{
                 args: %{
                   "action_id" => Ecto.UUID.generate(),
                   "approver_id" => nil,
                   "decision" => "pending"
                 }
               })
    end
  end

  describe "perform/1 on approval — poll loop" do
    test "executes lamp then polls until status=ready, pushing two canvas updates" do
      org = create_org!()
      actor = create_user_in_org!(org)
      register_global_lamp!()

      session_id = Ecto.UUID.generate()

      {:ok, lamp_action} =
        Conductor.build_action("aws.s3.create-bucket", "create_bucket",
          %{"bucket_name" => "test-bucket", "region" => "us-east-1"},
          actor: actor,
          session_id: session_id
        )

      Phoenix.PubSub.subscribe(Genie.PubSub, "canvas:#{session_id}")

      call_count = :counters.new(1, [])

      Req.Test.stub(Genie.Bridge, fn conn ->
        :counters.add(call_count, 1, 1)

        Req.Test.json(conn, %{
          "status" => "ready",
          "state" => "ready",
          "bucket_name" => "test-bucket",
          "console_url" => "https://s3.console.aws.amazon.com/s3/buckets/test-bucket"
        })
      end)

      assert :ok =
               ApprovalWorker.perform(%Oban.Job{
                 args: %{
                   "action_id" => lamp_action.id,
                   "approver_id" => actor.id,
                   "decision" => "approve"
                 }
               })

      # First push_canvas: execution result; second: poll result
      assert_receive {:push_canvas, _html1}
      assert_receive {:push_canvas, _html2}

      # At least 2 Bridge calls: create_bucket + poll_status
      assert :counters.get(call_count, 1) >= 2
    end
  end
end
