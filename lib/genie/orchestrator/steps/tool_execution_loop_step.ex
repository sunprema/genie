defmodule Genie.Orchestrator.Steps.ToolExecutionLoopStep do
  @moduledoc """
  Step 4: Executes any tool calls the LLM requested, re-prompts, and loops until
  the LLM returns an :intent_call or :message. Guards at 6 iterations.
  """
  use Reactor.Step

  require OpenTelemetry.Tracer, as: Tracer

  alias Genie.Bridge
  alias Genie.Lamp.LampRegistry
  alias Genie.Orchestrator.LlmClient
  alias ReqLLM.Context

  @max_iterations 6

  @impl Reactor.Step
  def run(%{llm_response: {:tool_call, data}, build_context: build_context}, _context, _options) do
    run_loop(data, build_context, 0)
  end

  def run(%{llm_response: response}, _context, _options) do
    {:ok, response}
  end

  @impl Reactor.Step
  def compensate(_reason, _arguments, _context, _options), do: :ok

  defp run_loop(_data, _build_context, iterations) when iterations >= @max_iterations do
    {:error, :max_iterations_exceeded}
  end

  defp run_loop(%{calls: calls, llm_context: llm_context}, build_context, iterations) do
    tool_registry = build_context.tool_registry

    case execute_tool_calls(calls, tool_registry, llm_context, iterations) do
      {:ok, updated_context} ->
        updated_build_context = %{build_context | llm_context: updated_context}

        case LlmClient.call(updated_build_context) do
          {:ok, {:tool_call, new_data}} ->
            run_loop(new_data, updated_build_context, iterations + 1)

          {:ok, other} ->
            {:ok, other}

          {:error, _} = error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  defp execute_tool_calls(calls, tool_registry, llm_context, iteration) do
    Enum.reduce_while(calls, {:ok, llm_context}, fn call, {:ok, ctx} ->
      tool_name = Map.get(call, :name) || Map.get(call, "name") || "unknown"

      Tracer.with_span "Genie.tool.execute", %{
        attributes: [{"tool_name", to_string(tool_name)}, {"iteration", iteration}]
      } do
        case execute_single_tool(call, tool_registry, ctx) do
          {:ok, updated_ctx} -> {:cont, {:ok, updated_ctx}}
          {:error, _} = error -> {:halt, error}
        end
      end
    end)
  end

  defp execute_single_tool(call, tool_registry, llm_context) do
    tool_name = Map.get(call, :name) || Map.get(call, "name")

    case Map.fetch(tool_registry, tool_name) do
      {:ok, {lamp_id, endpoint_id}} ->
        params = Map.get(call, :arguments) || Map.get(call, "arguments") || %{}
        execute_lamp_tool(lamp_id, endpoint_id, params, llm_context)

      :error ->
        {:error, {:unknown_tool, tool_name}}
    end
  end

  defp execute_lamp_tool(lamp_id, endpoint_id, params, llm_context) do
    with {:ok, lamp} <- LampRegistry.fetch_lamp(lamp_id),
         {:ok, result} <-
           Bridge.execute_tool(%{
             lamp: lamp,
             endpoint_id: endpoint_id,
             params: params,
             session_id: ""
           }) do
      tool_result_json = Jason.encode!(result)
      tool_call_id = "tool_#{System.unique_integer([:positive])}"
      tool_msg = Context.tool_result(tool_call_id, tool_result_json)
      updated = Context.append(llm_context, tool_msg)
      {:ok, updated}
    end
  end
end
