defmodule Genie.Lamp.Changes.ParseXml do
  @moduledoc false
  use Ash.Resource.Change

  alias Genie.Lamp.LampParser
  alias Genie.Lamp.LampSerializer

  @impl true
  def change(changeset, _opts, _context) do
    xml_source = Ash.Changeset.get_attribute(changeset, :xml_source)

    case LampParser.parse(xml_source) do
      {:ok, defn} ->
        changeset
        |> Ash.Changeset.force_change_attribute(:lamp_id, defn.id)
        |> Ash.Changeset.force_change_attribute(:parsed_definition, LampSerializer.to_map(defn))

      {:error, reason} ->
        Ash.Changeset.add_error(changeset, field: :xml_source, message: reason)
    end
  end
end
