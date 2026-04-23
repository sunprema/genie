defmodule Genie.Lamp.Loader do
  @moduledoc false
  require Logger

  @lamps_dir "lamps"

  def load_all do
    lamps_dir = Path.join(:code.priv_dir(:genie), @lamps_dir)

    case File.ls(lamps_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".xml"))
        |> Enum.each(&load_file(Path.join(lamps_dir, &1)))

      {:error, reason} ->
        Logger.warning("Could not list lamps directory: #{inspect(reason)}")
    end
  end

  defp load_file(path) do
    with {:ok, xml} <- File.read(path),
         {:ok, registry} <- Genie.Lamp.LampRegistry.register(%{xml_source: xml, enabled: true}) do
      Logger.info("Loaded lamp: #{registry.lamp_id}")
    else
      {:error, reason} ->
        Logger.error("Failed to load #{Path.basename(path)}: #{inspect(reason)}")
    end
  end
end
