defmodule Genie.Workers.ApprovalWorker do
  use Oban.Worker, queue: :approvals

  alias Genie.Audit.AuditLog
  alias Genie.Conductor.LampAction
  alias GenieWeb.CockpitLive

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "action_id" => action_id,
          "approver_id" => approver_id,
          "decision" => decision
        }
      }) do
    case decision do
      "approve" -> handle_approval(action_id)
      "deny" -> handle_denial(action_id, approver_id)
    end
  end

  defp handle_approval(action_id) do
    %{
      "session_id" => nil,
      "user_message" => "",
      "actor_id" => nil,
      "action_id" => action_id,
      "approved" => true
    }
    |> Genie.Workers.OrchestratorWorker.new()
    |> Oban.insert()

    :ok
  end

  defp handle_denial(action_id, _approver_id) do
    with {:ok, action} <- Ash.get(LampAction, action_id, authorize?: false) do
      AuditLog
      |> Ash.Changeset.for_create(:create, %{
        session_id: action.session_id,
        lamp_id: action.lamp_id,
        actor_id: action.actor_id,
        result: :denied
      })
      |> Ash.create(authorize?: false)

      if action.session_id do
        CockpitLive.push_error(to_string(action.session_id), :denied)
      end
    end

    :ok
  end
end
