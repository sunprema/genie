defmodule Genie.Orchestrator.Steps.ValidateInputStepTest do
  use Genie.DataCase, async: false

  alias Genie.Orchestrator.Steps.ValidateInputStep
  alias Genie.Accounts.{Organisation, User}
  alias Genie.Conversation.Session
  alias Genie.Lamp.LampRegistry

  @valid_xml File.read!(Path.join([:code.priv_dir(:genie), "lamps", "aws_s3_create_bucket.xml"]))

  defp create_org! do
    n = System.unique_integer([:positive])

    Organisation
    |> Ash.Changeset.for_create(:create, %{name: "Org #{n}", slug: "org-#{n}"})
    |> Ash.create!(authorize?: false)
  end

  defp create_user!(org) do
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

  defp create_session!(user) do
    Session
    |> Ash.Changeset.for_create(:create, %{
      org_id: user.org_id,
      user_id: user.id,
      title: "Test session"
    })
    |> Ash.create!(authorize?: false)
  end

  describe "run/3" do
    test "returns session, manifests, and actor on success" do
      org = create_org!()
      actor = create_user!(org)
      session = create_session!(actor)

      LampRegistry
      |> Ash.Changeset.for_create(:register, %{org_id: nil, xml_source: @valid_xml, enabled: true})
      |> Ash.create!(authorize?: false)

      assert {:ok, %{session: returned_session, manifests: manifests, actor: returned_actor}} =
               ValidateInputStep.run(
                 %{session_id: session.id, actor: actor},
                 %{},
                 []
               )

      assert returned_session.id == session.id
      assert returned_actor.id == actor.id
      assert length(manifests) >= 1
    end

    test "returns error for non-existent session" do
      org = create_org!()
      actor = create_user!(org)
      fake_session_id = Ecto.UUID.generate()

      assert {:error, _} =
               ValidateInputStep.run(
                 %{session_id: fake_session_id, actor: actor},
                 %{},
                 []
               )
    end
  end

  describe "compensate/4" do
    test "returns :ok even when push_error fails" do
      assert :ok = ValidateInputStep.compensate({:error, :forbidden}, %{session_id: "bad-id"}, %{}, [])
    end
  end
end
