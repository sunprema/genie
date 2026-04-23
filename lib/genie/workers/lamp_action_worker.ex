defmodule Genie.Workers.LampActionWorker do
  use Oban.Worker, queue: :lamp_actions

  alias Genie.Accounts.User
  alias Genie.Conductor
  alias GenieWeb.CockpitLive

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "lamp_id" => lamp_id,
          "endpoint_id" => endpoint_id,
          "params" => params,
          "actor_id" => actor_id,
          "session_id" => session_id
        }
      }) do
    actor = load_actor(actor_id)

    result =
      with {:ok, lamp_action} <-
             Conductor.build_action(lamp_id, endpoint_id, params || %{},
               actor: actor,
               session_id: session_id
             ),
           {:ok, html} <- Conductor.execute(lamp_action) do
        {:ok, html}
      end

    case result do
      {:ok, html} ->
        CockpitLive.push_canvas(session_id, html)
        :ok

      {:error, reason} ->
        CockpitLive.push_error(session_id, reason)
        :ok
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
