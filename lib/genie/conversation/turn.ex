defmodule Genie.Conversation.Turn do
  use Ash.Resource,
    otp_app: :genie,
    domain: Genie.Conversation,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "turns"
    repo Genie.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [:role, :content, :session_id]
    end

    update :update do
      accept [:content]
    end

    destroy :destroy

    read :recent_turns do
      argument :session_id, :uuid, allow_nil?: false
      argument :limit, :integer, default: 20

      filter expr(session_id == ^arg(:session_id))

      prepare fn query, _context ->
        limit = Ash.Query.get_argument(query, :limit)

        query
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.Query.limit(limit)
      end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if Genie.Conversation.Checks.TurnSameOrg
    end

    policy action_type(:create) do
      authorize_if Genie.Conversation.Checks.TurnSameOrg
    end

    policy action_type(:update) do
      authorize_if Genie.Conversation.Checks.TurnSameOrg
    end

    policy action_type(:destroy) do
      authorize_if Genie.Conversation.Checks.TurnSameOrg
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom do
      constraints one_of: [:user, :agent]
      allow_nil? false
      public? true
    end

    attribute :content, :string do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :session, Genie.Conversation.Session do
      allow_nil? false
      public? true
    end
  end
end
