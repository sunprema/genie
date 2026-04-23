defmodule Genie.Workers.OrchestratorWorker do
  @moduledoc false
  use Oban.Worker, queue: :orchestrator

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Genie.Accounts.User
  alias Genie.Orchestrator.ReasoningLoop
  alias GenieWeb.CockpitLive

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"session_id" => session_id, "user_message" => user_message, "actor_id" => actor_id}
      }) do
    actor = load_actor(actor_id)

    Tracer.with_span "Genie.reactor.start", %{
      attributes: [{"session_id", to_string(session_id)}, {"actor_id", to_string(actor_id)}]
    } do
      case Reactor.run(ReasoningLoop, %{
             session_id: session_id,
             user_message: user_message,
             actor: actor
           }) do
        {:ok, _result} ->
          :ok

        {:error, reason} ->
          Logger.error("ReasoningLoop failed for session=#{session_id}: #{inspect(reason)}")
          CockpitLive.push_error(session_id, reason)
          :ok
      end
    end
  end

  defp load_actor(nil), do: nil

  defp load_actor(actor_id) do
    case Ash.get(User, actor_id, authorize?: false) do
      {:ok, user} -> user
      _ -> nil
    end
  end
end
