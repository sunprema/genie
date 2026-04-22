defmodule Genie.Accounts.ApiKey do
  use Ash.Resource,
    otp_app: :genie,
    domain: Genie.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "api_keys"
    repo Genie.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :key_hash, :expires_at, :user_id]
    end

    update :update do
      accept [:name, :expires_at]
    end

    destroy :destroy
  end

  policies do
    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action_type(:create) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action_type(:update) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action_type(:destroy) do
      authorize_if relates_to_actor_via(:user)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :key_hash, :string do
      allow_nil? false
      sensitive? true
    end

    attribute :expires_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :user, Genie.Accounts.User do
      allow_nil? false
      public? true
    end
  end
end
