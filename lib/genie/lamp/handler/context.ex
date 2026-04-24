defmodule Genie.Lamp.Handler.Context do
  @moduledoc """
  Passed to every inline lamp handler callback. Carries everything an HTTP lamp
  backend would normally receive via request headers, plus the already-resolved
  actor, lamp, and endpoint so handlers don't have to re-lookup definitions.
  """

  @enforce_keys [:lamp_id, :endpoint_id, :trace_id]
  defstruct [
    :lamp_id,
    :endpoint_id,
    :session_id,
    :trace_id,
    :actor,
    :org_id,
    :lamp,
    :endpoint,
    :started_at,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          lamp_id: String.t(),
          endpoint_id: String.t(),
          session_id: String.t() | nil,
          trace_id: String.t(),
          actor: struct() | nil,
          org_id: String.t() | nil,
          lamp: Genie.Lamp.LampDefinition.t() | nil,
          endpoint: Genie.Lamp.EndpointDef.t() | nil,
          started_at: integer() | nil,
          metadata: map()
        }
end
