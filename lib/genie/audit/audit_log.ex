defmodule Genie.Audit.AuditLog do
  @moduledoc false
  use Ash.Resource,
    otp_app: :genie,
    domain: Genie.Audit,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "audit_logs"
    repo Genie.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [:session_id, :lamp_id, :intent_name, :actor_id, :trace_id, :oban_job_id, :result]
    end

    update :update do
      accept [:lamp_id]
    end

    destroy :destroy
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type([:update, :destroy]) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :session_id, :uuid do
      allow_nil? true
      public? true
    end

    attribute :lamp_id, :string do
      allow_nil? true
      public? true
    end

    attribute :intent_name, :string do
      allow_nil? true
      public? true
    end

    attribute :actor_id, :uuid do
      allow_nil? true
      public? true
    end

    attribute :trace_id, :string do
      allow_nil? true
      public? true
    end

    attribute :oban_job_id, :integer do
      allow_nil? true
      public? true
    end

    attribute :result, :atom do
      constraints one_of: [:success, :failed, :denied]
      allow_nil? true
      public? true
    end

    create_timestamp :inserted_at
  end
end
