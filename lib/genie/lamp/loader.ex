defmodule Genie.Lamp.Loader do
  @moduledoc false
  require Logger

  @lamps_dir "lamps"

  def load_all do
    lamps_dir = Path.join(:code.priv_dir(:genie), @lamps_dir)

    case File.ls(lamps_dir) do
      {:ok, files} ->
        registered =
          files
          |> Enum.filter(&String.ends_with?(&1, ".xml"))
          |> Enum.flat_map(&load_file(Path.join(lamps_dir, &1)))

        verify_inline_handlers(registered)

      {:error, reason} ->
        Logger.warning("Could not list lamps directory: #{inspect(reason)}")
    end
  end

  defp load_file(path) do
    with {:ok, xml} <- File.read(path),
         {:ok, registry} <- Genie.Lamp.LampRegistry.register(%{xml_source: xml, enabled: true}) do
      Logger.info("Loaded lamp: #{registry.lamp_id}")
      [registry.lamp_id]
    else
      {:error, reason} ->
        Logger.error("Failed to load #{Path.basename(path)}: #{inspect(reason)}")
        []
    end
  end

  # Inline lamps declare a handler module name in XML. Resolve each one at boot
  # so a missing or misspelled module surfaces here, not on the first request.
  defp verify_inline_handlers(lamp_ids) do
    for lamp_id <- lamp_ids,
        {:ok, lamp} <- [Genie.Lamp.LampRegistry.fetch_lamp(lamp_id)],
        lamp.meta && lamp.meta.runtime == "inline" do
      case resolve_handler(lamp.meta.handler) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.error(
            "[lamp #{lamp_id}] inline handler resolution failed: #{inspect(reason)}"
          )
      end
    end
  end

  defp resolve_handler(nil), do: {:error, :handler_not_declared}
  defp resolve_handler(""), do: {:error, :handler_not_declared}

  defp resolve_handler(name) when is_binary(name) do
    module = Module.concat([name])

    cond do
      not Code.ensure_loaded?(module) ->
        {:error, {:handler_module_not_loaded, name}}

      not function_exported?(module, :handle_endpoint, 3) ->
        {:error, {:handler_missing_callback, name}}

      true ->
        :ok
    end
  end
end
