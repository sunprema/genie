defmodule Genie.Orchestrator.Steps.ValidateInputStep do
  @moduledoc """
  Step 1: Loads the session, validates the actor, and fetches enabled lamp manifests.
  Compensate broadcasts an auth error to the Cockpit so the UI doesn't hang.
  """
  use Reactor.Step

  alias GenieWeb.CockpitLive
  alias Genie.Lamp.LampRegistry

  @impl Reactor.Step
  def run(%{session_id: session_id, actor: actor}, _context, _options) do
    org_id = actor && actor.org_id

    with {:ok, session} <- load_session(session_id, actor),
         {:ok, manifests} <- LampRegistry.load_active_manifests(org_id) do
      {:ok, %{session: session, manifests: manifests, actor: actor}}
    end
  end

  @impl Reactor.Step
  def compensate(reason, %{session_id: session_id}, _context, _options) do
    CockpitLive.push_error(to_string(session_id), reason)
    :ok
  end

  def compensate(_reason, _arguments, _context, _options), do: :ok

  defp load_session(session_id, actor) do
    case Ash.get(Genie.Conversation.Session, session_id, actor: actor, authorize?: false) do
      {:ok, session} -> {:ok, session}
      {:error, _} = error -> error
    end
  end
end
