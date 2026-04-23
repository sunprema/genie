defmodule Genie.Workers.OrchestratorWorker do
  use Oban.Worker, queue: :orchestrator

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"session_id" => session_id, "user_message" => user_message, "actor_id" => actor_id}
      }) do
    Logger.info(
      "OrchestratorWorker received session_id=#{session_id} actor_id=#{actor_id} message=#{user_message}"
    )

    :ok
  end
end
