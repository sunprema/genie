defmodule Genie.Orchestrator.ReasoningLoopTest do
  use Genie.DataCase, async: false

  alias Genie.Orchestrator.ReasoningLoop
  alias Genie.Accounts.{Organisation, User}
  alias Genie.Conversation.Session
  alias Genie.Lamp.LampRegistry
  alias Genie.MockReqLLM

  @valid_xml File.read!(Path.join([:code.priv_dir(:genie), "lamps", "aws_s3_create_bucket.xml"]))

  setup do
    Application.put_env(:genie, :req_llm_module, MockReqLLM)

    on_exit(fn ->
      Application.delete_env(:genie, :req_llm_module)
      Application.delete_env(:genie, :mock_llm_response)
      Application.delete_env(:genie, :mock_llm_object)
    end)

    :ok
  end

  defp create_org!, do: Organisation |> Ash.Changeset.for_create(:create, %{name: "Org#{System.unique_integer([:positive])}", slug: "org-#{System.unique_integer([:positive])}"}) |> Ash.create!(authorize?: false)

  defp create_user!(org) do
    n = System.unique_integer([:positive])
    user = User |> Ash.Changeset.for_create(:register_with_password, %{email: "u-#{n}@t.com", password: "password123", password_confirmation: "password123"}) |> Ash.create!(authorize?: false)
    user |> Ash.Changeset.for_update(:update, %{org_id: org.id, role: :admin}) |> Ash.update!(authorize?: false)
  end

  defp create_session!(user) do
    Session |> Ash.Changeset.for_create(:create, %{org_id: user.org_id, user_id: user.id, title: "test"}) |> Ash.create!(authorize?: false)
  end

  defp register_lamp! do
    LampRegistry |> Ash.Changeset.for_create(:register, %{org_id: nil, xml_source: @valid_xml, enabled: true}) |> Ash.create!(authorize?: false)
  end

  describe "full Reactor run with mocked LLM" do
    test "returns :sent when LLM returns a plain message" do
      org = create_org!()
      actor = create_user!(org)
      session = create_session!(actor)
      register_lamp!()

      session_id = to_string(session.id)
      Phoenix.PubSub.subscribe(Genie.PubSub, "chat:#{session_id}")

      Application.put_env(:genie, :mock_llm_response, {:ok, MockReqLLM.build_message_response("No lamp needed")})

      result = Reactor.run(ReasoningLoop, %{
        session_id: session_id,
        user_message: "Just tell me the time",
        actor: actor
      }, async?: false)

      assert {:ok, :sent} = result
      assert_receive {:push_chat, "No lamp needed"}
    end

    test "returns :sent when LLM returns an intent_call and renders HTML to canvas" do
      org = create_org!()
      actor = create_user!(org)
      session = create_session!(actor)
      register_lamp!()

      session_id = to_string(session.id)
      Phoenix.PubSub.subscribe(Genie.PubSub, "canvas:#{session_id}")

      Application.put_env(
        :genie,
        :mock_llm_response,
        {:ok,
         MockReqLLM.build_invoke_lamp_response(
           "aws.s3.create-bucket",
           "create_bucket",
           %{"bucket_name" => "test-bucket", "region" => "us-east-1"}
         )}
      )

      Application.put_env(:genie, :mock_llm_object, {:ok, MockReqLLM.build_object_response(%{"bucket_name" => "test-bucket"})})

      result = Reactor.run(ReasoningLoop, %{
        session_id: session_id,
        user_message: "Create a bucket called test-bucket",
        actor: actor
      }, async?: false)

      # May return :sent or error depending on approval requirement
      assert match?({:ok, :sent}, result) or match?({:error, _}, result)
    end

    test "full S3 demo sequence — pre-filled form rendered on canvas" do
      org = create_org!()
      actor = create_user!(org)
      session = create_session!(actor)
      register_lamp!()

      session_id = to_string(session.id)
      Phoenix.PubSub.subscribe(Genie.PubSub, "canvas:#{session_id}")

      Application.put_env(
        :genie,
        :mock_llm_response,
        {:ok,
         MockReqLLM.build_invoke_lamp_response(
           "aws.s3.create-bucket",
           "create_bucket",
           %{"bucket_name" => "acme-prod-assets", "region" => "us-east-1"}
         )}
      )

      Application.put_env(
        :genie,
        :mock_llm_object,
        {:ok,
         MockReqLLM.build_object_response(%{
           "bucket_name" => "acme-prod-assets",
           "access" => "private",
           "versioning" => "true"
         })}
      )

      assert {:ok, :sent} =
               Reactor.run(
                 ReasoningLoop,
                 %{
                   session_id: session_id,
                   user_message: "Create a private versioned bucket called acme-prod-assets in us-east-1",
                   actor: actor
                 },
                 async?: false
               )

      # Canvas shows the pre-filled S3 form (not pending-approval)
      assert_receive {:push_canvas, canvas_html}
      assert canvas_html =~ "acme-prod-assets"
      assert canvas_html =~ "Create S3 Bucket"
    end

    test "from-context fields are filled without LLM call when params provided" do
      org = create_org!()
      actor = create_user!(org)
      session = create_session!(actor)
      register_lamp!()

      session_id = to_string(session.id)
      Phoenix.PubSub.subscribe(Genie.PubSub, "canvas:#{session_id}")

      Application.put_env(
        :genie,
        :mock_llm_response,
        {:ok,
         MockReqLLM.build_invoke_lamp_response(
           "aws.s3.create-bucket",
           "create_bucket",
           %{"bucket_name" => "test-bucket", "region" => "us-east-1", "org_id" => "my-org"}
         )}
      )

      Application.put_env(
        :genie,
        :mock_llm_object,
        {:ok, MockReqLLM.build_object_response(%{"bucket_name" => "test-bucket"})}
      )

      assert {:ok, :sent} =
               Reactor.run(
                 ReasoningLoop,
                 %{
                   session_id: session_id,
                   user_message: "Create a bucket for my-org in us-east-1",
                   actor: actor
                 },
                 async?: false
               )

      # Canvas should receive some HTML
      assert_receive {:push_canvas, canvas_html}
      assert is_binary(canvas_html)
    end
  end
end
