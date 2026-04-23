defmodule Genie.Orchestrator.Steps.LlmCallStep do
  @moduledoc """
  Step 3: Calls the LLM with assembled context and tools.
  Compensates with exponential backoff on transient failures (up to 3 retries).
  """
  use Reactor.Step

  alias Genie.Orchestrator.LlmClient

  @impl Reactor.Step
  def run(%{build_context: build_context}, _context, _options) do
    LlmClient.call(build_context)
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
