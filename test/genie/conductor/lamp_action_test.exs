defmodule Genie.ConductorTest do
  use Genie.DataCase, async: true

  alias Genie.Conductor
  alias Genie.Conductor.LampAction
  alias Genie.Accounts.{Organisation, User}
  alias Genie.Lamp.LampRegistry

  @valid_xml File.read!(Path.join([
               :code.priv_dir(:genie),
               "lamps",
               "aws_s3_create_bucket.xml"
             ]))

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

  defp register_global_lamp! do
    LampRegistry
    |> Ash.Changeset.for_create(:register, %{
      org_id: nil,
      xml_source: @valid_xml,
      enabled: true
    })
    |> Ash.create!(authorize?: false)
  end

  defp register_org_lamp!(org_id) do
    LampRegistry
    |> Ash.Changeset.for_create(:register, %{
      org_id: org_id,
      xml_source: @valid_xml,
      enabled: true
    })
    |> Ash.create!(authorize?: false)
  end

  describe "build_action/3" do
    test "valid params and authorized actor returns {:ok, %LampAction{}}" do
      org = create_org!()
      actor = create_user_in_org!(org, :admin)
      register_global_lamp!()

      assert {:ok, %LampAction{} = action} =
               Conductor.build_action(
                 "aws.s3.create-bucket",
                 "create_bucket",
                 %{"bucket_name" => "test-bucket"},
                 actor: actor
               )

      assert action.lamp_id == "aws.s3.create-bucket"
      assert action.endpoint_id == "create_bucket"
      assert action.actor_id == actor.id
    end

    test "member actor on non-destructive lamp is authorized" do
      org = create_org!()
      actor = create_user_in_org!(org, :member)
      register_global_lamp!()

      assert {:ok, %LampAction{}} =
               Conductor.build_action(
                 "aws.s3.create-bucket",
                 "create_bucket",
                 %{},
                 actor: actor
               )
    end

    test "unauthorized actor (wrong org) returns {:error, %Ash.Error.Forbidden{}}" do
      org_a = create_org!()
      org_b = create_org!()
      actor = create_user_in_org!(org_a)
      register_org_lamp!(org_b.id)

      assert {:error, %Ash.Error.Forbidden{}} =
               Conductor.build_action(
                 "aws.s3.create-bucket",
                 "create_bucket",
                 %{},
                 actor: actor
               )
    end

    test "missing required param lamp_id returns {:error, %Ash.Error.Invalid{}}" do
      org = create_org!()
      actor = create_user_in_org!(org)

      assert {:error, %Ash.Error.Invalid{}} =
               Conductor.build_action(nil, "create_bucket", %{}, actor: actor)
    end

    test "missing required param endpoint_id returns {:error, %Ash.Error.Invalid{}}" do
      org = create_org!()
      actor = create_user_in_org!(org)
      register_global_lamp!()

      assert {:error, %Ash.Error.Invalid{}} =
               Conductor.build_action("aws.s3.create-bucket", nil, %{}, actor: actor)
    end
  end

  describe "execute/1" do
    test "calls Bridge with the correct endpoint and returns HTML" do
      org = create_org!()
      actor = create_user_in_org!(org, :admin)
      register_global_lamp!()

      {:ok, lamp_action} =
        Conductor.build_action(
          "aws.s3.create-bucket",
          "create_bucket",
          %{"bucket_name" => "acme-test"},
          actor: actor
        )

      Req.Test.stub(Genie.Bridge, fn conn ->
        Req.Test.json(conn, %{"state" => "ready", "bucket_name" => "acme-test"})
      end)

      assert {:ok, html} = Conductor.execute(lamp_action)
      assert is_binary(html)
    end
  end
end
