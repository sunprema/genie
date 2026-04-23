defmodule Genie.Workers.LampActionWorkerTest do
  use Genie.DataCase, async: false

  alias Genie.Workers.LampActionWorker
  alias Genie.Accounts.{Organisation, User}
  alias Genie.Lamp.LampRegistry

  @valid_xml File.read!(Path.join([:code.priv_dir(:genie), "lamps", "aws_s3_create_bucket.xml"]))

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

  defp register_global_lamp! do
    LampRegistry
    |> Ash.Changeset.for_create(:register, %{org_id: nil, xml_source: @valid_xml, enabled: true})
    |> Ash.create!(authorize?: false)
  end

  describe "perform/1" do
    test "with a successful Bridge call returns :ok and broadcasts push_canvas" do
      org = create_org!()
      actor = create_user_in_org!(org)
      register_global_lamp!()
      session_id = Ecto.UUID.generate()

      Phoenix.PubSub.subscribe(Genie.PubSub, "canvas:#{session_id}")

      Req.Test.stub(Genie.Bridge, fn conn ->
        Req.Test.json(conn, %{"state" => "ready", "bucket_name" => "test-bucket"})
      end)

      assert :ok =
               LampActionWorker.perform(%Oban.Job{
                 args: %{
                   "lamp_id" => "aws.s3.create-bucket",
                   "endpoint_id" => "create_bucket",
                   "params" => %{"bucket_name" => "test-bucket"},
                   "actor_id" => actor.id,
                   "session_id" => session_id
                 }
               })

      assert_receive {:push_canvas, html}
      assert is_binary(html)
    end

    test "with a Bridge error broadcasts push_error" do
      org = create_org!()
      actor = create_user_in_org!(org)
      register_global_lamp!()
      session_id = Ecto.UUID.generate()

      Phoenix.PubSub.subscribe(Genie.PubSub, "canvas:#{session_id}")
      Phoenix.PubSub.subscribe(Genie.PubSub, "chat:#{session_id}")

      Req.Test.stub(Genie.Bridge, fn conn ->
        Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      assert :ok =
               LampActionWorker.perform(%Oban.Job{
                 args: %{
                   "lamp_id" => "aws.s3.create-bucket",
                   "endpoint_id" => "create_bucket",
                   "params" => %{},
                   "actor_id" => actor.id,
                   "session_id" => session_id
                 }
               })

      assert_receive {:push_error, _reason}
    end
  end
end
