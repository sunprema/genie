defmodule GenieWeb.CockpitLive do
  use GenieWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, message: "", page_title: "Cockpit")}
  end

  def handle_event("update_composer", %{"message" => message}, socket) do
    {:noreply, assign(socket, message: message)}
  end
end
