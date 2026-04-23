defmodule Genie.Orchestrator.Steps.PushCockpitStep do
  @moduledoc """
  Step 7: Pushes rendered HTML to the Cockpit canvas (or a message to chat),
  writes an immutable AuditLog entry, and persists both the user and agent
  turns so future requests have full conversation history.
  """
  use Reactor.Step

  alias Genie.Audit.AuditLog
  alias Genie.Conversation.Turn
  alias GenieWeb.CockpitLive

  @impl Reactor.Step
  def run(%{ui_result: %{type: :canvas, html: html, lamp_id: lamp_id}, session_id: session_id, user_message: user_message, actor: actor}, _context, _options) do
    CockpitLive.push_canvas(to_string(session_id), html)
    write_audit_log(session_id, lamp_id, actor)
    save_turns(session_id, user_message, "[Showing #{lamp_id} form]")
    {:ok, :sent}
  end

  def run(%{ui_result: %{type: :chat, message: text}, session_id: session_id, user_message: user_message, actor: actor}, _context, _options) do
    CockpitLive.push_chat(to_string(session_id), text)
    write_audit_log(session_id, nil, actor)
    save_turns(session_id, user_message, text)
    {:ok, :sent}
  end

  @impl Reactor.Step
  def undo(_value, %{session_id: session_id, ui_result: ui_result}, _context, _options) do
    _ = {session_id, ui_result}
    :ok
  end

  defp save_turns(session_id, user_message, agent_reply) do
    Turn
    |> Ash.Changeset.for_create(:create, %{role: :user, content: user_message, session_id: session_id})
    |> Ash.create(authorize?: false)

    Turn
    |> Ash.Changeset.for_create(:create, %{role: :agent, content: agent_reply, session_id: session_id})
    |> Ash.create(authorize?: false)

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
