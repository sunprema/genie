defmodule Genie.Orchestrator.LlmClientTest do
  use ExUnit.Case, async: false

  alias Genie.Orchestrator.LlmClient
  alias Genie.MockReqLLM
  alias ReqLLM.Context

  setup do
    Application.put_env(:genie, :req_llm_module, MockReqLLM)
    on_exit(fn -> Application.delete_env(:genie, :req_llm_module) end)
    :ok
  end

  defp empty_context, do: Context.new([])

  describe "call/1" do
    test "correctly parses a plain message response" do
      Process.put(:mock_llm_response, {:ok, MockReqLLM.build_message_response("Hello from Genie")})

      assert {:ok, {:message, %{text: "Hello from Genie"}}} =
               LlmClient.call(%{llm_context: empty_context(), tools: []})
    end

    test "correctly parses a tool_call response" do
      response = MockReqLLM.build_tool_call_response("data_aws_ec2_load_regions", %{"region" => "us-east-1"})
      Process.put(:mock_llm_response, {:ok, response})

      assert {:ok, {:tool_call, %{calls: calls}}} =
               LlmClient.call(%{llm_context: empty_context(), tools: []})

      assert [call | _] = calls
      assert call.name == "data_aws_ec2_load_regions"
    end

    test "correctly parses an intent_call response" do
      response =
        MockReqLLM.build_invoke_lamp_response(
          "aws.s3.create-bucket",
          "create_bucket",
          %{"bucket_name" => "test-bucket"}
        )

      Process.put(:mock_llm_response, {:ok, response})

      assert {:ok, {:intent_call, intent}} =
               LlmClient.call(%{llm_context: empty_context(), tools: []})

      assert intent.lamp_id == "aws.s3.create-bucket"
      assert intent.endpoint_id == "create_bucket"
      assert intent.params["bucket_name"] == "test-bucket"
    end

    test "returns error when LLM call fails" do
      Process.put(:mock_llm_response, {:error, :timeout})

      assert {:error, :timeout} =
               LlmClient.call(%{llm_context: empty_context(), tools: []})
    end
  end

  describe "fill/1" do
    test "returns a parsed map of field values" do
      fields = [
        %Genie.Lamp.FieldDef{
          id: "bucket_name",
          type: :text,
          aria_label: "S3 bucket name",
          genie_fill: :infer,
          value: nil
        }
      ]

      Process.put(:mock_llm_object, {:ok, MockReqLLM.build_object_response(%{"bucket_name" => "acme-prod"})})

      assert {:ok, %{"bucket_name" => "acme-prod"}} =
               LlmClient.fill(%{fields: fields, conversation: "Create a bucket called acme-prod"})
    end

    test "returns empty map on error" do
      Process.put(:mock_llm_object, {:error, :timeout})

      assert {:error, :timeout} =
               LlmClient.fill(%{fields: [], conversation: "test"})
    end
  end
end
