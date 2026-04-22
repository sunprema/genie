defmodule Genie.Accounts.PolicyTest do
  use Genie.DataCase, async: true

  alias Genie.Accounts.{Organisation, User, ApiKey}

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

  defp create_api_key_for!(user) do
    ApiKey
    |> Ash.Changeset.for_create(:create, %{
      name: "my-key",
      key_hash: "hash-#{System.unique_integer([:positive])}",
      user_id: user.id
    })
    |> Ash.create!(authorize?: false)
  end

  # --- Organisation policies ---

  describe "Organisation read policy" do
    test "user can read their own organisation" do
      org = create_org!()
      user = create_user_in_org!(org)

      {:ok, orgs} = Ash.read(Organisation, actor: user)
      assert Enum.any?(orgs, &(&1.id == org.id))
    end

    test "cross-org: user cannot read another organisation" do
      org_a = create_org!()
      org_b = create_org!()
      user_a = create_user_in_org!(org_a)

      {:ok, orgs} = Ash.read(Organisation, actor: user_a)
      ids = Enum.map(orgs, & &1.id)
      assert org_a.id in ids
      refute org_b.id in ids
    end
  end

  # --- User policies ---

  describe "User read policy" do
    test "user can read other users in their own organisation" do
      org = create_org!()
      user_a = create_user_in_org!(org)
      user_b = create_user_in_org!(org)

      {:ok, users} = Ash.read(User, actor: user_a)
      ids = Enum.map(users, & &1.id)
      assert user_a.id in ids
      assert user_b.id in ids
    end

    test "cross-org: user cannot read users from another organisation" do
      org_a = create_org!()
      org_b = create_org!()
      user_a = create_user_in_org!(org_a)
      user_b = create_user_in_org!(org_b)

      {:ok, users} = Ash.read(User, actor: user_a)
      ids = Enum.map(users, & &1.id)
      assert user_a.id in ids
      refute user_b.id in ids
    end
  end

  # --- ApiKey policies ---

  describe "ApiKey read policy" do
    test "user can read their own api keys" do
      org = create_org!()
      user = create_user_in_org!(org)
      key = create_api_key_for!(user)

      {:ok, keys} = Ash.read(ApiKey, actor: user)
      assert Enum.any?(keys, &(&1.id == key.id))
    end

    test "cross-org: user cannot read another user's api keys" do
      org = create_org!()
      user_a = create_user_in_org!(org)
      user_b = create_user_in_org!(org)
      key_b = create_api_key_for!(user_b)

      {:ok, keys} = Ash.read(ApiKey, actor: user_a)
      ids = Enum.map(keys, & &1.id)
      refute key_b.id in ids
    end
  end
end
