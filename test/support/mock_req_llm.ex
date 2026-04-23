defmodule Genie.MockReqLLM do
  @moduledoc """
  Mock for ReqLLM used in orchestrator tests.
  Configure responses via the process dictionary before calling.

  Usage:
    Process.put(:mock_llm_response, {:ok, build_tool_call_response()})
    Process.put(:mock_llm_object, {:ok, %{object: %{"field_id" => "value"}}})
  """

  def generate_text(_model, _context, _opts \\ []) do
    Process.get(:mock_llm_response) ||
      Application.get_env(:genie, :mock_llm_response, {:ok, build_message_response("Hello")})
  end

  def generate_object(_model, _prompt, _schema, _opts \\ []) do
    Process.get(:mock_llm_object) ||
      Application.get_env(:genie, :mock_llm_object, {:ok, build_object_response(%{})})
  end

  def build_message_response(text) do
    message = %ReqLLM.Message{
      role: :assistant,
      content: [%ReqLLM.Message.ContentPart{type: :text, text: text}]
    }

    %ReqLLM.Response{
      id: "msg_test",
      model: "test-model",
      context: ReqLLM.Context.new([message]),
      message: message,
      finish_reason: :stop
    }
  end

  def build_tool_call_response(tool_name, arguments \\ %{}) do
    tool_call = ReqLLM.ToolCall.new(
      "call_test_#{System.unique_integer([:positive])}",
      tool_name,
      Jason.encode!(arguments)
    )

    message = %ReqLLM.Message{
      role: :assistant,
      content: [],
      tool_calls: [tool_call]
    }

    %ReqLLM.Response{
      id: "msg_test",
      model: "test-model",
      context: ReqLLM.Context.new([message]),
      message: message,
      finish_reason: :tool_calls
    }
  end

  def build_invoke_lamp_response(lamp_id, endpoint_id, params \\ %{}) do
    build_tool_call_response("invoke_lamp", %{
      "lamp_id" => lamp_id,
      "endpoint_id" => endpoint_id,
      "params" => params
    })
  end

  def build_object_response(fields) do
    %ReqLLM.Response{
      id: "msg_test",
      model: "test-model",
      context: ReqLLM.Context.new([]),
      message: nil,
      object: fields,
      finish_reason: :stop
    }
  end
end
