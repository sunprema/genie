defmodule Genie.Conductor.LampAction do
  use Ash.Resource,
    otp_app: :genie,
    domain: Genie.Conductor,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Genie.Conductor.Checks

  postgres do
    table "lamp_actions"
    repo Genie.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :lamp_id,
        :endpoint_id,
        :params,
        :actor_id,
        :session_id,
        :requires_approval,
        :status,
        :oban_job_id
      ]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      forbid_unless Checks.LampOrgAccess
      forbid_unless Checks.HasRequiredRole
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :lamp_id, :string do
      allow_nil? false
      public? true
    end

    attribute :endpoint_id, :string do
      allow_nil? false
      public? true
    end

    attribute :params, :map do
      allow_nil? true
      public? true
    end

    attribute :actor_id, :uuid do
      allow_nil? true
      public? true
    end

    attribute :session_id, :uuid do
      allow_nil? true
      public? true
    end

    attribute :requires_approval, :boolean do
      allow_nil? true
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:pending, :approved, :denied, :executed, :failed]
      allow_nil? true
      public? true
    end

    attribute :oban_job_id, :integer do
      allow_nil? true
      public? true
    end

    create_timestamp :inserted_at
  end
end
