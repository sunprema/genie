defmodule GenieWeb.MockBackendController do
  @moduledoc "Dev-only mock backend that simulates lamp API endpoints."
  use GenieWeb, :controller

  def regions(conn, _params) do
    json(conn, [
      %{code: "us-east-1", name: "US East (N. Virginia)"},
      %{code: "us-east-2", name: "US East (Ohio)"},
      %{code: "us-west-1", name: "US West (N. California)"},
      %{code: "us-west-2", name: "US West (Oregon)"},
      %{code: "eu-west-1", name: "EU (Ireland)"},
      %{code: "eu-central-1", name: "EU (Frankfurt)"},
      %{code: "ap-southeast-1", name: "Asia Pacific (Singapore)"}
    ])
  end

  def pagerduty_incidents(conn, _params) do
    json(conn, %{
      state: "ready",
      count: 3,
      incidents: [
        %{
          title: "Database CPU spike — payments-db",
          severity: "high",
          service: "payments-db",
          status: "triggered",
          created_at: "2 min ago"
        },
        %{
          title: "Elevated error rate — checkout API",
          severity: "medium",
          service: "checkout-api",
          status: "acknowledged",
          created_at: "11 min ago"
        },
        %{
          title: "Memory pressure — auth-service pods",
          severity: "critical",
          service: "auth-service",
          status: "triggered",
          created_at: "just now"
        }
      ]
    })
  end

  def create_s3_bucket(conn, params) do
    bucket_name = Map.get(params, "bucket_name", "my-bucket")
    region = Map.get(params, "region", "us-east-1")

    json(conn, %{
      state: "submitting",
      status: "creating",
      bucket_name: bucket_name,
      region: region,
      console_url: "https://s3.console.aws.amazon.com/s3/buckets/#{bucket_name}"
    })
  end

  def s3_bucket_status(conn, %{"bucket_name" => bucket_name} = _params) do
    json(conn, %{
      status: "ready",
      state: "ready",
      bucket_name: bucket_name,
      console_url: "https://s3.console.aws.amazon.com/s3/buckets/#{bucket_name}"
    })
  end

  def github_pull_requests(conn, params) do
    repo = Map.get(params, "repo", "acme/platform")
    state_filter = Map.get(params, "state", "open")

    pull_requests = [
      %{
        number: "42",
        title: "Add rate limiting to API gateway",
        author: "alice",
        state: "open",
        base: "main",
        head: "feature/rate-limiting",
        updated_at: "2 hours ago"
      },
      %{
        number: "38",
        title: "Fix memory leak in worker pool",
        author: "bob",
        state: "open",
        base: "main",
        head: "fix/worker-memory-leak",
        updated_at: "1 day ago"
      },
      %{
        number: "35",
        title: "Upgrade Elixir to 1.17",
        author: "carol",
        state: "closed",
        base: "main",
        head: "chore/elixir-upgrade",
        updated_at: "3 days ago"
      }
    ]

    filtered =
      if state_filter == "all" do
        pull_requests
      else
        Enum.filter(pull_requests, &(&1.state == state_filter))
      end

    json(conn, %{state: "ready-list", repo: repo, pull_requests: filtered})
  end

  def github_pr_detail(conn, %{"id" => pr_number} = _params) do
    json(conn, %{
      state: "ready-detail",
      pull_request: %{
        number: pr_number,
        title: "Add rate limiting to API gateway",
        author: "alice",
        state: "open",
        base: "main",
        head: "feature/rate-limiting",
        body: "Implements token-bucket rate limiting at the API gateway layer to prevent abuse.",
        url: "https://github.com/acme/platform/pull/#{pr_number}",
        updated_at: "2 hours ago"
      }
    })
  end

  def ec2_instances(conn, params) do
    region = Map.get(params, "region", "us-east-1")
    state_filter = Map.get(params, "state", "running")

    all_instances = [
      %{
        instance_id: "i-0a1b2c3d4e5f6a7b8",
        instance_type: "t3.micro",
        state: "running",
        availability_zone: "#{region}a",
        public_ip: "54.210.12.34"
      },
      %{
        instance_id: "i-0b2c3d4e5f6a7b8c9",
        instance_type: "m5.large",
        state: "running",
        availability_zone: "#{region}b",
        public_ip: "18.234.56.78"
      },
      %{
        instance_id: "i-0c3d4e5f6a7b8c9d0",
        instance_type: "t3.small",
        state: "stopped",
        availability_zone: "#{region}a",
        public_ip: nil
      }
    ]

    instances =
      if state_filter == "all" do
        all_instances
      else
        Enum.filter(all_instances, &(&1.state == state_filter))
      end

    json(conn, %{state: "ready", region: region, instances: instances})
  end
end
