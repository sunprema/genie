defmodule Genie.Bridge do
  @moduledoc """
  Secure proxy between the Cockpit and all lamp backends.
  The browser never calls a lamp backend directly.
  """

  require OpenTelemetry.Tracer, as: Tracer

  alias Genie.Bridge.VaultClient
  alias Genie.Lamp.{EndpointDef, FieldDef, LampDefinition, LampRenderer}
  alias Genie.Lamp.Handler.Context

  @type request :: %{
          required(:lamp) => LampDefinition.t(),
          required(:endpoint_id) => String.t(),
          required(:params) => map(),
          required(:session_id) => String.t() | nil,
          optional(:actor) => struct() | nil,
          optional(:org_id) => String.t() | nil
        }

  @spec execute(request()) :: {:ok, String.t()} | {:error, term()}
  def execute(%{lamp: lamp, endpoint_id: endpoint_id, params: params} = req) do
    with {:ok, endpoint} <- find_endpoint(lamp, endpoint_id),
         {:ok, response} <- invoke_endpoint(lamp, endpoint, params, req) do
      html = render_status_html(lamp, response)
      {:ok, html}
    else
      {:error, reason} -> {:error, sanitize_error(reason)}
    end
  end

  @spec fetch_options(LampDefinition.t(), FieldDef.t()) ::
          {:ok, [{String.t(), String.t()}]} | {:error, term()}
  def fetch_options(%LampDefinition{} = lamp, %FieldDef{} = field) do
    with {:ok, endpoint} <- find_endpoint(lamp, field.options_from),
         {:ok, items} <- fetch_options_items(lamp, endpoint) do
      value_key = field.options_value_key || "value"
      label_key = field.options_label_key || "label"
      pairs = Enum.map(items, fn item -> {Map.get(item, value_key), Map.get(item, label_key)} end)
      {:ok, pairs}
    end
  end

  @spec execute_tool(request()) :: {:ok, map()} | {:error, term()}
  def execute_tool(%{lamp: lamp, endpoint_id: endpoint_id, params: params} = req) do
    with {:ok, endpoint} <- find_endpoint(lamp, endpoint_id),
         {:ok, response} <- invoke_endpoint(lamp, endpoint, params, req) do
      {:ok, response}
    else
      {:error, reason} -> {:error, sanitize_error(reason)}
    end
  end

  # --- Dispatch: inline vs remote ---

  defp invoke_endpoint(lamp, endpoint, params, req) do
    if inline?(lamp) do
      call_inline(lamp, endpoint, params, req)
    else
      session_id = Map.get(req, :session_id)

      with {:ok, token} <- VaultClient.get_scoped_token(lamp.meta.auth_scheme || "bearer") do
        call_endpoint(lamp, endpoint, params, token, session_id)
      end
    end
  end

  defp fetch_options_items(lamp, endpoint) do
    if inline?(lamp) do
      call_inline_options(lamp, endpoint)
    else
      with {:ok, token} <- VaultClient.get_scoped_token(lamp.meta.auth_scheme || "bearer") do
        get_options(lamp, endpoint, token)
      end
    end
  end

  defp inline?(%LampDefinition{meta: %{runtime: "inline"}}), do: true
  defp inline?(_), do: false

  defp call_inline(lamp, endpoint, params, req) do
    Tracer.with_span "Genie.bridge.inline",
      attributes: [
        {"lamp_id", lamp.id},
        {"endpoint_id", endpoint.id},
        {"runtime", "inline"}
      ] do
      started_at = System.monotonic_time(:millisecond)

      with {:ok, handler} <- resolve_handler(lamp.meta.handler),
           ctx <- build_context(lamp, endpoint, req, started_at),
           {:ok, response} <- invoke_handler(handler, endpoint.id, params, ctx) do
        Tracer.set_attributes([
          {"duration_ms", System.monotonic_time(:millisecond) - started_at}
        ])

        case validate_response_shape(endpoint, response) do
          :ok -> {:ok, response}
          {:error, _} = err -> err
        end
      end
    end
  end

  defp call_inline_options(lamp, endpoint) do
    started_at = System.monotonic_time(:millisecond)

    with {:ok, handler} <- resolve_handler(lamp.meta.handler),
         ctx <- build_context(lamp, endpoint, %{}, started_at) do
      cond do
        function_exported?(handler, :handle_options, 2) ->
          handler.handle_options(endpoint.id, ctx)

        function_exported?(handler, :handle_endpoint, 3) ->
          case handler.handle_endpoint(endpoint.id, %{}, ctx) do
            {:ok, list} when is_list(list) -> {:ok, list}
            {:ok, _other} -> {:error, :handler_expected_list_response}
            err -> err
          end

        true ->
          {:error, {:handler_missing_callback, lamp.meta.handler}}
      end
    end
  end

  defp invoke_handler(handler, endpoint_id, params, ctx) do
    handler.handle_endpoint(endpoint_id, params, ctx)
  rescue
    e -> {:error, {:handler_crash, Exception.message(e)}}
  end

  defp resolve_handler(nil), do: {:error, :handler_not_declared}
  defp resolve_handler(""), do: {:error, :handler_not_declared}

  defp resolve_handler(name) when is_binary(name) do
    module = Module.concat([name])

    if Code.ensure_loaded?(module) and function_exported?(module, :handle_endpoint, 3) do
      {:ok, module}
    else
      {:error, {:handler_not_found, name}}
    end
  end

  defp build_context(lamp, endpoint, req, started_at) do
    %Context{
      lamp_id: lamp.id,
      endpoint_id: endpoint.id,
      session_id: Map.get(req, :session_id),
      trace_id: current_otel_trace_id(),
      actor: Map.get(req, :actor),
      org_id: Map.get(req, :org_id),
      lamp: lamp,
      endpoint: endpoint,
      started_at: started_at,
      metadata: Map.get(req, :metadata, %{})
    }
  end

  defp validate_response_shape(%EndpointDef{response_keys: keys}, response)
       when is_list(keys) and keys != [] and is_map(response) do
    if Application.get_env(:genie, :inline_strict_responses, true) do
      missing =
        keys
        |> Enum.filter(& &1.required)
        |> Enum.reject(fn k -> Map.has_key?(response, k.name) end)
        |> Enum.map(& &1.name)

      if missing == [] do
        :ok
      else
        {:error, {:missing_required_response_keys, missing}}
      end
    else
      :ok
    end
  end

  defp validate_response_shape(_endpoint, _response), do: :ok

  defp find_endpoint(%LampDefinition{endpoints: endpoints}, endpoint_id) do
    case Enum.find(endpoints || [], &(&1.id == endpoint_id)) do
      nil -> {:error, :undeclared_endpoint}
      endpoint -> {:ok, endpoint}
    end
  end

  defp call_endpoint(lamp, endpoint, params, token, session_id) do
    url = build_url(lamp.meta.base_url, endpoint.path, params)
    timeout = endpoint.timeout_ms || lamp.meta.timeout_ms || 10_000
    headers = build_headers(token, lamp.meta.auth_scheme, session_id)
    req_opts = base_req_options()

    log_request(lamp.id, endpoint.id, url, params)

    Tracer.with_span "Genie.bridge.request", %{
      attributes: [{"lamp_id", lamp.id}, {"endpoint_id", endpoint.id}]
    } do
      start_ms = System.monotonic_time(:millisecond)

      result =
        case String.upcase(endpoint.method || "POST") do
          "GET" ->
            Req.get(url, [headers: headers, receive_timeout: timeout] ++ req_opts)

          _ ->
            Req.post(url, [json: params, headers: headers, receive_timeout: timeout] ++ req_opts)
        end

      duration_ms = System.monotonic_time(:millisecond) - start_ms

      case result do
        {:ok, %{status: status, body: body}} when status in 200..299 ->
          Tracer.set_attributes([{"status_code", status}, {"duration_ms", duration_ms}])
          log_response(lamp.id, endpoint.id, status, body)
          {:ok, body}

        {:ok, %{status: status, body: body}} ->
          Tracer.set_attributes([{"status_code", status}, {"duration_ms", duration_ms}])
          log_response(lamp.id, endpoint.id, status, body)
          {:error, {:http_error, status}}

        {:error, reason} ->
          Tracer.set_attributes([{"status_code", 0}, {"duration_ms", duration_ms}])
          log_response(lamp.id, endpoint.id, :error, reason)
          {:error, reason}
      end
    end
  end

  defp get_options(lamp, endpoint, token) do
    url = build_url(lamp.meta.base_url, endpoint.path, %{})
    timeout = endpoint.timeout_ms || lamp.meta.timeout_ms || 10_000
    headers = build_headers(token, lamp.meta.auth_scheme, nil)
    req_opts = base_req_options()

    case Req.get(url, [headers: headers, receive_timeout: timeout] ++ req_opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 and is_list(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_url(base_url, path, params) do
    interpolated = interpolate_path(path, params)
    base = String.trim_trailing(base_url || "", "/")
    prefix = if String.starts_with?(interpolated, "/"), do: "", else: "/"
    base <> prefix <> interpolated
  end

  defp interpolate_path(path, params) do
    Regex.replace(~r/\{([^}]+)\}/, path || "", fn _full, key ->
      to_string(Map.get(params, key, ""))
    end)
  end

  defp build_headers(token, auth_scheme, session_id) do
    trace_id = current_otel_trace_id()

    auth_header =
      case auth_scheme do
        "api-key" -> {"X-Api-Key", token}
        _ -> {"Authorization", "Bearer #{token}"}
      end

    headers = [
      auth_header,
      {"X-Genie-Trace-Id", trace_id},
      {"Content-Type", "application/json"}
    ]

    if session_id do
      [{"X-Genie-Session", session_id} | headers]
    else
      headers
    end
  end

  defp current_otel_trace_id do
    case :otel_tracer.current_span_ctx() do
      :undefined ->
        :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

      span_ctx ->
        trace_id = :otel_span.trace_id(span_ctx)

        if trace_id == 0 do
          :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
        else
          trace_id
          |> Integer.to_string(16)
          |> String.downcase()
          |> String.pad_leading(32, "0")
        end
    end
  end

  defp render_status_html(lamp, response) when is_map(response) do
    {:safe, html_data} = LampRenderer.render_status(lamp, response)
    IO.iodata_to_binary(html_data)
  end

  defp render_status_html(_lamp, _response), do: ""

  defp base_req_options do
    Application.get_env(:genie, :bridge_req_options, [])
  end

  defp log_request(lamp_id, endpoint_id, url, params) do
    if Application.get_env(:genie, :bridge_log_requests, false) do
      require Logger
      Logger.debug("[Bridge] request lamp=#{lamp_id} endpoint=#{endpoint_id} url=#{url} params=#{inspect(params)}")
    end
  end

  defp log_response(lamp_id, endpoint_id, status, body) do
    if Application.get_env(:genie, :bridge_log_requests, false) do
      require Logger
      Logger.debug("[Bridge] response lamp=#{lamp_id} endpoint=#{endpoint_id} status=#{inspect(status)} body=#{inspect(body)}")
    end
  end

  defp sanitize_error(:undeclared_endpoint), do: :undeclared_endpoint

  defp sanitize_error({:http_error, status}), do: {:http_error, status}

  # Pass through inline-runtime errors verbatim so developers can diagnose
  # handler-side issues (crashes, schema mismatches, resolution failures)
  # without grepping the logs by trace_id.
  defp sanitize_error({:handler_crash, _} = reason), do: reason
  defp sanitize_error({:handler_not_found, _} = reason), do: reason
  defp sanitize_error(:handler_not_declared), do: :handler_not_declared
  defp sanitize_error({:handler_missing_callback, _} = reason), do: reason
  defp sanitize_error({:missing_required_response_keys, _} = reason), do: reason
  defp sanitize_error(:handler_expected_list_response), do: :handler_expected_list_response

  defp sanitize_error(_reason) do
    trace_id = current_otel_trace_id()
    {:service_unavailable, trace_id}
  end
end
