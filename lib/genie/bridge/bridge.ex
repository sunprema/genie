defmodule Genie.Bridge do
  @moduledoc """
  Secure proxy between the Cockpit and all lamp backends.
  The browser never calls a lamp backend directly.
  """

  alias Genie.Bridge.VaultClient
  alias Genie.Lamp.{FieldDef, LampDefinition, LampRenderer}

  @type request :: %{
          required(:lamp) => LampDefinition.t(),
          required(:endpoint_id) => String.t(),
          required(:params) => map(),
          required(:session_id) => String.t()
        }

  @spec execute(request()) :: {:ok, String.t()} | {:error, term()}
  def execute(%{lamp: lamp, endpoint_id: endpoint_id, params: params, session_id: session_id}) do
    with {:ok, endpoint} <- find_endpoint(lamp, endpoint_id),
         {:ok, token} <- VaultClient.get_scoped_token(lamp.meta.auth_scheme || "bearer"),
         {:ok, response} <- call_endpoint(lamp, endpoint, params, token, session_id) do
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
         {:ok, token} <- VaultClient.get_scoped_token(lamp.meta.auth_scheme || "bearer"),
         {:ok, items} <- get_options(lamp, endpoint, token) do
      value_key = field.options_value_key || "value"
      label_key = field.options_label_key || "label"
      pairs = Enum.map(items, fn item -> {Map.get(item, value_key), Map.get(item, label_key)} end)
      {:ok, pairs}
    end
  end

  @spec execute_tool(request()) :: {:ok, map()} | {:error, term()}
  def execute_tool(%{lamp: lamp, endpoint_id: endpoint_id, params: params, session_id: session_id}) do
    with {:ok, endpoint} <- find_endpoint(lamp, endpoint_id),
         {:ok, token} <- VaultClient.get_scoped_token(lamp.meta.auth_scheme || "bearer"),
         {:ok, response} <- call_endpoint(lamp, endpoint, params, token, session_id) do
      {:ok, response}
    else
      {:error, reason} -> {:error, sanitize_error(reason)}
    end
  end

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

    result =
      case String.upcase(endpoint.method || "POST") do
        "GET" ->
          Req.get(url, [headers: headers, receive_timeout: timeout] ++ req_opts)

        _ ->
          Req.post(url, [json: params, headers: headers, receive_timeout: timeout] ++ req_opts)
      end

    case result do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        log_response(lamp.id, endpoint.id, status, body)
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        log_response(lamp.id, endpoint.id, status, body)
        {:error, {:http_error, status}}

      {:error, reason} ->
        log_response(lamp.id, endpoint.id, :error, reason)
        {:error, reason}
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
    trace_id = generate_trace_id()

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

  defp generate_trace_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
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

  defp sanitize_error(_reason) do
    trace_id = generate_trace_id()
    {:service_unavailable, trace_id}
  end
end
