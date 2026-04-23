defmodule Genie.Orchestrator.Steps.ValidateActionStep do
  @moduledoc """
  Step 5: Validates the lamp action through Ash policy checks (RBAC).
  Inserts an ApprovalWorker job when the lamp requires approval.
  Passes :message responses through unchanged.
  """
  use Reactor.Step

  alias Genie.Conductor

  @impl Reactor.Step
  def run(%{tool_loop_result: {:intent_call, intent_data}, session: session, actor: actor}, _context, _options) do
    lamp_id = intent_data[:lamp_id] || intent_data["lamp_id"]
    endpoint_id = intent_data[:endpoint_id] || intent_data["endpoint_id"]
    params = intent_data[:params] || intent_data["params"] || %{}

    with {:ok, action} <-
           Conductor.build_action(lamp_id, endpoint_id, params,
             actor: actor,
             session_id: session.id
           ) do
      {:ok, {:action, action}}
    end
  end

  def run(%{tool_loop_result: {:message, _} = msg}, _context, _options) do
    {:ok, msg}
  end

  @impl Reactor.Step
  def compensate(_reason, _arguments, _context, _options), do: :ok
end
