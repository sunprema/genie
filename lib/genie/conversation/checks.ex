defmodule Genie.Conversation.Checks.TurnSameOrg do
  @moduledoc false
  use Ash.Policy.FilterCheck

  @impl true
  def describe(_opts), do: "turn belongs to a session in the actor's organisation"

  @impl true
  def filter(nil, _, _), do: false

  def filter(actor, _, _) do
    actor_org_id = actor.org_id
    expr(session.org_id == ^actor_org_id)
  end
end
