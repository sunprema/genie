defmodule Mix.Tasks.Genie.Lamp.VerifyTest do
  # Tests that check module attribute lookup rely on the real handler modules
  # already being compiled, so we don't need test isolation here.
  use ExUnit.Case, async: true

  test "every lamp in priv/lamps/ has a corresponding handler that implements handle_endpoint/3" do
    lamps_dir = Path.join(:code.priv_dir(:genie), "lamps")

    for file <- File.ls!(lamps_dir), String.ends_with?(file, ".xml") do
      xml = File.read!(Path.join(lamps_dir, file))
      assert {:ok, defn} = Genie.Lamp.LampParser.parse(xml), "#{file} did not parse"

      if defn.meta.runtime == "inline" do
        module = Module.concat([defn.meta.handler])
        assert Code.ensure_loaded?(module), "#{file}: handler #{defn.meta.handler} not loaded"

        assert function_exported?(module, :handle_endpoint, 3),
               "#{file}: #{defn.meta.handler} does not export handle_endpoint/3"

        declared =
          module.__info__(:attributes)
          |> Keyword.get_values(:endpoint)
          |> List.flatten()

        expected = Enum.map(defn.endpoints, & &1.id)

        missing = expected -- declared
        extra = declared -- expected

        assert missing == [], "#{file}: handler #{defn.meta.handler} is missing @endpoint clauses for #{inspect(missing)}"
        assert extra == [], "#{file}: handler #{defn.meta.handler} has extra @endpoint clauses for #{inspect(extra)} not in XML"
      end
    end
  end
end
