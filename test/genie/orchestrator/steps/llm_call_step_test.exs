defmodule Genie.Orchestrator.Steps.LlmCallStepTest do
  use ExUnit.Case, async: false

  alias Genie.MockReqLLM
  alias Genie.Orchestrator.Steps.LlmCallStep
  alias ReqLLM.Context

  setup do
    Application.put_env(:genie, :req_llm_module, MockReqLLM)
    on_exit(fn -> Application.delete_env(:genie, :req_llm_module) end)
    :ok
  end

  defp build_context do
    %{
      llm_context: Context.new([]),
      tools: [],
      tool_registry: %{}
    }
  end

  describe "run/3" do
    test "returns {:ok, {:message, data}} for message responses" do
      Process.put(:mock_llm_response, {:ok, MockReqLLM.build_message_response("Test response")})

      assert {:ok, {:message, %{text: "Test response"}}} =
               LlmCallStep.run(%{build_context: build_context()}, %{}, [])
    end

    test "returns {:ok, {:tool_call, data}} for tool call responses" do
      response = MockReqLLM.build_tool_call_response("data_tool", %{})
      Process.put(:mock_llm_response, {:ok, response})

      assert {:ok, {:tool_call, %{calls: _}}} =
               LlmCallStep.run(%{build_context: build_context()}, %{}, [])
    end

    test "returns {:ok, {:intent_call, data}} for invoke_lamp calls" do
      response = MockReqLLM.build_invoke_lamp_response("aws.s3.create-bucket", "create_bucket")
      Process.put(:mock_llm_response, {:ok, response})

      assert {:ok, {:intent_call, %{lamp_id: "aws.s3.create-bucket", endpoint_id: "create_bucket"}}} =
               LlmCallStep.run(%{build_context: build_context()}, %{}, [])
    end

    test "propagates errors from LLM client" do
      Process.put(:mock_llm_response, {:error, :service_unavailable})

      assert {:error, :service_unavailable} =
               LlmCallStep.run(%{build_context: build_context()}, %{}, [])
    end
  end

  describe "compensate/4" do
    test "retries on transient errors up to 3 times" do
      assert :retry = LlmCallStep.compensate({:error, :timeout}, %{}, %{}, retry_count: 0)
      assert :retry = LlmCallStep.compensate({:error, :timeout}, %{}, %{}, retry_count: 2)
    end

    test "stops retrying after 3 attempts" do
      assert :ok = LlmCallStep.compensate({:error, :timeout}, %{}, %{}, retry_count: 3)
    end
  end
end
