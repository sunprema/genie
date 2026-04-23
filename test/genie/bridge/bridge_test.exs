defmodule Genie.BridgeTest do
  use ExUnit.Case, async: true

  alias Genie.Bridge
  alias Genie.Lamp.{EndpointDef, FieldDef, LampDefinition, MetaDef, StatusTemplate}

  @base_url "https://api.example.com"

  defp build_lamp(opts \\ []) do
    endpoints = Keyword.get(opts, :endpoints, [
      %EndpointDef{
        id: "create_item",
        method: "POST",
        path: "/items",
        trigger: :"on-submit",
        timeout_ms: 5000
      }
    ])

    status_templates = Keyword.get(opts, :status_templates, [
      %StatusTemplate{
        state: "ready",
        fields: [
          %FieldDef{
            id: "result_msg",
            type: :banner,
            aria_label: "Item created successfully",
            style: "success"
          }
        ]
      }
    ])

    %LampDefinition{
      id: "test.svc.create-item",
      version: "1.0",
      category: "compute",
      vendor: "test",
      meta: %MetaDef{
        title: "Test Lamp",
        base_url: @base_url,
        auth_scheme: "bearer",
        timeout_ms: 10_000
      },
      endpoints: endpoints,
      fields: [],
      groups: [],
      actions: [],
      status_templates: status_templates
    }
  end

  describe "execute/1 — endpoint validation" do
    test "returns {:error, :undeclared_endpoint} for unknown endpoint_id" do
      lamp = build_lamp()

      result =
        Bridge.execute(%{
          lamp: lamp,
          endpoint_id: "nonexistent_endpoint",
          params: %{},
          session_id: "sess_123"
        })

      assert result == {:error, :undeclared_endpoint}
    end

    test "returns {:ok, html} for a declared endpoint" do
      lamp = build_lamp()

      Req.Test.stub(Genie.Bridge, fn conn ->
        Req.Test.json(conn, %{"state" => "ready", "msg" => "done"})
      end)

      assert {:ok, html} =
               Bridge.execute(%{
                 lamp: lamp,
                 endpoint_id: "create_item",
                 params: %{"name" => "test"},
                 session_id: "sess_abc"
               })

      assert is_binary(html)
    end
  end

  describe "execute/1 — path interpolation" do
    test "interpolates path params from the params map" do
      lamp =
        build_lamp(
          endpoints: [
            %EndpointDef{
              id: "get_item",
              method: "GET",
              path: "/items/{item_id}",
              trigger: :"on-submit",
              timeout_ms: 5000
            }
          ]
        )

      Req.Test.stub(Genie.Bridge, fn conn ->
        assert String.ends_with?(conn.request_path, "/items/abc-123")
        Req.Test.json(conn, %{"state" => "ready"})
      end)

      Bridge.execute(%{
        lamp: lamp,
        endpoint_id: "get_item",
        params: %{"item_id" => "abc-123"},
        session_id: "sess_1"
      })
    end
  end

  describe "execute/1 — headers" do
    test "includes X-Genie-Session header" do
      lamp = build_lamp()

      Req.Test.stub(Genie.Bridge, fn conn ->
        session_header = Plug.Conn.get_req_header(conn, "x-genie-session")
        assert session_header == ["sess_xyz"]
        Req.Test.json(conn, %{"state" => "ready"})
      end)

      Bridge.execute(%{
        lamp: lamp,
        endpoint_id: "create_item",
        params: %{},
        session_id: "sess_xyz"
      })
    end

    test "includes X-Genie-Trace-Id header" do
      lamp = build_lamp()

      Req.Test.stub(Genie.Bridge, fn conn ->
        trace_header = Plug.Conn.get_req_header(conn, "x-genie-trace-id")
        assert trace_header != []
        assert String.length(hd(trace_header)) == 32
        Req.Test.json(conn, %{"state" => "ready"})
      end)

      Bridge.execute(%{
        lamp: lamp,
        endpoint_id: "create_item",
        params: %{},
        session_id: "sess_1"
      })
    end
  end

  describe "fetch_options/2" do
    test "maps response using configured value and label keys" do
      lamp =
        build_lamp(
          endpoints: [
            %EndpointDef{
              id: "load_regions",
              method: "GET",
              path: "/regions",
              trigger: :"on-load",
              timeout_ms: 5000
            }
          ]
        )

      field = %FieldDef{
        id: "region",
        type: :select,
        aria_label: "AWS Region",
        options_from: "load_regions",
        options_value_key: "region_id",
        options_label_key: "region_name"
      }

      Req.Test.stub(Genie.Bridge, fn conn ->
        Req.Test.json(conn, [
          %{"region_id" => "us-east-1", "region_name" => "US East (N. Virginia)"},
          %{"region_id" => "eu-west-1", "region_name" => "EU (Ireland)"}
        ])
      end)

      assert {:ok, pairs} = Bridge.fetch_options(lamp, field)
      assert {"us-east-1", "US East (N. Virginia)"} in pairs
      assert {"eu-west-1", "EU (Ireland)"} in pairs
    end

    test "returns undeclared_endpoint error when options_from not in endpoints" do
      lamp = build_lamp()

      field = %FieldDef{
        id: "region",
        type: :select,
        aria_label: "Region",
        options_from: "load_regions",
        options_value_key: "id",
        options_label_key: "name"
      }

      assert {:error, :undeclared_endpoint} = Bridge.fetch_options(lamp, field)
    end
  end
end
