defmodule Genie.Conductor do
  @moduledoc false
  use Ash.Domain, otp_app: :genie

  alias Genie.Conductor.LampAction

  resources do
    resource LampAction
  end

  @spec build_action(String.t(), String.t(), map(), keyword()) ::
          {:ok, LampAction.t()} | {:error, term()}
  def build_action(lamp_id, endpoint_id, params, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    session_id = Keyword.get(opts, :session_id)

    LampAction
    |> Ash.Changeset.for_create(:create, %{
      lamp_id: lamp_id,
      endpoint_id: endpoint_id,
      params: params,
      actor_id: actor && actor.id,
      session_id: session_id
    })
    |> Ash.create(actor: actor)
  end

  @spec execute(LampAction.t()) :: {:ok, String.t()} | {:error, term()}
  def execute(%LampAction{} = lamp_action) do
    with {:ok, lamp} <- Genie.Lamp.LampRegistry.fetch_lamp(lamp_action.lamp_id) do
      Genie.Bridge.execute(%{
        lamp: lamp,
        endpoint_id: lamp_action.endpoint_id,
        params: lamp_action.params || %{},
        session_id: lamp_action.session_id && to_string(lamp_action.session_id)
      })
    end
  end
end
