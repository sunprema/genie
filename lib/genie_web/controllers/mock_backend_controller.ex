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

  @process_limit 50

  def elixir_processes(conn, params) do
    filter = Map.get(params, "filter", "all")

    processes =
      Process.list()
      |> Enum.map(&process_summary/1)
      |> Enum.reject(&is_nil/1)
      |> filter_processes(filter)
      |> Enum.sort_by(& &1.memory_kb, :desc)
      |> Enum.take(@process_limit)

    json(conn, %{state: "ready-list", filter: filter, processes: processes})
  end

  def elixir_process_detail(conn, %{"pid" => pid_str}) do
    case decode_pid(pid_str) do
      {:ok, pid} ->
        case process_detail(pid) do
          nil ->
            json(conn, %{state: "failed", error_message: "Process #{pid_str} no longer exists"})

          detail ->
            json(conn, %{state: "ready-detail", process: detail})
        end

      :error ->
        json(conn, %{state: "failed", error_message: "Invalid PID: #{pid_str}"})
    end
  end

  defp process_summary(pid) do
    case Process.info(pid, [:registered_name, :status, :memory, :message_queue_len, :current_function]) do
      nil ->
        nil

      info ->
        {m, f, a} = info[:current_function]

        %{
          pid: pid_to_str(pid),
          registered_name: format_name(info[:registered_name]),
          status: to_string(info[:status]),
          memory_kb: div(info[:memory], 1024),
          message_queue_len: info[:message_queue_len],
          current_function: "#{m}.#{f}/#{a}"
        }
    end
  end

  defp process_detail(pid) do
    keys = [
      :registered_name,
      :current_function,
      :initial_call,
      :status,
      :memory,
      :heap_size,
      :stack_size,
      :message_queue_len,
      :reductions,
      :links,
      :monitors
    ]

    case Process.info(pid, keys) do
      nil ->
        nil

      info ->
        %{
          pid: pid_to_str(pid),
          registered_name: format_name(info[:registered_name]),
          current_function: format_mfa(info[:current_function]),
          initial_call: format_mfa(info[:initial_call]),
          status: to_string(info[:status]),
          memory_kb: div(info[:memory], 1024),
          heap_size_words: info[:heap_size],
          stack_size_words: info[:stack_size],
          message_queue_len: info[:message_queue_len],
          reductions: info[:reductions],
          links: format_pids(info[:links]),
          monitors: format_monitors(info[:monitors])
        }
    end
  end

  defp filter_processes(processes, "named") do
    Enum.filter(processes, &(&1.registered_name != ""))
  end

  defp filter_processes(processes, "application") do
    app_pids =
      case :application.get_supervisor(:genie) do
        {:ok, sup_pid} -> collect_supervisor_pids(sup_pid, MapSet.new())
        _ -> MapSet.new()
      end

    Enum.filter(processes, &MapSet.member?(app_pids, &1.pid))
  end

  defp filter_processes(processes, _), do: processes

  defp collect_supervisor_pids(sup_pid, acc) do
    pid_str = pid_to_str(sup_pid)

    if MapSet.member?(acc, pid_str) do
      acc
    else
      acc = MapSet.put(acc, pid_str)

      sup_pid
      |> Supervisor.which_children()
      |> Enum.reduce(acc, fn
        {_, child_pid, :supervisor, _}, acc when is_pid(child_pid) ->
          collect_supervisor_pids(child_pid, acc)

        {_, child_pid, _, _}, acc when is_pid(child_pid) ->
          MapSet.put(acc, pid_to_str(child_pid))

        _, acc ->
          acc
      end)
    end
  end

  defp pid_to_str(pid) do
    pid |> inspect() |> String.replace_prefix("#PID<", "") |> String.replace_suffix(">", "")
  end

  defp decode_pid(str) do
    pid = :erlang.list_to_pid(~c"<#{str}>")
    {:ok, pid}
  rescue
    _ -> :error
  end

  defp format_name([]), do: ""
  defp format_name(nil), do: ""
  defp format_name(name) when is_atom(name), do: to_string(name)

  defp format_mfa({m, f, a}), do: "#{m}.#{f}/#{a}"
  defp format_mfa(nil), do: ""

  defp format_pids(pids), do: pids |> Enum.map(&pid_to_str/1) |> Enum.join(", ")

  defp format_monitors(monitors) do
    monitors
    |> Enum.map(fn
      {:process, pid} when is_pid(pid) -> pid_to_str(pid)
      {:process, name} when is_atom(name) -> to_string(name)
      {:port, port} -> inspect(port)
      other -> inspect(other)
    end)
    |> Enum.join(", ")
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
