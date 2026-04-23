defmodule Genie.Orchestrator.Steps.LlmCallStep do
  @moduledoc """
  Step 3: Calls the LLM with assembled context and tools.
  Compensates with exponential backoff on transient failures (up to 3 retries).
  """
  use Reactor.Step

  require OpenTelemetry.Tracer, as: Tracer

  alias Genie.Orchestrator.LlmClient

  @impl Reactor.Step
  def run(%{build_context: build_context}, _context, _options) do
    Tracer.with_span "Genie.llm.call" do
      case LlmClient.call(build_context) do
        {:ok, {_type, data} = result} ->
          usage = Map.get(data, :usage, %{})

          Tracer.set_attributes([
            {"token_count_input", usage[:input_tokens] || 0},
            {"token_count_output", usage[:output_tokens] || 0}
          ])

          {:ok, result}

        {:error, _} = error ->
          error
      end
    end
  end

  @impl Reactor.Step
  def compensate({:error, _reason}, _arguments, _context, options) do
    retry_count = Keyword.get(options, :retry_count, 0)

    if retry_count < 3 do
      backoff_ms = :math.pow(2, retry_count) |> round() |> Kernel.*(500)
      Process.sleep(backoff_ms)
      :retry
    else
      :ok
    end
  end

  def compensate(_reason, _arguments, _context, _options), do: :ok
end
