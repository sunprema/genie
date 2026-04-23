defmodule Genie.Orchestrator.Steps.ValidateActionStep do
  @moduledoc """
  Step 5: Validates the lamp action through Ash policy checks (RBAC).
  Inserts an ApprovalWorker job when the lamp requires approval.
  Passes :message responses through unchanged.
  """
  use Reactor.Step

  alias Genie.Conductor
  alias Genie.Lamp.LampRegistry
  alias Genie.Workers.ApprovalWorker

  @impl Reactor.Step
  def run(%{tool_loop_result: {:intent_call, intent_data}, session: session, actor: actor}, _context, _options) do
    lamp_id = intent_data[:lamp_id] || intent_data["lamp_id"]
    endpoint_id = intent_data[:endpoint_id] || intent_data["endpoint_id"]
    params = intent_data[:params] || intent_data["params"] || %{}

    with {:ok, action} <-
           Conductor.build_action(lamp_id, endpoint_id, params,
             actor: actor,
             session_id: session.id
           ),
         {:ok, lamp} <- LampRegistry.fetch_lamp(lamp_id) do
      if lamp.meta && lamp.meta.requires_approval do
        case insert_approval_job(action) do
          {:ok, %{id: job_id}} ->
            {:ok, {:pending_approval, job_id, action}}

          {:error, _} = error ->
            error
        end
      else
        {:ok, {:action, action}}
      end
    end
  end

  def run(%{tool_loop_result: {:message, _} = msg}, _context, _options) do
    {:ok, msg}
  end

  @impl Reactor.Step
  def compensate(_reason, _arguments, _context, _options), do: :ok

  defp insert_approval_job(action) do
    %{
      "action_id" => to_string(action.id),
      "approver_id" => nil,
      "decision" => "pending"
    }
    |> ApprovalWorker.new()
    |> Oban.insert()
  end
end
