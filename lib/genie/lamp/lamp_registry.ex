defmodule Genie.Lamp.LampRegistry do
  use Ash.Resource,
    otp_app: :genie,
    domain: Genie.Lamp,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Genie.Lamp.{Changes.ParseXml, LampSerializer}

  postgres do
    table "lamp_registry"
    repo Genie.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :register do
      accept [:org_id, :xml_source, :enabled]
      upsert? true
      upsert_identity :unique_lamp_id
      upsert_fields [:xml_source, :parsed_definition, :enabled, :updated_at]

      change ParseXml
    end

    read :list_active do
      argument :org_id, :uuid, allow_nil?: true

      filter expr(
               enabled == true and
                 (is_nil(org_id) or is_nil(^arg(:org_id)) or org_id == ^arg(:org_id))
             )
    end

    read :by_lamp_id do
      argument :lamp_id, :string, allow_nil?: false
      get? true

      filter expr(lamp_id == ^arg(:lamp_id))
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :lamp_id, :string do
      allow_nil? false
      public? true
    end

    attribute :org_id, :uuid do
      allow_nil? true
      public? true
    end

    attribute :xml_source, :string do
      allow_nil? false
      public? true
    end

    attribute :parsed_definition, :map do
      allow_nil? false
      public? true
    end

    attribute :enabled, :boolean do
      allow_nil? false
      default true
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_lamp_id, [:lamp_id]
  end

  code_interface do
    define :register, action: :register
    define :list_active, action: :list_active, args: [:org_id]
    define :by_lamp_id, action: :by_lamp_id, args: [:lamp_id]
  end

  def load_active_manifests(org_id, opts \\ []) do
    case list_active(org_id, opts) do
      {:ok, records} ->
        {:ok, Enum.map(records, &LampSerializer.from_map(&1.parsed_definition))}

      {:error, _} = error ->
        error
    end
  end

  def fetch_lamp(lamp_id, opts \\ []) do
    case by_lamp_id(lamp_id, opts) do
      {:ok, nil} ->
        {:error, "lamp not found: #{lamp_id}"}

      {:ok, record} ->
        {:ok, LampSerializer.from_map(record.parsed_definition)}

      {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} ->
        {:error, "lamp not found: #{lamp_id}"}

      {:error, _} = error ->
        error
    end
  end
end
