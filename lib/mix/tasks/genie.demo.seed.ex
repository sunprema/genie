defmodule Mix.Tasks.Genie.Demo.Seed do
  use Mix.Task

  @shortdoc "Seeds demo org, user, and session for live demonstration"

  @moduledoc """
  Creates a repeatable demo environment:

    - Organisation: "Genie Demo" (slug: "genie-demo")
    - User: demo@genie.dev / DemoUser123! (role: admin)
    - Session: "Live Demo" with pre-seeded context turns containing
        region=us-east-1, org_id, env=prod, bucket_name=acme-prod-assets

  Safe to run multiple times — existing records are reused by slug/email identity.
  """

  alias Genie.Accounts.{Organisation, User}
  alias Genie.Conversation.{Session, Turn}

  @demo_email "demo@genie.dev"
  @demo_password "DemoUser123!"
  @demo_org_slug "genie-demo"
  @context_message """
  Our AWS organisation is in us-east-1. Our org_id is genie-demo. \
  We operate in prod (env=prod). \
  We need to create a private versioned S3 bucket called acme-prod-assets in us-east-1.
  """

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    org = upsert_org()
    user = upsert_user(org)
    session = create_session(org, user)
    seed_context_turns(session, user)

    Mix.shell().info("""

    Demo seed complete.

      Org:     #{org.name} (#{org.slug})
      User:    #{@demo_email}
      Pass:    #{@demo_password}
      Session: #{session.id}

    Log in at http://localhost:4000 with the credentials above.
    """)
  end

  defp upsert_org do
    case Ash.get(Organisation, [slug: @demo_org_slug], authorize?: false, error?: false) do
      {:ok, org} ->
        Mix.shell().info("Reusing existing org: #{org.name}")
        org

      _ ->
        {:ok, org} =
          Organisation
          |> Ash.Changeset.for_create(:create, %{name: "Genie Demo", slug: @demo_org_slug})
          |> Ash.create(authorize?: false)

        Mix.shell().info("Created org: #{org.name}")
        org
    end
  end

  defp upsert_user(org) do
    case Ash.get(User, [email: @demo_email], authorize?: false, error?: false) do
      {:ok, user} ->
        Mix.shell().info("Reusing existing user: #{user.email}")
        ensure_user_in_org(user, org)

      _ ->
        {:ok, user} =
          User
          |> Ash.Changeset.for_action(:register_with_password, %{
            email: @demo_email,
            password: @demo_password,
            password_confirmation: @demo_password
          })
          |> Ash.create(authorize?: false)

        {:ok, user} =
          user
          |> Ash.Changeset.for_update(:update, %{role: :admin, org_id: org.id})
          |> Ash.update(authorize?: false)

        Mix.shell().info("Created user: #{user.email}")
        user
    end
  end

  defp ensure_user_in_org(%User{org_id: org_id} = user, %Organisation{id: org_id}), do: user

  defp ensure_user_in_org(user, org) do
    {:ok, updated} =
      user
      |> Ash.Changeset.for_update(:update, %{org_id: org.id})
      |> Ash.update(authorize?: false)

    updated
  end

  defp create_session(org, user) do
    {:ok, session} =
      Session
      |> Ash.Changeset.for_create(:create, %{
        title: "Live Demo",
        org_id: org.id,
        user_id: user.id
      })
      |> Ash.create(authorize?: false)

    Mix.shell().info("Created session: #{session.id}")
    session
  end

  defp seed_context_turns(session, _user) do
    {:ok, _} =
      Turn
      |> Ash.Changeset.for_create(:create, %{
        role: :user,
        content: @context_message,
        session_id: session.id
      })
      |> Ash.create(authorize?: false)

    {:ok, _} =
      Turn
      |> Ash.Changeset.for_create(:create, %{
        role: :agent,
        content:
          "Understood. I have your context: region=us-east-1, org=genie-demo, env=prod, bucket=acme-prod-assets. Ready to assist.",
        session_id: session.id
      })
      |> Ash.create(authorize?: false)

    Mix.shell().info("Seeded context turns for session")
  end
end
