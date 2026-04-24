defmodule Genie.Lamp.Handler.Compiler do
  @moduledoc """
  Compile-time check that an inline lamp handler has an `@endpoint` clause for
  every endpoint declared in the lamp XML. Runs via `@before_compile` wired by
  `use Genie.Lamp.Handler`. Missing clauses emit `IO.warn/2`, which is promoted
  to a compile error under `mix compile --warnings-as-errors` in CI.
  """

  @lamps_dir "lamps"

  defmacro __before_compile__(env) do
    lamp_id = Module.get_attribute(env.module, :genie_lamp_id)
    declared = env.module |> Module.get_attribute(:endpoint) |> List.wrap()

    case expected_endpoints(lamp_id) do
      {:ok, expected} ->
        missing = Enum.uniq(expected -- declared)
        extra = Enum.uniq(declared -- expected)

        if missing != [] do
          IO.warn(
            "#{inspect(env.module)} is declared for lamp #{lamp_id} but has no @endpoint clause for: #{inspect(missing)}",
            env
          )
        end

        if extra != [] do
          IO.warn(
            "#{inspect(env.module)} has @endpoint clauses for #{inspect(extra)} which are not declared in lamp #{lamp_id}",
            env
          )
        end

      {:error, reason} ->
        IO.warn(
          "#{inspect(env.module)} declared for lamp #{lamp_id}: could not verify endpoints (#{inspect(reason)})",
          env
        )
    end

    :ok
  end

  @doc """
  Returns the list of endpoint IDs declared for `lamp_id` by scanning lamp XML
  files under `priv/lamps/`. Also callable from runtime checks (e.g. a mix task).
  """
  @spec expected_endpoints(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def expected_endpoints(nil), do: {:error, :missing_lamp_id}

  def expected_endpoints(lamp_id) when is_binary(lamp_id) do
    lamps_dir = Path.join(:code.priv_dir(:genie), @lamps_dir)

    with {:ok, files} <- File.ls(lamps_dir),
         {:ok, endpoints} <- find_lamp(lamps_dir, files, lamp_id) do
      {:ok, endpoints}
    end
  end

  defp find_lamp(lamps_dir, files, lamp_id) do
    files
    |> Enum.filter(&String.ends_with?(&1, ".xml"))
    |> Enum.find_value({:error, {:lamp_not_found, lamp_id}}, fn file ->
      path = Path.join(lamps_dir, file)

      with {:ok, xml} <- File.read(path),
           {:ok, defn} <- Genie.Lamp.LampParser.parse(xml),
           true <- defn.id == lamp_id do
        {:ok, Enum.map(defn.endpoints, & &1.id)}
      else
        _ -> nil
      end
    end)
  end
end
