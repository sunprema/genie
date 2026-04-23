defmodule Genie.Orchestrator.Steps.FillUiStepTest do
  use Genie.DataCase, async: false

  alias Genie.Orchestrator.Steps.FillUiStep
  alias Genie.Lamp.{FieldDef, LampRegistry, LampDefinition}
  alias Genie.MockReqLLM
  alias ReqLLM.Context

  @valid_xml File.read!(Path.join([:code.priv_dir(:genie), "lamps", "aws_s3_create_bucket.xml"]))

  setup do
    Application.put_env(:genie, :req_llm_module, MockReqLLM)
    on_exit(fn -> Application.delete_env(:genie, :req_llm_module) end)
    :ok
  end

  defp register_lamp! do
    LampRegistry
    |> Ash.Changeset.for_create(:register, %{org_id: nil, xml_source: @valid_xml, enabled: true})
    |> Ash.create!(authorize?: false)
  end

  defp minimal_lamp do
    %LampDefinition{
      id: "test.lamp.action",
      version: "1.0",
      category: "test",
      vendor: "test",
      meta: %Genie.Lamp.MetaDef{
        title: "Test Lamp",
        requires_approval: false
      },
      fields: [
        %FieldDef{
          id: "context_field",
          type: :text,
          aria_label: "Context field",
          genie_fill: :from_context,
          value: nil
        },
        %FieldDef{
          id: "infer_field",
          type: :text,
          aria_label: "Infer field",
          genie_fill: :infer,
          value: nil
        },
        %FieldDef{
          id: "none_field",
          type: :text,
          aria_label: "None field",
          genie_fill: :none,
          value: nil
        }
      ],
      endpoints: [],
      groups: [],
      actions: [],
      status_templates: []
    }
  end

  defp mock_action(lamp_id \\ "test.lamp.action") do
    %Genie.Conductor.LampAction{
      id: Ecto.UUID.generate(),
      lamp_id: lamp_id,
      endpoint_id: "test_endpoint",
      params: %{"context_field" => "from-context-value"},
      session_id: Ecto.UUID.generate()
    }
  end

  defp build_context do
    %{
      llm_context: Context.new([
        ReqLLM.Context.user("Create with context-value")
      ]),
      tools: [],
      tool_registry: %{}
    }
  end

  describe "run/3 — :action" do
    test "fills :from_context fields from params without LLM call" do
      Process.put(:mock_llm_object, {:ok, MockReqLLM.build_object_response(%{"infer_field" => "inferred"})})

      lamp = minimal_lamp()
      action = mock_action()

      assert {:ok, %{html: html, type: :canvas}} =
               FillUiStep.run(
                 %{
                   validated_action: {:action, action},
                   manifests: [lamp],
                   build_context: build_context()
                 },
                 %{},
                 []
               )

      assert is_binary(html)
      # from_context field should be filled, not from LLM
      assert String.contains?(html, "from-context-value")
    end

    test "calls LLM only for :infer fields, not :from_context fields" do
      Process.put(:mock_llm_object, {:ok, MockReqLLM.build_object_response(%{"infer_field" => "inferred-value"})})

      lamp = minimal_lamp()
      action = mock_action()

      assert {:ok, %{html: html}} =
               FillUiStep.run(
                 %{
                   validated_action: {:action, action},
                   manifests: [lamp],
                   build_context: build_context()
                 },
                 %{},
                 []
               )

      assert is_binary(html)
    end

  end

  describe "run/3 — :message" do
    test "passes message through as chat type" do
      assert {:ok, %{type: :chat, message: "Hello from agent", html: nil}} =
               FillUiStep.run(
                 %{
                   validated_action: {:message, %{text: "Hello from agent"}},
                   manifests: [],
                   build_context: build_context()
                 },
                 %{},
                 []
               )
    end
  end

  describe "compensate/4" do
    test "returns :ok for non-action cases" do
      assert :ok =
               FillUiStep.compensate(
                 {:error, :llm_timeout},
                 %{validated_action: {:message, %{text: "hi"}}, manifests: [], build_context: %{}},
                 %{},
                 []
               )
    end
  end
end
