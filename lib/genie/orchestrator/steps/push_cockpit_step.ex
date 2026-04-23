defmodule Genie.Orchestrator.Steps.PushCockpitStep do
  @moduledoc """
  Step 7: Pushes rendered HTML to the Cockpit canvas (or a message to chat),
  then writes an immutable AuditLog entry.

  Undo stores the pending UI in a session cache (stub — full reconnect logic is in Slice 15).
  """
  use Reactor.Step

  alias Genie.Audit.AuditLog
  alias GenieWeb.CockpitLive

  @impl Reactor.Step
  def run(%{ui_result: %{type: :canvas, html: html, lamp_id: lamp_id}, session_id: session_id, actor: actor}, _context, _options) do
    CockpitLive.push_canvas(to_string(session_id), html)
    write_audit_log(session_id, lamp_id, actor)
    {:ok, :sent}
  end

  def run(%{ui_result: %{type: :chat, message: text}, session_id: session_id, actor: actor}, _context, _options) do
    CockpitLive.push_chat(to_string(session_id), text)
    write_audit_log(session_id, nil, actor)
    {:ok, :sent}
  end

  @impl Reactor.Step
  def undo(_value, %{session_id: session_id, ui_result: ui_result}, _context, _options) do
    # Stub: in a full implementation, store pending UI in SessionCache
    # so it can be re-pushed on reconnect
    _ = {session_id, ui_result}
    :ok
  end

  defp write_audit_log(session_id, lamp_id, actor) do
    AuditLog
    |> Ash.Changeset.for_create(:create, %{
      session_id: session_id,
      lamp_id: lamp_id,
      actor_id: actor && actor.id,
      result: :success
    })
    |> Ash.create(authorize?: false)
  end
end
