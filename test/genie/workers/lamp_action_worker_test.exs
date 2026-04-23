defmodule Genie.Workers.LampActionWorkerTest do
  use Genie.DataCase, async: false

  alias Genie.Workers.LampActionWorker
  alias Genie.Accounts.{Organisation, User}
  alias Genie.Lamp.LampRegistry

  @valid_xml File.read!(Path.join([:code.priv_dir(:genie), "lamps", "aws_s3_create_bucket.xml"]))
  @ec2_xml File.read!(Path.join([:code.priv_dir(:genie), "lamps", "aws_ec2_list_instances.xml"]))

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

  defp register_global_lamp!(xml) do
    LampRegistry
    |> Ash.Changeset.for_create(:register, %{org_id: nil, xml_source: xml, enabled: true})
    |> Ash.create!(authorize?: false)
  end

  describe "perform/1 — S3 lamp" do
    test "with a successful Bridge call returns :ok and broadcasts push_canvas" do
      org = create_org!()
      actor = create_user_in_org!(org)
      register_global_lamp!(@valid_xml)
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
      register_global_lamp!(@valid_xml)
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

  describe "perform/1 — EC2 on-load trigger" do
    test "fires load_regions and pushes rendered lamp with populated region options" do
      register_global_lamp!(@ec2_xml)
      session_id = Ecto.UUID.generate()

      Phoenix.PubSub.subscribe(Genie.PubSub, "canvas:#{session_id}")

      Req.Test.stub(Genie.Bridge, fn conn ->
        Req.Test.json(conn, [
          %{"code" => "us-east-1", "name" => "US East (N. Virginia)"},
          %{"code" => "us-west-2", "name" => "US West (Oregon)"}
        ])
      end)

      assert :ok =
               LampActionWorker.perform(%Oban.Job{
                 args: %{
                   "trigger" => "on_load",
                   "lamp_id" => "aws.ec2.list-instances",
                   "endpoint_id" => "load_regions",
                   "session_id" => session_id
                 }
               })

      assert_receive {:push_canvas, html}
      assert html =~ "us-east-1"
      assert html =~ "US East (N. Virginia)"
      assert html =~ "us-west-2"
    end

    test "on-load Bridge error broadcasts push_error" do
      register_global_lamp!(@ec2_xml)
      session_id = Ecto.UUID.generate()

      Phoenix.PubSub.subscribe(Genie.PubSub, "canvas:#{session_id}")
      Phoenix.PubSub.subscribe(Genie.PubSub, "chat:#{session_id}")

      Req.Test.stub(Genie.Bridge, fn conn ->
        Plug.Conn.send_resp(conn, 503, "Service Unavailable")
      end)

      assert :ok =
               LampActionWorker.perform(%Oban.Job{
                 args: %{
                   "trigger" => "on_load",
                   "lamp_id" => "aws.ec2.list-instances",
                   "endpoint_id" => "load_regions",
                   "session_id" => session_id
                 }
               })

      assert_receive {:push_error, _reason}
    end
  end

  describe "perform/1 — EC2 instance listing" do
    test "renders table of instances on submit and broadcasts push_canvas" do
      org = create_org!()
      actor = create_user_in_org!(org)
      register_global_lamp!(@ec2_xml)
      session_id = Ecto.UUID.generate()

      Phoenix.PubSub.subscribe(Genie.PubSub, "canvas:#{session_id}")

      Req.Test.stub(Genie.Bridge, fn conn ->
        Req.Test.json(conn, %{
          "state" => "ready",
          "region" => "us-east-1",
          "instances" => [
            %{
              "instance_id" => "i-0abc1234",
              "instance_type" => "t3.micro",
              "state" => "running",
              "availability_zone" => "us-east-1a",
              "public_ip" => "54.123.45.67"
            }
          ]
        })
      end)

      assert :ok =
               LampActionWorker.perform(%Oban.Job{
                 args: %{
                   "lamp_id" => "aws.ec2.list-instances",
                   "endpoint_id" => "list_instances",
                   "params" => %{"region" => "us-east-1", "state" => "running"},
                   "actor_id" => actor.id,
                   "session_id" => session_id
                 }
               })

      assert_receive {:push_canvas, html}
      assert html =~ "i-0abc1234"
      assert html =~ "t3.micro"
      assert html =~ "us-east-1a"
    end
  end
end
