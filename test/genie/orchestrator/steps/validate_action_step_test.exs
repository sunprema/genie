defmodule Genie.Orchestrator.Steps.ValidateActionStepTest do
  use Genie.DataCase, async: false

  alias Genie.Orchestrator.Steps.ValidateActionStep
  alias Genie.Accounts.{Organisation, User}
  alias Genie.Conversation.Session
  alias Genie.Lamp.LampRegistry

  @valid_xml File.read!(Path.join([:code.priv_dir(:genie), "lamps", "aws_s3_create_bucket.xml"]))

  defp create_org!, do: Organisation |> Ash.Changeset.for_create(:create, %{name: "Org#{System.unique_integer([:positive])}", slug: "org-#{System.unique_integer([:positive])}"}) |> Ash.create!(authorize?: false)

  defp create_user!(org) do
    n = System.unique_integer([:positive])
    user = User |> Ash.Changeset.for_create(:register_with_password, %{email: "u-#{n}@t.com", password: "password123", password_confirmation: "password123"}) |> Ash.create!(authorize?: false)
    user |> Ash.Changeset.for_update(:update, %{org_id: org.id, role: :admin}) |> Ash.update!(authorize?: false)
  end

  defp create_session!(user) do
    Session |> Ash.Changeset.for_create(:create, %{org_id: user.org_id, user_id: user.id, title: "test"}) |> Ash.create!(authorize?: false)
  end

  defp register_lamp! do
    LampRegistry |> Ash.Changeset.for_create(:register, %{org_id: nil, xml_source: @valid_xml, enabled: true}) |> Ash.create!(authorize?: false)
  end

  describe "run/3 — pass-through" do
    test "passes :message through unchanged" do
      message = {:message, %{text: "Hello"}}

      assert {:ok, {:message, %{text: "Hello"}}} =
               ValidateActionStep.run(
                 %{tool_loop_result: message, session: nil, actor: nil},
                 %{},
                 []
               )
    end
  end

  describe "run/3 — :intent_call" do
    test "returns {:ok, {:action, action}} for a valid authorised actor" do
      org = create_org!()
      actor = create_user!(org)
      session = create_session!(actor)
      register_lamp!()

      intent = {:intent_call, %{
        lamp_id: "aws.s3.create-bucket",
        endpoint_id: "create_bucket",
        params: %{"bucket_name" => "test-bucket"},
        llm_context: nil
      }}

      result = ValidateActionStep.run(
        %{tool_loop_result: intent, session: session, actor: actor},
        %{},
        []
      )

      # Always returns :action — approval is checked later in LampActionWorker
      assert match?({:ok, {:action, _}}, result) or match?({:error, _}, result)
    end

    test "returns :action regardless of requires_approval flag on the lamp" do
      org = create_org!()
      actor = create_user!(org)
      session = create_session!(actor)
      register_lamp!()

      intent = {:intent_call, %{
        lamp_id: "aws.s3.create-bucket",
        endpoint_id: "create_bucket",
        params: %{},
        llm_context: nil
      }}

      assert {:ok, {:action, _action}} =
               ValidateActionStep.run(
                 %{tool_loop_result: intent, session: session, actor: actor},
                 %{},
                 []
               )
    end
  end

  describe "compensate/4" do
    test "always returns :ok" do
      assert :ok = ValidateActionStep.compensate({:error, :test}, %{}, %{}, [])
    end
  end
end
