defmodule Genie.Accounts.Checks.ActorOrg do
  @moduledoc false
  use Ash.Policy.FilterCheck

  @impl true
  def describe(_opts), do: "actor belongs to this organisation"

  @impl true
  def filter(nil, _, _), do: false
  def filter(actor, _, _), do: [id: actor.org_id]
end

defmodule Genie.Accounts.Checks.SameOrg do
  @moduledoc false
  use Ash.Policy.FilterCheck

  @impl true
  def describe(_opts), do: "resource belongs to the same organisation as the actor"

  @impl true
  def filter(nil, _, _), do: false
  def filter(actor, _, _), do: [org_id: actor.org_id]
end

defmodule Genie.Accounts.Checks.IsSelf do
  @moduledoc false
  use Ash.Policy.FilterCheck

  @impl true
  def describe(_opts), do: "resource is the actor themselves"

  @impl true
  def filter(nil, _, _), do: false
  def filter(actor, _, _), do: [id: actor.id]
end
