defmodule Genie.Lamps.AWS.S3CreateBucketTest do
  use ExUnit.Case, async: true

  alias Genie.Lamp.Handler.Context
  alias Genie.Lamps.AWS.S3CreateBucket

  defp ctx(endpoint_id) do
    %Context{
      lamp_id: "aws.s3.create-bucket",
      endpoint_id: endpoint_id,
      session_id: "t",
      trace_id: "trace-1"
    }
  end

  describe "load_regions" do
    test "returns the shared AWS region list" do
      assert {:ok, regions} = S3CreateBucket.handle_endpoint("load_regions", %{}, ctx("load_regions"))
      assert Enum.any?(regions, &(&1["code"] == "us-east-1"))
    end
  end

  describe "create_bucket" do
    test "echoes bucket_name and region back in the submitting response" do
      {:ok, response} =
        S3CreateBucket.handle_endpoint(
          "create_bucket",
          %{"bucket_name" => "my-bucket-42", "region" => "eu-west-1"},
          ctx("create_bucket")
        )

      assert response["state"] == "submitting"
      assert response["bucket_name"] == "my-bucket-42"
      assert response["region"] == "eu-west-1"
      assert response["console_url"] =~ "my-bucket-42"
    end
  end

  describe "poll_status" do
    test "reports ready with a console_url derived from bucket_name" do
      {:ok, response} =
        S3CreateBucket.handle_endpoint(
          "poll_status",
          %{"bucket_name" => "my-bucket-42"},
          ctx("poll_status")
        )

      assert response["state"] == "ready"
      assert response["status"] == "ready"
      assert response["console_url"] =~ "my-bucket-42"
    end
  end
end
