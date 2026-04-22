defmodule Genie.Audit.AuditLogTest do
  use Genie.DataCase, async: true

  alias Genie.Accounts.{Organisation, User}
  alias Genie.Audit.AuditLog

  # --- helpers ---

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
    |> Ash.Changeset.for_update(:update, %{org_id: org.id})
    |> Ash.update!(authorize?: false)
  end

  defp create_audit_log! do
    AuditLog
    |> Ash.Changeset.for_create(:create, %{
      lamp_id: "aws.s3.create-bucket",
      intent_name: "create_bucket",
      result: :success
    })
    |> Ash.create!(authorize?: false)
  end

  # --- append-only policy tests ---

  describe "AuditLog append-only policy" do
    test "read action is permitted" do
      org = create_org!()
      actor = create_user_in_org!(org)
      _log = create_audit_log!()

      assert {:ok, _logs} = Ash.read(AuditLog, actor: actor)
    end

    test "create action is permitted" do
      org = create_org!()
      actor = create_user_in_org!(org)

      result =
        AuditLog
        |> Ash.Changeset.for_create(:create, %{
          lamp_id: "test.lamp",
          result: :success
        })
        |> Ash.create(actor: actor)

      assert {:ok, _log} = result
    end

    test "update action is rejected at policy layer" do
      org = create_org!()
      actor = create_user_in_org!(org)
      log = create_audit_log!()

      result =
        log
        |> Ash.Changeset.for_update(:update, %{lamp_id: "modified"})
        |> Ash.update(actor: actor)

      assert {:error, %Ash.Error.Forbidden{}} = result
    end

    test "destroy action is rejected at policy layer" do
      org = create_org!()
      actor = create_user_in_org!(org)
      log = create_audit_log!()

      result =
        log
        |> Ash.Changeset.for_destroy(:destroy)
        |> Ash.destroy(actor: actor)

      assert {:error, %Ash.Error.Forbidden{}} = result
    end
  end
end
