defmodule Genie.Workers.OrchestratorWorkerTest do
  use Genie.DataCase, async: false

  alias Genie.Accounts.{Organisation, User}
  alias Genie.Workers.OrchestratorWorker

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
    |> Ash.Changeset.for_update(:update, %{org_id: org.id, role: :admin})
    |> Ash.update!(authorize?: false)
  end

  describe "perform/1" do
    test "runs ReasoningLoop and returns :ok on success" do
      org = create_org!()
      actor = create_user_in_org!(org)
      session_id = Ecto.UUID.generate()

      Phoenix.PubSub.subscribe(Genie.PubSub, "chat:#{session_id}")

      result =
        OrchestratorWorker.perform(%Oban.Job{
          args: %{
            "session_id" => session_id,
            "user_message" => "list EC2 instances",
            "actor_id" => actor.id
          }
        })

      assert result == :ok
    end

    test "returns :ok when actor_id is nil" do
      session_id = Ecto.UUID.generate()

      result =
        OrchestratorWorker.perform(%Oban.Job{
          args: %{
            "session_id" => session_id,
            "user_message" => "hello",
            "actor_id" => nil
          }
        })

      assert result == :ok
    end

    test "returns :ok when actor_id does not exist" do
      session_id = Ecto.UUID.generate()

      result =
        OrchestratorWorker.perform(%Oban.Job{
          args: %{
            "session_id" => session_id,
            "user_message" => "hello",
            "actor_id" => Ecto.UUID.generate()
          }
        })

      assert result == :ok
    end
  end
end
