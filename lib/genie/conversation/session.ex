defmodule Genie.Conversation.Session do
  @moduledoc false
  use Ash.Resource,
    otp_app: :genie,
    domain: Genie.Conversation,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "sessions"
    repo Genie.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [:title, :org_id, :user_id]
    end

    update :update do
      accept [:title]
    end

    destroy :destroy
  end

  policies do
    policy action_type(:read) do
      authorize_if Genie.Accounts.Checks.SameOrg
    end

    policy action_type(:create) do
      authorize_if Genie.Accounts.Checks.SameOrg
    end

    policy action_type(:update) do
      authorize_if Genie.Accounts.Checks.SameOrg
    end

    policy action_type(:destroy) do
      authorize_if Genie.Accounts.Checks.SameOrg
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? true
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :org, Genie.Accounts.Organisation do
      allow_nil? false
      public? true
    end

    belongs_to :user, Genie.Accounts.User do
      allow_nil? false
      public? true
    end
  end
end
