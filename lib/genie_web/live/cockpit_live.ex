defmodule GenieWeb.CockpitLive do
  use GenieWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, message: "", page_title: "Cockpit")}
  end

  def handle_event("update_composer", %{"message" => message}, socket) do
    {:noreply, assign(socket, message: message)}
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
end
