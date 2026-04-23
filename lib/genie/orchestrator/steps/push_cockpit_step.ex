defmodule Genie.Orchestrator.Steps.PushCockpitStep do
  @moduledoc """
  Step 7: Pushes rendered HTML to the Cockpit canvas (or a message to chat),
  writes an immutable AuditLog entry, and persists both the user and agent
  turns so future requests have full conversation history.
  """
  use Reactor.Step

  require OpenTelemetry.Tracer, as: Tracer

  alias Genie.Audit.AuditLog
  alias Genie.Conversation.Turn
  alias GenieWeb.CockpitLive

  @impl Reactor.Step
  def run(%{ui_result: %{type: :canvas, html: html, lamp_id: lamp_id}, session_id: session_id, user_message: user_message, actor: actor}, _context, _options) do
    Tracer.with_span "Genie.canvas.push", %{
      attributes: [{"session_id", to_string(session_id)}, {"lamp_id", to_string(lamp_id)}]
    } do
      CockpitLive.push_canvas(to_string(session_id), html)
      write_audit_log(session_id, lamp_id, actor)
      save_turns(session_id, user_message, "[Showing #{lamp_id} form]")
      {:ok, :sent}
    end
  end

  def run(%{ui_result: %{type: :chat, message: text}, session_id: session_id, user_message: user_message, actor: actor}, _context, _options) do
    Tracer.with_span "Genie.canvas.push", %{
      attributes: [{"session_id", to_string(session_id)}, {"lamp_id", "chat"}]
    } do
      CockpitLive.push_chat(to_string(session_id), text)
      write_audit_log(session_id, nil, actor)
      save_turns(session_id, user_message, text)
      {:ok, :sent}
    end
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
    trace_id = current_otel_trace_id()

    AuditLog
    |> Ash.Changeset.for_create(:create, %{
      session_id: session_id,
      lamp_id: lamp_id,
      actor_id: actor && actor.id,
      trace_id: trace_id,
      result: :success
    })
    |> Ash.create(authorize?: false)
  end

  defp current_otel_trace_id do
    case :otel_tracer.current_span_ctx() do
      :undefined ->
        nil

      span_ctx ->
        trace_id = :otel_span.trace_id(span_ctx)

        if trace_id == 0 do
          nil
        else
          trace_id
          |> Integer.to_string(16)
          |> String.downcase()
          |> String.pad_leading(32, "0")
        end
    end
  end
end
