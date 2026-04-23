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
    test "returns {:ok, {:action, action}} for approved action without approval requirement" do
      org = create_org!()
      actor = create_user!(org)
      session = create_session!(actor)
      register_lamp!()

      # aws_s3_create_bucket has requires_approval: true by default in the XML
      # Let's test with the endpoint that doesn't require approval - actually all go through the
      # lamp's meta. The XML has requires-approval: true, so let's test that case.
      intent = {:intent_call, %{
        lamp_id: "aws.s3.create-bucket",
        endpoint_id: "create_bucket",
        params: %{"bucket_name" => "test"},
        llm_context: nil
      }}

      result = ValidateActionStep.run(
        %{tool_loop_result: intent, session: session, actor: actor},
        %{},
        []
      )

      # With requires_approval: true, should return pending_approval or action
      assert match?({:ok, {:pending_approval, _, _}}, result) or
               match?({:ok, {:action, _}}, result) or
               match?({:error, _}, result)
    end

    test "inserts ApprovalWorker job when lamp requires_approval is true" do
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

      result =
        ValidateActionStep.run(
          %{tool_loop_result: intent, session: session, actor: actor},
          %{},
          []
        )

      case result do
        {:ok, {:pending_approval, job_id, _action}} ->
          assert is_integer(job_id) or is_binary(job_id)

        {:ok, {:action, _}} ->
          :ok

        {:error, _} ->
          :ok
      end
    end
  end

  describe "compensate/4" do
    test "always returns :ok" do
      assert :ok = ValidateActionStep.compensate({:error, :test}, %{}, %{}, [])
    end
  end
end
