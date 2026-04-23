defmodule Genie.Workers.LampActionWorker do
  use Oban.Worker, queue: :lamp_actions

  alias Genie.Accounts.User
  alias Genie.Bridge
  alias Genie.Conductor
  alias Genie.Lamp.{LampRegistry, LampRenderer, OptionDef}
  alias GenieWeb.CockpitLive

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "trigger" => "on_load",
          "lamp_id" => lamp_id,
          "endpoint_id" => endpoint_id,
          "session_id" => session_id
        }
      }) do
    result =
      with {:ok, lamp} <- LampRegistry.fetch_lamp(lamp_id),
           {:ok, field} <- find_fills_field(lamp, endpoint_id),
           {:ok, pairs} <- Bridge.fetch_options(lamp, field) do
        options = Enum.map(pairs, fn {v, l} -> %OptionDef{value: v, label: l} end)
        updated_lamp = put_field_options(lamp, field.id, options)
        {:safe, iodata} = LampRenderer.render(updated_lamp)
        {:ok, IO.iodata_to_binary(iodata)}
      end

    case result do
      {:ok, html} ->
        CockpitLive.push_canvas(session_id, html)
        :ok

      {:error, reason} ->
        CockpitLive.push_error(session_id, reason)
        :ok
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "lamp_id" => lamp_id,
          "endpoint_id" => endpoint_id,
          "params" => params,
          "actor_id" => actor_id,
          "session_id" => session_id
        }
      }) do
    actor = load_actor(actor_id)

    result =
      with {:ok, lamp_action} <-
             Conductor.build_action(lamp_id, endpoint_id, params || %{},
               actor: actor,
               session_id: session_id
             ),
           {:ok, html} <- Conductor.execute(lamp_action) do
        {:ok, html}
      end

    case result do
      {:ok, html} ->
        CockpitLive.push_canvas(session_id, html)
        :ok

      {:error, reason} ->
        CockpitLive.push_error(session_id, reason)
        :ok
    end
  end

  defp find_fills_field(lamp, endpoint_id) do
    case Enum.find(lamp.endpoints || [], &(&1.id == endpoint_id)) do
      nil -> {:error, :endpoint_not_found}
      %{fills_field: nil} -> {:error, :endpoint_has_no_fills_field}
      endpoint ->
        case Enum.find(lamp.fields || [], &(&1.id == endpoint.fills_field)) do
          nil -> {:error, :fills_field_not_found}
          field -> {:ok, field}
        end
    end
  end

  defp put_field_options(lamp, field_id, options) do
    updated_fields =
      Enum.map(lamp.fields || [], fn
        %{id: ^field_id} = field -> %{field | options: options, options_from: nil}
        field -> field
      end)

    %{lamp | fields: updated_fields}
  end

  defp load_actor(nil), do: nil

  defp load_actor(actor_id) do
    case Ash.get(User, actor_id, authorize?: false) do
      {:ok, user} -> user
      _ -> nil
    end
  end
end
