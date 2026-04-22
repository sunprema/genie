defmodule Mix.Tasks.Genie.Lamps.Load do
  use Mix.Task

  @shortdoc "Loads all lamp XML files from priv/lamps/ into the registry"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    Genie.Lamp.Loader.load_all()
  end
end
