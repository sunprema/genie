defmodule Genie.Workers.LampActionWorker do
  use Oban.Worker, queue: :lamp_actions

  alias Genie.Accounts.User
  alias Genie.Bridge
  alias Genie.Conductor
  alias Genie.Lamp.{LampRegistry, LampRenderer, OptionDef}
  alias Genie.Workers.ApprovalWorker
  alias GenieWeb.CockpitLive

  @active_session_window_hours 8

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "trigger" => "webhook",
          "lamp_id" => lamp_id,
          "org_id" => org_id
        }
      }) do
    result =
      with {:ok, lamp} <- LampRegistry.fetch_lamp(lamp_id),
           {:ok, incident_data} <- Bridge.execute_tool(%{lamp: lamp, endpoint_id: "list_incidents", params: %{}, session_id: ""}),
           {:ok, html} <- render_incident_html(lamp, incident_data) do
        broadcast_to_org_sessions(org_id, html)
        {:ok, :broadcast}
      end

    case result do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

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
    params = params || %{}

    result =
      with {:ok, lamp} <- LampRegistry.fetch_lamp(lamp_id),
           {:ok, lamp_action} <-
             Conductor.build_action(lamp_id, endpoint_id, params,
               actor: actor,
               session_id: session_id
             ) do
        if lamp.meta && lamp.meta.requires_approval && !demo_actor?(actor) do
          handle_approval_required(lamp, lamp_action, session_id)
        else
          with {:ok, html} <- Conductor.execute(lamp_action) do
            {:ok, lamp, html}
          end
        end
      end

    case result do
      {:ok, lamp, html} ->
        CockpitLive.push_canvas(session_id, html)
        run_poll_if_needed(lamp, endpoint_id, params, session_id)
        :ok

      {:ok, :pending_approval} ->
        :ok

      {:error, reason} ->
        CockpitLive.push_error(session_id, reason)
        :ok
    end
  end

  defp handle_approval_required(lamp, lamp_action, session_id) do
    case %{
           "action_id" => to_string(lamp_action.id),
           "approver_id" => nil,
           "decision" => "pending"
         }
         |> ApprovalWorker.new()
         |> Oban.insert() do
      {:ok, _job} ->
        {:safe, iodata} = LampRenderer.render_status(lamp, %{"state" => "pending-approval",
          "bucket_name" => get_in(lamp_action.params, ["bucket_name"]) || ""})
        html = IO.iodata_to_binary(iodata)
        CockpitLive.push_canvas(session_id, html)
        CockpitLive.push_pending_approval(session_id, to_string(lamp_action.id))
        CockpitLive.push_chat(session_id, "Waiting for approval. An admin has been notified to review this action.")
        {:ok, :pending_approval}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_poll_if_needed(lamp, submitted_endpoint_id, params, session_id) do
    poll_endpoint =
      Enum.find(lamp.endpoints || [], fn ep ->
        ep.trigger == :on_complete && ep.id != submitted_endpoint_id
      end)

    if poll_endpoint do
      run_poll_loop(lamp, poll_endpoint, params, session_id)
    end
  end

  defp run_poll_loop(lamp, endpoint, params, session_id) do
    timeout_ms = endpoint.timeout_ms || 60_000
    interval_ms = endpoint.poll_interval_ms || 2_000
    conditions = parse_poll_conditions(endpoint.poll_until)
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_poll(lamp, endpoint, params, session_id, conditions, interval_ms, deadline)
  end

  defp do_poll(lamp, endpoint, params, session_id, conditions, interval_ms, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      :ok
    else
      Process.sleep(interval_ms)

      case Bridge.execute_tool(%{lamp: lamp, endpoint_id: endpoint.id, params: params, session_id: session_id}) do
        {:ok, response} ->
          {:safe, iodata} = LampRenderer.render_status(lamp, response)
          html = IO.iodata_to_binary(iodata)
          CockpitLive.push_canvas(session_id, html)

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
      Enum.map(lamp.fields, fn
        %{id: ^field_id} = field -> %{field | options: options, options_from: nil}
        field -> field
      end)

    %{lamp | fields: updated_fields}
  end

  defp render_incident_html(lamp, data) when is_map(data) do
    result_map =
      cond do
        match?(%{"incidents" => _}, data) ->
          incidents = data["incidents"] || []
          state = if incidents == [], do: "no_incidents", else: "ready"
          Map.merge(data, %{"state" => state, "count" => length(incidents)})

        match?(%{"error" => _}, data) ->
          Map.put(data, "state", "failed")

        true ->
          Map.put(data, "state", "ready")
      end

    {:safe, iodata} = LampRenderer.render_status(lamp, result_map)
    {:ok, IO.iodata_to_binary(iodata)}
  end

  defp broadcast_to_org_sessions(org_id, html) do
    import Ecto.Query, only: [from: 2, where: 3]

    cutoff = DateTime.add(DateTime.utc_now(), -@active_session_window_hours, :hour)

    base = from(s in "sessions", select: %{id: s.id}, where: s.inserted_at > ^cutoff)

    query =
      if org_id do
        where(base, [s], s.org_id == ^org_id)
      else
        base
      end

    sessions = Genie.Repo.all(query)

    Enum.each(sessions, fn session ->
      CockpitLive.push_canvas(Ecto.UUID.load!(session.id), html)
    end)
  end

  defp load_actor(nil), do: nil

  defp load_actor(actor_id) do
    case Ash.get(User, actor_id, authorize?: false) do
      {:ok, user} -> user
      _ -> nil
    end
  end

  defp demo_actor?(nil), do: false

  defp demo_actor?(actor) do
    demo_email = Application.get_env(:genie, :demo_actor_email, "demo@genie.dev")
    to_string(actor.email) == demo_email
  end
end
