defmodule Genie.Orchestrator.ReasoningLoop do
  @moduledoc """
  Ash Reactor that implements the AI reasoning loop for Genie.

  Inputs:
    - session_id: UUID of the current conversation session
    - user_message: the message text from the user
    - actor: the authenticated %User{} struct

  Steps:
    1. ValidateInputStep   — load session and lamp manifests
    2. BuildContextStep    — build LLM context from conversation history
    3. LlmCallStep         — call the LLM
    4. ToolExecutionLoopStep — execute tool calls, re-prompt until intent
    5. ValidateActionStep  — RBAC check, approval job insertion
    6. FillUiStep          — fill form fields, render HTML
    7. PushCockpitStep     — broadcast to Cockpit, write AuditLog

  Returns the result of the final push step.
  """
  use Ash.Reactor

  alias Genie.Orchestrator.Steps.{
    BuildContextStep,
    FillUiStep,
    LlmCallStep,
    PushCockpitStep,
    ToolExecutionLoopStep,
    ValidateActionStep,
    ValidateInputStep
  }

  input :session_id
  input :user_message
  input :actor

  step :validate_input, ValidateInputStep do
    argument :session_id, input(:session_id)
    argument :actor, input(:actor)
  end

  step :build_context, BuildContextStep do
    argument :session, result(:validate_input, :session)
    argument :manifests, result(:validate_input, :manifests)
    argument :user_message, input(:user_message)
  end

  step :llm_call, LlmCallStep do
    argument :build_context, result(:build_context)
  end

  step :tool_loop, ToolExecutionLoopStep do
    argument :llm_response, result(:llm_call)
    argument :build_context, result(:build_context)
  end

  step :validate_action, ValidateActionStep do
    argument :tool_loop_result, result(:tool_loop)
    argument :session, result(:validate_input, :session)
    argument :actor, result(:validate_input, :actor)
  end

  step :fill_ui, FillUiStep do
    argument :validated_action, result(:validate_action)
    argument :manifests, result(:validate_input, :manifests)
    argument :build_context, result(:build_context)
  end

  step :push_cockpit, PushCockpitStep do
    argument :ui_result, result(:fill_ui)
    argument :session_id, input(:session_id)
    argument :actor, input(:actor)
  end

  return :push_cockpit
end
