defmodule Genie.Bridge.Sanitizer do
  @moduledoc "Strict HTML allowlist sanitizer for lamp backend responses."

  @dangerous_elements ~w[script style iframe form]

  @allowed_elements MapSet.new(~w[
    div span p strong em ul ol li
    table thead tbody tr th td a code pre
  ])

  @allowed_attrs MapSet.new(~w[class id role href])

  # Matches: name="val", name='val', name (boolean)
  # Group 1 = name, Group 2 = raw value-with-quotes (if present)
  @attr_re ~r/\s+([a-zA-Z][a-zA-Z0-9:_-]*)(?:\s*=\s*("[^"]*"|'[^']*'|[^\s>]*))?/

  @spec sanitize(String.t()) :: String.t()
  def sanitize(html) when is_binary(html) do
    html
    |> strip_dangerous_elements()
    |> strip_self_closing_inputs()
    |> process_tags()
  end

  defp strip_dangerous_elements(html) do
    Enum.reduce(@dangerous_elements, html, fn tag, acc ->
      Regex.replace(~r/<#{tag}(?:\s[^>]*)?>.*?<\/#{tag}>/si, acc, "")
    end)
  end

  defp strip_self_closing_inputs(html) do
    Regex.replace(~r/<input(?:\s[^>]*)?\/?>/i, html, "")
  end

  defp process_tags(html) do
    Regex.replace(
      ~r/<(\/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>/,
      html,
      &replace_tag/4
    )
  end

  defp replace_tag(_full, slash, tag, attrs_str) do
    tag_lower = String.downcase(tag)

    if MapSet.member?(@allowed_elements, tag_lower) do
      build_allowed_tag(tag_lower, slash, attrs_str)
    else
      ""
    end
  end

  defp build_allowed_tag(tag_lower, "/", _attrs_str), do: "</#{tag_lower}>"

  defp build_allowed_tag(tag_lower, _slash, attrs_str) do
    "<#{tag_lower}#{filter_attributes(attrs_str)}>"
  end

  defp filter_attributes(attrs_str) do
    @attr_re
    |> Regex.scan(attrs_str)
    |> Enum.flat_map(&safe_attribute/1)
    |> Enum.join("")
  end

  defp safe_attribute(groups) do
    name = Enum.at(groups, 1, "")
    raw_value = Enum.at(groups, 2)
    name_lower = String.downcase(name)
    value = raw_value && unquote_attr(raw_value)

    cond do
      String.starts_with?(name_lower, "on") -> []
      allowed_attr?(name_lower) -> safe_href_attr(name_lower, value)
      true -> []
    end
  end

  defp safe_href_attr(name, value) do
    if dangerous_href?(name, value), do: [], else: format_attr(name, value)
  end

  defp unquote_attr("\"" <> rest), do: String.trim_trailing(rest, "\"")
  defp unquote_attr("'" <> rest), do: String.trim_trailing(rest, "'")
  defp unquote_attr(v), do: v

  defp allowed_attr?(name) do
    MapSet.member?(@allowed_attrs, name) or
      String.starts_with?(name, "aria-") or
      String.starts_with?(name, "data-lamp-")
  end

  defp dangerous_href?("href", value) when is_binary(value) do
    lower = String.downcase(String.trim(value))
    String.starts_with?(lower, "javascript:") or String.starts_with?(lower, "data:")
  end

  defp dangerous_href?(_, _), do: false

  defp format_attr(name, nil), do: [" #{name}"]
  defp format_attr(name, value), do: [" #{name}=\"#{html_encode(value)}\""]

  defp html_encode(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
