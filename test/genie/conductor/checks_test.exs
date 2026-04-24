defmodule Genie.Conductor.ChecksTest do
  use Genie.DataCase, async: true

  alias Genie.Accounts.{Organisation, User}
  alias Genie.Accounts.Checks.{ActorOrg, IsSelf, SameOrg}
  alias Genie.Conductor.Checks.{HasRequiredRole, LampOrgAccess}
  alias Genie.Conversation.Checks.TurnSameOrg
  alias Genie.Lamp.LampRegistry

  @valid_xml File.read!(Path.join([:code.priv_dir(:genie), "lamps", "aws_s3_create_bucket.xml"]))

  defp create_org! do
    n = System.unique_integer([:positive])

    Organisation
    |> Ash.Changeset.for_create(:create, %{name: "Org #{n}", slug: "org-#{n}"})
    |> Ash.create!(authorize?: false)
  end

  defp create_user!(org, role \\ :member) do
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

  defp register_lamp!(xml \\ @valid_xml) do
    LampRegistry
    |> Ash.Changeset.for_create(:register, %{org_id: nil, xml_source: xml, enabled: true})
    |> Ash.create!(authorize?: false)
  end

  defp fake_changeset(lamp_id) do
    cs = Ash.Changeset.new(Genie.Conductor.LampAction)
    %{cs | attributes: Map.put(cs.attributes, :lamp_id, lamp_id)}
  end

  describe "HasRequiredRole.match?/3" do
    test "returns false for nil actor" do
      assert HasRequiredRole.match?(nil, %{}, []) == false
    end

    test "returns false for nil actor with context" do
      changeset = fake_changeset("aws.s3.create-bucket")
      assert HasRequiredRole.match?(nil, %{changeset: changeset}, []) == false
    end

    test "returns true for admin actor on non-destructive lamp" do
      register_lamp!()
      org = create_org!()
      actor = create_user!(org, :admin)

      changeset = fake_changeset("aws.s3.create-bucket")
      assert HasRequiredRole.match?(actor, %{changeset: changeset}, []) == true
    end

    test "returns true for member actor on non-destructive lamp" do
      register_lamp!()
      org = create_org!()
      actor = create_user!(org, :member)

      changeset = fake_changeset("aws.s3.create-bucket")
      assert HasRequiredRole.match?(actor, %{changeset: changeset}, []) == true
    end

    test "returns false for unknown lamp_id" do
      org = create_org!()
      actor = create_user!(org, :admin)

      changeset = fake_changeset("unknown.lamp")
      assert HasRequiredRole.match?(actor, %{changeset: changeset}, []) == false
    end
  end

  describe "LampOrgAccess.match?/3" do
    test "returns false for nil actor" do
      assert LampOrgAccess.match?(nil, %{}, []) == false
    end

    test "returns true for actor with global lamp access" do
      register_lamp!()
      org = create_org!()
      actor = create_user!(org)

      changeset = fake_changeset("aws.s3.create-bucket")
      assert LampOrgAccess.match?(actor, %{changeset: changeset}, []) == true
    end

    test "returns false for unknown lamp_id" do
      org = create_org!()
      actor = create_user!(org)

      changeset = fake_changeset("unknown.lamp")
      assert LampOrgAccess.match?(actor, %{changeset: changeset}, []) == false
    end
  end

  describe "TurnSameOrg.filter/3" do
    test "returns false for nil actor" do
      assert TurnSameOrg.filter(nil, nil, nil) == false
    end
  end

  describe "Accounts check describe/1" do
    test "ActorOrg describes the check" do
      assert ActorOrg.describe([]) =~ "organisation"
    end

    test "SameOrg describes the check" do
      assert SameOrg.describe([]) =~ "organisation"
    end

    test "IsSelf describes the check" do
      assert IsSelf.describe([]) =~ "actor"
    end
  end
end
