defmodule Mix.Tasks.Genie.Lamp.Verify do
  @shortdoc "Verifies every lamp XML parses and every inline handler resolves"

  @moduledoc """
  Walks `priv/lamps/*.xml` and verifies each lamp is well-formed:

  1. Parses the XML through `Genie.Lamp.LampParser` (all existing validators run).
  2. For `runtime=inline` lamps, resolves the declared handler module and
     confirms it exports `handle_endpoint/3`, and that every declared endpoint
     has a matching `@endpoint` clause on the handler.

  Exits with a non-zero status if any lamp fails verification. Intended to be
  wired into CI so lamp/handler contract drift fails the pipeline.
  """

  use Mix.Task

  alias Genie.Lamp.LampParser

  @lamps_dir "lamps"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("loadpaths")

    lamps_dir = lamps_dir()

    case File.ls(lamps_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".xml"))
        |> Enum.sort()
        |> Enum.flat_map(&verify_file(Path.join(lamps_dir, &1)))
        |> report_and_exit()

      {:error, reason} ->
        Mix.shell().error("Could not list lamps directory #{lamps_dir}: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp verify_file(path) do
    basename = Path.basename(path)

    with {:ok, xml} <- File.read(path),
         {:ok, defn} <- LampParser.parse(xml) do
      Mix.shell().info("  ok  #{defn.id} (#{basename})")
      inline_errors(defn, basename)
    else
      {:error, reason} ->
        [{basename, :parse_failed, reason}]
    end
  end

  defp inline_errors(%{meta: %{runtime: "inline", handler: handler_name}} = defn, basename) do
    case resolve_handler(handler_name) do
      {:ok, module} ->
        check_endpoint_coverage(defn, module, basename)

      {:error, reason} ->
        [{basename, :handler_resolve_failed, reason}]
    end
  end

  defp inline_errors(_defn, _basename), do: []

  defp resolve_handler(nil), do: {:error, :handler_not_declared}
  defp resolve_handler(""), do: {:error, :handler_not_declared}

  defp resolve_handler(name) when is_binary(name) do
    module = Module.concat([name])

    cond do
      not Code.ensure_loaded?(module) ->
        {:error, {:module_not_loaded, name}}

      not function_exported?(module, :handle_endpoint, 3) ->
        {:error, {:missing_callback, name}}

      true ->
        {:ok, module}
    end
  end

  defp check_endpoint_coverage(defn, module, basename) do
    declared = declared_endpoints(module)
    expected = Enum.map(defn.endpoints, & &1.id)

    missing = expected -- declared
    extra = declared -- expected

    errors = []
    errors = if missing == [], do: errors, else: [{basename, :missing_endpoints, missing} | errors]
    errors = if extra == [], do: errors, else: [{basename, :extra_endpoints, extra} | errors]

    errors
  end

  defp declared_endpoints(module) do
    module.__info__(:attributes)
    |> Keyword.get_values(:endpoint)
    |> List.flatten()
  rescue
    _ -> []
  end

  defp report_and_exit([]) do
    Mix.shell().info("")
    Mix.shell().info("✓ all lamps verified")
  end

  defp report_and_exit(errors) do
    Mix.shell().error("")
    Mix.shell().error("Lamp verification failed:")

    for {file, kind, detail} <- errors do
      Mix.shell().error("  - #{file}: #{kind} — #{inspect(detail)}")
    end

    exit({:shutdown, 1})
  end

  defp lamps_dir do
    :code.priv_dir(:genie)
    |> to_string()
    |> Path.join(@lamps_dir)
  end
end
