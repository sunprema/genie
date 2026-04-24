defmodule Genie.Lamps.AWS.S3CreateBucket do
  @moduledoc """
  Inline handler for the `aws.s3.create-bucket` lamp. Serves demo data for now
  — the `create_bucket` endpoint returns immediately with a submitting state,
  and `poll_status` reports ready on the first poll.
  """

  use Genie.Lamp.Handler, lamp_id: "aws.s3.create-bucket"

  alias Genie.Lamps.AWS.Regions

  @endpoint "load_regions"
  def handle_endpoint("load_regions", _params, _ctx), do: {:ok, Regions.list()}

  @endpoint "create_bucket"
  def handle_endpoint("create_bucket", params, _ctx) do
    bucket_name = Map.get(params, "bucket_name", "my-bucket")
    region = Map.get(params, "region", "us-east-1")

    {:ok,
     %{
       "state" => "submitting",
       "bucket_name" => bucket_name,
       "region" => region,
       "console_url" => console_url(bucket_name)
     }}
  end

  @endpoint "poll_status"
  def handle_endpoint("poll_status", params, _ctx) do
    bucket_name = Map.get(params, "bucket_name", "my-bucket")

    {:ok,
     %{
       "state" => "ready",
       "status" => "ready",
       "bucket_name" => bucket_name,
       "console_url" => console_url(bucket_name)
     }}
  end

  defp console_url(bucket_name),
    do: "https://s3.console.aws.amazon.com/s3/buckets/#{bucket_name}"
end
