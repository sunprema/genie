defmodule Genie.Conductor.Checks.LampOrgAccess do
  @moduledoc false
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor belongs to an org with access to this lamp"

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(actor, %{changeset: changeset}, _opts) do
    lamp_id = Ash.Changeset.get_attribute(changeset, :lamp_id)

    case Genie.Lamp.LampRegistry.by_lamp_id(lamp_id, authorize?: false) do
      {:ok, record} ->
        record.enabled &&
          (is_nil(record.org_id) || record.org_id == actor.org_id)

      _ ->
        false
    end
  end
end

defmodule Genie.Conductor.Checks.HasRequiredRole do
  @moduledoc false
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor has the required role for this lamp"

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(actor, %{changeset: changeset}, _opts) do
    lamp_id = Ash.Changeset.get_attribute(changeset, :lamp_id)

    case Genie.Lamp.LampRegistry.fetch_lamp(lamp_id, authorize?: false) do
      {:ok, lamp} ->
        destructive = lamp.meta && lamp.meta.destructive

        if destructive do
          actor.role == :admin
        else
          actor.role in [:admin, :member]
        end

      _ ->
        false
    end
  end
end
