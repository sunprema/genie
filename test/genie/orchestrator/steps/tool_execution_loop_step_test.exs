defmodule Genie.Orchestrator.Steps.ToolExecutionLoopStepTest do
  use Genie.DataCase, async: false

  alias Genie.MockReqLLM
  alias Genie.Orchestrator.Steps.ToolExecutionLoopStep
  alias ReqLLM.Context

  setup do
    Application.put_env(:genie, :req_llm_module, MockReqLLM)
    on_exit(fn -> Application.delete_env(:genie, :req_llm_module) end)
    :ok
  end

  defp build_context(tool_registry \\ %{}) do
    %{
      llm_context: Context.new([]),
      tools: [],
      tool_registry: tool_registry
    }
  end

  describe "run/3 — pass-through" do
    test "passes :message responses through without modification" do
      response = {:message, %{text: "Hello", llm_context: nil}}

      assert {:ok, ^response} =
               ToolExecutionLoopStep.run(
                 %{llm_response: response, build_context: build_context()},
                 %{},
                 []
               )
    end

    test "passes :intent_call responses through without modification" do
      response = {:intent_call, %{lamp_id: "test", endpoint_id: "ep", params: %{}, llm_context: nil}}

      assert {:ok, ^response} =
               ToolExecutionLoopStep.run(
                 %{llm_response: response, build_context: build_context()},
                 %{},
                 []
               )
    end
  end

  describe "run/3 — tool execution loop" do
    test "returns error after 6 iterations with empty tool calls" do
      # LLM keeps returning tool_calls with empty calls list.
      # This causes the loop to iterate without executing any tools.
      data = %{calls: [], llm_context: Context.new([])}

      # Each LLM call returns another empty tool_call response
      Process.put(
        :mock_llm_response,
        {:ok, build_empty_tool_call_response()}
      )

      assert {:error, :max_iterations_exceeded} =
               ToolExecutionLoopStep.run(
                 %{llm_response: {:tool_call, data}, build_context: build_context()},
                 %{},
                 []
               )
    end

    test "exits loop and returns message when LLM responds with a message" do
      # Empty calls means tool execution is a no-op.
      # LLM immediately returns a message on the re-prompt.
      data = %{calls: [], llm_context: Context.new([])}

      Process.put(:mock_llm_response, {:ok, MockReqLLM.build_message_response("Done")})

      assert {:ok, {:message, %{text: "Done"}}} =
               ToolExecutionLoopStep.run(
                 %{llm_response: {:tool_call, data}, build_context: build_context()},
                 %{},
                 []
               )
    end
  end

  defp build_empty_tool_call_response do
    message = %ReqLLM.Message{
      role: :assistant,
      content: [],
      tool_calls: []
    }

    %ReqLLM.Response{
      id: "msg_test",
      model: "test-model",
      context: ReqLLM.Context.new([message]),
      message: message,
      finish_reason: :tool_calls
    }
  end

  describe "run/3 — tool execution with known tool" do
    setup do
      ec2_xml = File.read!(Path.join(:code.priv_dir(:genie), "lamps/aws_ec2_list_instances.xml"))

      Genie.Lamp.LampRegistry
      |> Ash.Changeset.for_create(:register, %{org_id: nil, xml_source: ec2_xml, enabled: true})
      |> Ash.create!(authorize?: false)

      :ok
    end

    test "executes tool call and continues loop when LLM returns message" do
      tool_registry = %{"aws_ec2_list_regions" => {"aws.ec2.list-instances", "load_regions"}}

      Req.Test.stub(Genie.Bridge, fn conn ->
        Req.Test.json(conn, [
          %{"code" => "us-east-1", "name" => "US East (N. Virginia)"}
        ])
      end)

      Process.put(:mock_llm_response, {:ok, MockReqLLM.build_message_response("Done")})

      tool_call = ReqLLM.ToolCall.new("call_001", "aws_ec2_list_regions", "{}")

      data = %{calls: [tool_call], llm_context: Context.new([])}

      assert {:ok, {:message, %{text: "Done"}}} =
               ToolExecutionLoopStep.run(
                 %{llm_response: {:tool_call, data}, build_context: build_context(tool_registry)},
                 %{},
                 []
               )
    end

    test "returns error for unknown tool" do
      tool_call = ReqLLM.ToolCall.new("call_002", "unknown_tool", "{}")

      data = %{calls: [tool_call], llm_context: Context.new([])}

      assert {:error, {:unknown_tool, "unknown_tool"}} =
               ToolExecutionLoopStep.run(
                 %{llm_response: {:tool_call, data}, build_context: build_context(%{})},
                 %{},
                 []
               )
    end
  end

  describe "compensate/4" do
    test "always returns :ok" do
      assert :ok = ToolExecutionLoopStep.compensate({:error, :test}, %{}, %{}, [])
    end
  end
end
