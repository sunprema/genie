defmodule Genie.Workers.ApprovalWorkerTest do
  use Genie.DataCase, async: false

  require Ash.Query

  alias Genie.Workers.ApprovalWorker
  alias Genie.Accounts.{Organisation, User}
  alias Genie.Audit.AuditLog
  alias Genie.Conductor
  alias Genie.Lamp.LampRegistry

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
  end
end
