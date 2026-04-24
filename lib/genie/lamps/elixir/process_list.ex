defmodule Genie.Lamps.Elixir.ProcessList do
  @moduledoc """
  Inline handler for the `elixir.process.list` lamp. Introspects the running
  BEAM via `Process.list/0` and `Process.info/2` — no HTTP dependency.
  """

  use Genie.Lamp.Handler, lamp_id: "elixir.process.list"

  @process_limit 50

  @endpoint "list_processes"
  def handle_endpoint("list_processes", params, _ctx) do
    filter = Map.get(params, "filter", "all")

    processes =
      Process.list()
      |> Enum.map(&process_summary/1)
      |> Enum.reject(&is_nil/1)
      |> filter_processes(filter)
      |> Enum.sort_by(& &1.memory_kb, :desc)
      |> Enum.take(@process_limit)

    {:ok, %{"state" => "ready-list", "filter" => filter, "processes" => processes}}
  end

  @endpoint "fetch_process"
  def handle_endpoint("fetch_process", %{"id" => pid_str}, _ctx) do
    case decode_pid(pid_str) do
      {:ok, pid} ->
        case process_detail(pid) do
          nil ->
            {:ok,
             %{
               "state" => "failed",
               "error_message" => "Process #{pid_str} no longer exists"
             }}

          detail ->
            {:ok, %{"state" => "ready-detail", "process" => detail}}
        end

      :error ->
        {:ok, %{"state" => "failed", "error_message" => "Invalid PID: #{pid_str}"}}
    end
  end

  defp process_summary(pid) do
    keys = [:registered_name, :status, :memory, :message_queue_len, :current_function]

    case Process.info(pid, keys) do
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
end
