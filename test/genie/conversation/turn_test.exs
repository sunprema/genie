defmodule Genie.Conversation.TurnTest do
  use Genie.DataCase, async: true

  alias Genie.Accounts.{Organisation, User}
  alias Genie.Conversation.{Session, Turn}

  # --- helpers ---

  defp create_org! do
    n = System.unique_integer([:positive])

    Organisation
    |> Ash.Changeset.for_create(:create, %{name: "Org #{n}", slug: "org-#{n}"})
    |> Ash.create!(authorize?: false)
  end

  defp create_user_in_org!(org) do
    n = System.unique_integer([:positive])

    user =
      User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "user-#{n}@example.com",
        password: "password123",
        password_confirmation: "password123"
      })
      |> Ash.create!(authorize?: false)

    user
    |> Ash.Changeset.for_update(:update, %{org_id: org.id})
    |> Ash.update!(authorize?: false)
  end

  defp create_session!(user, org) do
    Session
    |> Ash.Changeset.for_create(:create, %{
      title: "Test session",
      org_id: org.id,
      user_id: user.id
    })
    |> Ash.create!(authorize?: false)
  end

  defp create_turn!(session, role, content) do
    Turn
    |> Ash.Changeset.for_create(:create, %{
      session_id: session.id,
      role: role,
      content: content
    })
    |> Ash.create!(authorize?: false)
  end

  # --- recent_turns ---

  describe "recent_turns/2" do
    test "returns turns for the given session ordered by inserted_at desc" do
      org = create_org!()
      user = create_user_in_org!(org)
      session = create_session!(user, org)

      turn1 = create_turn!(session, :user, "Hello")
      turn2 = create_turn!(session, :agent, "Hi there")

      turns =
        Turn
        |> Ash.Query.for_read(:recent_turns, %{session_id: session.id, limit: 10}, actor: user)
        |> Ash.read!()

      ids = Enum.map(turns, & &1.id)
      assert turn1.id in ids
      assert turn2.id in ids
      assert length(turns) == 2

      [first | _] = turns
      assert first.id == turn2.id
    end

    test "respects the limit argument" do
      org = create_org!()
      user = create_user_in_org!(org)
      session = create_session!(user, org)

      for i <- 1..5, do: create_turn!(session, :user, "msg #{i}")

      turns =
        Turn
        |> Ash.Query.for_read(:recent_turns, %{session_id: session.id, limit: 3}, actor: user)
        |> Ash.read!()

      assert length(turns) == 3
    end

    test "only returns turns for the specified session" do
      org = create_org!()
      user = create_user_in_org!(org)
      session_a = create_session!(user, org)
      session_b = create_session!(user, org)

      _turn_a = create_turn!(session_a, :user, "A message")
      turn_b = create_turn!(session_b, :user, "B message")

      turns =
        Turn
        |> Ash.Query.for_read(:recent_turns, %{session_id: session_b.id, limit: 10}, actor: user)
        |> Ash.read!()

      assert length(turns) == 1
      assert hd(turns).id == turn_b.id
    end
  end
end
