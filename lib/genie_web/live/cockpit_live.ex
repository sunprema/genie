defmodule GenieWeb.CockpitLive do
  use GenieWeb, :live_view

  alias Genie.Workers.{OrchestratorWorker, LampActionWorker}

  on_mount {GenieWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    session_id = Ecto.UUID.generate()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Genie.PubSub, "canvas:#{session_id}")
      Phoenix.PubSub.subscribe(Genie.PubSub, "chat:#{session_id}")
    end

    {:ok,
     socket
     |> assign(
       message: "",
       page_title: "Cockpit",
       session_id: session_id,
       lamp_field_values: %{},
       lamp_group_states: %{}
     )
     |> stream(:messages, [])}
  end

  def handle_event("update_composer", %{"message" => message}, socket) do
    {:noreply, assign(socket, message: message)}
  end

  def handle_event("send_message", %{"message" => message}, socket) do
    message = String.trim(message)

    if message == "" do
      {:noreply, socket}
    else
      session_id = socket.assigns.session_id
      actor_id = socket.assigns[:current_user] && socket.assigns.current_user.id

      %{session_id: session_id, user_message: message, actor_id: actor_id}
      |> OrchestratorWorker.new()
      |> Oban.insert()

      {:noreply,
       socket
       |> stream_insert(:messages, build_user_message(socket, message))
       |> assign(message: "")}
    end
  end

  def handle_event("lamp_submit", params, socket) do
    session_id = socket.assigns.session_id
    actor_id = socket.assigns[:current_user] && socket.assigns.current_user.id

    %{
      lamp_id: params["lamp_id"],
      endpoint_id: params["endpoint_id"],
      params: params["params"] || %{},
      actor_id: actor_id,
      session_id: session_id
    }
    |> LampActionWorker.new()
    |> Oban.insert()

    {:noreply, push_event(socket, "lamp_loading", %{})}
  end

  def handle_event("lamp_toggle", %{"field" => field_id, "value" => value}, socket) do
    lamp_field_values = Map.put(socket.assigns.lamp_field_values, field_id, value)
    {:noreply, assign(socket, lamp_field_values: lamp_field_values)}
  end

  def handle_event("lamp_field_change", %{"field" => field_id, "value" => value}, socket) do
    lamp_field_values = Map.put(socket.assigns.lamp_field_values, field_id, value)
    {:noreply, assign(socket, lamp_field_values: lamp_field_values)}
  end

  def handle_event("lamp_group_toggle", %{"group" => group_id}, socket) do
    lamp_group_states =
      Map.update(socket.assigns.lamp_group_states, group_id, true, &(!&1))

    {:noreply, assign(socket, lamp_group_states: lamp_group_states)}
  end

  def handle_info({:push_canvas, html}, socket) do
    {:noreply, push_event(socket, "update_canvas", %{html: html})}
  end

  def handle_info({:push_chat, message}, socket) do
    {:noreply,
     stream_insert(socket, :messages, %{
       id: Ecto.UUID.generate(),
       role: :agent,
       name: "Genie",
       text: message,
       timestamp: "just now",
       error: false
     })}
  end

  def handle_info({:push_error, reason}, socket) do
    reason_text = format_error(reason)

    {:noreply,
     socket
     |> stream_insert(:messages, %{
       id: Ecto.UUID.generate(),
       role: :agent,
       name: "Genie",
       text: reason_text,
       timestamp: "just now",
       error: true
     })
     |> push_event("canvas_error", %{reason: reason_text})}
  end

  def push_canvas(session_id, html) do
    Phoenix.PubSub.broadcast(Genie.PubSub, "canvas:#{session_id}", {:push_canvas, html})
  end

  def push_chat(session_id, message) do
    Phoenix.PubSub.broadcast(Genie.PubSub, "chat:#{session_id}", {:push_chat, message})
  end

  def push_error(session_id, reason) do
    Phoenix.PubSub.broadcast(Genie.PubSub, "canvas:#{session_id}", {:push_error, reason})
    Phoenix.PubSub.broadcast(Genie.PubSub, "chat:#{session_id}", {:push_error, reason})
  end

  defp build_user_message(socket, text) do
    name =
      case socket.assigns[:current_user] do
        nil -> "You"
        user -> user.name || "You"
      end

    %{id: Ecto.UUID.generate(), role: :user, name: name, text: text, timestamp: "just now", error: false}
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
