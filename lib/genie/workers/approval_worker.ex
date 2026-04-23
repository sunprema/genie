defmodule Genie.Workers.ApprovalWorker do
  use Oban.Worker, queue: :approvals

  alias Genie.Audit.AuditLog
  alias Genie.Conductor
  alias Genie.Conductor.LampAction
  alias Genie.Lamp.{LampRegistry, LampRenderer}
  alias GenieWeb.CockpitLive

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "action_id" => action_id,
          "approver_id" => approver_id,
          "decision" => decision
        }
      }) do
    case decision do
      "approve" -> handle_approval(action_id)
      "deny" -> handle_denial(action_id, approver_id)
      "pending" -> :ok
    end
  end

  defp handle_approval(action_id) do
    with {:ok, lamp_action} <- Ash.get(LampAction, action_id, authorize?: false),
         {:ok, lamp} <- LampRegistry.fetch_lamp(lamp_action.lamp_id),
         {:ok, html} <- Conductor.execute(lamp_action) do
      session_id = lamp_action.session_id && to_string(lamp_action.session_id)

      if session_id do
        CockpitLive.push_canvas(session_id, html)
        run_poll_if_needed(lamp, lamp_action.endpoint_id, lamp_action.params || %{}, session_id)
      end
    end

    :ok
  end

  defp run_poll_if_needed(lamp, submitted_endpoint_id, params, session_id) do
    poll_endpoint =
      Enum.find(lamp.endpoints || [], fn ep ->
        ep.trigger == :on_complete && ep.id != submitted_endpoint_id
      end)

    if poll_endpoint do
      timeout_ms = poll_endpoint.timeout_ms || 60_000
      interval_ms = poll_endpoint.poll_interval_ms || 2_000
      conditions = parse_poll_conditions(poll_endpoint.poll_until)
      deadline = System.monotonic_time(:millisecond) + timeout_ms
      do_poll(lamp, poll_endpoint, params, session_id, conditions, interval_ms, deadline)
    end
  end

  defp do_poll(lamp, endpoint, params, session_id, conditions, interval_ms, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      :ok
    else
      Process.sleep(interval_ms)

      case Genie.Bridge.execute_tool(%{lamp: lamp, endpoint_id: endpoint.id, params: params, session_id: session_id}) do
        {:ok, response} ->
          {:safe, iodata} = LampRenderer.render_status(lamp, response)
          CockpitLive.push_canvas(session_id, IO.iodata_to_binary(iodata))

          if poll_condition_met?(response, conditions) do
            :ok
          else
            do_poll(lamp, endpoint, params, session_id, conditions, interval_ms, deadline)
          end

        {:error, _} ->
          :ok
      end
    end
  end

  defp parse_poll_conditions(nil), do: []

  defp parse_poll_conditions(poll_until) do
    poll_until
    |> String.split("|")
    |> Enum.map(fn condition ->
      case String.split(condition, "=", parts: 2) do
        [key, value] -> {key, value}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp poll_condition_met?(_response, []), do: false

  defp poll_condition_met?(response, conditions) when is_map(response) do
    Enum.any?(conditions, fn {key, value} ->
      to_string(Map.get(response, key, "")) == value
    end)
  end

  defp handle_denial(action_id, _approver_id) do
    with {:ok, action} <- Ash.get(LampAction, action_id, authorize?: false) do
      AuditLog
      |> Ash.Changeset.for_create(:create, %{
        session_id: action.session_id,
        lamp_id: action.lamp_id,
        actor_id: action.actor_id,
        result: :denied
      })
      |> Ash.create(authorize?: false)

      if action.session_id do
        CockpitLive.push_error(to_string(action.session_id), :denied)
      end
    end

    :ok
  end
end
