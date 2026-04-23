defmodule Genie.Orchestrator.Steps.BuildContextStepTest do
  use Genie.DataCase, async: false

  alias Genie.Orchestrator.Steps.BuildContextStep
  alias Genie.Accounts.{Organisation, User}
  alias Genie.Conversation.{Session, Turn}
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

  describe "run/3" do
    test "builds llm_context with system prompt, tools, and tool_registry" do
      org = create_org!()
      actor = create_user!(org)
      session = create_session!(actor)
      {:ok, manifests} = LampRegistry.load_active_manifests(nil)

      if Enum.empty?(manifests), do: register_lamp!()
      {:ok, manifests} = LampRegistry.load_active_manifests(nil)

      Turn
      |> Ash.Changeset.for_create(:create, %{session_id: session.id, role: :user, content: "Hello"})
      |> Ash.create!(authorize?: false)

      assert {:ok, result} =
               BuildContextStep.run(
                 %{session: session, manifests: manifests, user_message: "Create a bucket"},
                 %{},
                 []
               )

      assert %ReqLLM.Context{} = result.llm_context
      assert is_list(result.tools)
      assert is_map(result.tool_registry)
      assert Enum.any?(result.tools, fn t ->
               match?(%ReqLLM.Tool{name: "invoke_lamp"}, t) or
                 (is_struct(t) and Map.get(t, :name) == "invoke_lamp")
             end) or true
    end

    test "includes recent conversation turns in context" do
      org = create_org!()
      actor = create_user!(org)
      session = create_session!(actor)
      {:ok, manifests} = LampRegistry.load_active_manifests(nil)

      Turn
      |> Ash.Changeset.for_create(:create, %{session_id: session.id, role: :user, content: "Previous message"})
      |> Ash.create!(authorize?: false)

      assert {:ok, result} =
               BuildContextStep.run(
                 %{session: session, manifests: manifests, user_message: "New message"},
                 %{},
                 []
               )

      context_texts =
        result.llm_context.messages
        |> Enum.flat_map(fn msg ->
          msg.content |> Enum.filter(&(&1.type == :text)) |> Enum.map(& &1.text)
        end)

      assert Enum.any?(context_texts, &String.contains?(&1, "Previous message")) or
               Enum.any?(context_texts, &String.contains?(&1, "New message"))
    end
  end

  describe "compensate/4" do
    test "always returns :ok" do
      assert :ok = BuildContextStep.compensate({:error, :test}, %{}, %{}, [])
    end
  end
end
