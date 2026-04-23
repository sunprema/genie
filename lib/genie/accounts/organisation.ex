defmodule Genie.Accounts.Organisation do
  @moduledoc false
  use Ash.Resource,
    otp_app: :genie,
    domain: Genie.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "organisations"
    repo Genie.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :slug]
    end

    update :update do
      accept [:name, :slug]
    end

    destroy :destroy
  end

  policies do
    policy action_type(:read) do
      authorize_if Genie.Accounts.Checks.ActorOrg
    end

    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type(:update) do
      authorize_if Genie.Accounts.Checks.ActorOrg
    end

    policy action_type(:destroy) do
      authorize_if Genie.Accounts.Checks.ActorOrg
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :slug, :string do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
