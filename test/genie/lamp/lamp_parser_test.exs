defmodule Genie.Lamp.LampParserTest do
  use ExUnit.Case, async: true

  alias Genie.Lamp.{
    ActionDef,
    EndpointDef,
    GroupDef,
    LampParser,
    MetaDef,
    OptionDef,
    StatusTemplate
  }

  @s3_xml File.read!(Path.join(:code.priv_dir(:genie), "lamps/aws_s3_create_bucket.xml"))

  describe "parse/1 with aws_s3_create_bucket.xml" do
    setup do
      {:ok, defn} = LampParser.parse(@s3_xml)
      %{defn: defn}
    end

    test "populates top-level lamp attributes", %{defn: defn} do
      assert defn.id == "aws.s3.create-bucket"
      assert defn.version == "1.0"
      assert defn.category == "storage"
      assert defn.vendor == "aws"
    end

    test "populates meta", %{defn: %{meta: meta}} do
      assert %MetaDef{} = meta
      assert meta.title == "AWS S3 Bucket Creator"
      assert meta.icon == "aws-s3"
      assert meta.tags == "aws,storage,s3,bucket"
      assert meta.requires_approval == true
      assert meta.destructive == false
      assert meta.audit == true
      assert meta.base_url == "https://api.partner.com/genie"
      assert meta.auth_scheme == "bearer"
      assert meta.timeout_ms == 10_000
    end

    test "populates all three endpoints", %{defn: %{endpoints: endpoints}} do
      assert length(endpoints) == 3
      ids = Enum.map(endpoints, & &1.id)
      assert "load_regions" in ids
      assert "create_bucket" in ids
      assert "poll_status" in ids
    end

    test "load_regions endpoint has correct attributes", %{defn: %{endpoints: endpoints}} do
      ep = Enum.find(endpoints, &(&1.id == "load_regions"))
      assert %EndpointDef{} = ep
      assert ep.method == "GET"
      assert ep.path == "/aws/regions"
      assert ep.trigger == :on_load
      assert ep.fills_field == "region"
    end

    test "poll_status endpoint has poll attributes", %{defn: %{endpoints: endpoints}} do
      ep = Enum.find(endpoints, &(&1.id == "poll_status"))
      assert ep.poll_interval_ms == 2000
      assert ep.poll_until == "status=ready|status=failed"
      assert ep.timeout_ms == 60_000
    end

    test "parses all form fields", %{defn: %{fields: fields}} do
      ids = Enum.map(fields, & &1.id)
      assert "region" in ids
      assert "bucket_name" in ids
      assert "access" in ids
      assert "versioning" in ids
      assert "org_id" in ids
      assert "encryption_type" in ids
      assert "kms_key_id" in ids
      assert "storage_class" in ids
      assert "expiry_days" in ids
    end

    test "region field has from-context fill", %{defn: %{fields: fields}} do
      field = Enum.find(fields, &(&1.id == "region"))
      assert field.genie_fill == :from_context
      assert field.type == :select
      assert field.required == true
      assert field.options_from == "load_regions"
      assert field.options_value_key == "code"
      assert field.options_label_key == "name"
    end

    test "bucket_name field has infer fill with text attributes", %{defn: %{fields: fields}} do
      field = Enum.find(fields, &(&1.id == "bucket_name"))
      assert field.genie_fill == :infer
      assert field.type == :text
      assert field.required == true
      assert field.max_length == 63
      assert field.pattern != nil
    end

    test "access field has static options", %{defn: %{fields: fields}} do
      field = Enum.find(fields, &(&1.id == "access"))
      assert field.genie_fill == :infer
      assert field.type == :select
      assert length(field.options) == 3
      assert [%OptionDef{value: "private"} | _] = field.options
    end

    test "versioning field is a toggle", %{defn: %{fields: fields}} do
      field = Enum.find(fields, &(&1.id == "versioning"))
      assert field.type == :toggle
      assert field.genie_fill == :infer
    end

    test "org_id field is hidden with from-context fill", %{defn: %{fields: fields}} do
      field = Enum.find(fields, &(&1.id == "org_id"))
      assert field.type == :hidden
      assert field.genie_fill == :from_context
    end

    test "encryption_type field is radio inside a group", %{defn: %{fields: fields}} do
      field = Enum.find(fields, &(&1.id == "encryption_type"))
      assert field.type == :radio
      assert field.group_id == "advanced_config"
      assert field.genie_fill == :none
      assert length(field.options) == 3
    end

    test "expiry_days field has number attributes", %{defn: %{fields: fields}} do
      field = Enum.find(fields, &(&1.id == "expiry_days"))
      assert field.type == :number
      assert field.min == 0
      assert field.max == 3650
      assert field.step == 1
    end

    test "kms_key_id field has depends-on attributes", %{defn: %{fields: fields}} do
      field = Enum.find(fields, &(&1.id == "kms_key_id"))
      assert field.depends_on == "encryption_type"
      assert field.depends_on_value == "SSE-KMS"
      assert field.depends_on_behavior == :show
    end

    test "hints are resolved onto fields", %{defn: %{fields: fields}} do
      region = Enum.find(fields, &(&1.id == "region"))
      assert region.hint =~ "closest to your users"

      bucket = Enum.find(fields, &(&1.id == "bucket_name"))
      assert bucket.hint =~ "globally unique"
    end

    test "parses group", %{defn: %{groups: groups}} do
      assert length(groups) == 1
      group = hd(groups)
      assert %GroupDef{} = group
      assert group.id == "advanced_config"
      assert group.collapsible == true
      assert group.aria_label != nil
    end

    test "parses actions", %{defn: %{actions: actions}} do
      assert length(actions) == 2
      submit = Enum.find(actions, &(&1.id == "submit_create"))
      assert %ActionDef{} = submit
      assert submit.style == "primary"
      assert submit.endpoint_id == "create_bucket"
      assert submit.behavior == :submit
      assert submit.destructive == false
    end

    test "parses status templates", %{defn: %{status_templates: templates}} do
      states = Enum.map(templates, & &1.state)
      assert "submitting" in states
      assert "pending-approval" in states
      assert "ready" in states
      assert "failed" in states
    end

    test "status template fields have aria-label", %{defn: %{status_templates: templates}} do
      for tmpl <- templates, field <- tmpl.fields do
        assert field.aria_label != nil, "template #{tmpl.state} field missing aria-label"
      end
    end

    test "ready template has two fields", %{defn: %{status_templates: templates}} do
      ready = Enum.find(templates, &(&1.state == "ready"))
      assert %StatusTemplate{} = ready
      assert length(ready.fields) == 2
      link_field = Enum.find(ready.fields, &(&1.type == :link))
      assert link_field.href == "{console_url}"
    end

    test "form description is populated", %{defn: defn} do
      assert defn.form_description_id == "form-description"
      assert defn.form_description =~ "Create a new Amazon S3 bucket"
      assert defn.form_aria_label == "Create S3 Bucket"
      assert defn.form_aria_describedby == "form-description"
    end
  end

  describe "genie-fill parsing" do
    test "from-context maps to :from_context" do
      {:ok, defn} = LampParser.parse(lamp_xml(field(genie_fill: "from-context")))
      field = hd(defn.fields)
      assert field.genie_fill == :from_context
    end

    test "infer maps to :infer" do
      {:ok, defn} = LampParser.parse(lamp_xml(field(genie_fill: "infer")))
      field = hd(defn.fields)
      assert field.genie_fill == :infer
    end

    test "none maps to :none" do
      {:ok, defn} = LampParser.parse(lamp_xml(field(genie_fill: "none")))
      field = hd(defn.fields)
      assert field.genie_fill == :none
    end
  end

  describe "field type parsing" do
    for {xml_type, expected_atom} <- [
          {"text", :text},
          {"textarea", :textarea},
          {"select", :select},
          {"radio", :radio},
          {"toggle", :toggle},
          {"number", :number},
          {"date", :date},
          {"checkbox-group", :checkbox_group},
          {"hidden", :hidden}
        ] do
      test "#{xml_type} maps to #{expected_atom}" do
        xml_type = unquote(xml_type)
        expected = unquote(expected_atom)

        {:ok, defn} = LampParser.parse(lamp_xml(field(type: xml_type)))
        assert hd(defn.fields).type == expected
      end
    end
  end

  describe "validation — lamp id" do
    test "missing id returns error" do
      assert {:error, msg} = LampParser.parse(lamp_xml_with_id(nil))
      assert msg =~ "id"
    end

    test "id without dots returns error" do
      assert {:error, msg} = LampParser.parse(lamp_xml_with_id("nodots"))
      assert msg =~ "pattern"
    end

    test "id with only one dot returns error" do
      assert {:error, msg} = LampParser.parse(lamp_xml_with_id("a.b"))
      assert msg =~ "pattern"
    end

    test "valid id passes" do
      assert {:ok, defn} = LampParser.parse(lamp_xml_with_id("aws.s3.create-bucket"))
      assert defn.id == "aws.s3.create-bucket"
    end
  end

  describe "validation — at least one field" do
    test "lamp with no fields returns error" do
      assert {:error, msg} = LampParser.parse(lamp_xml_no_fields())
      assert msg =~ "field"
    end
  end

  describe "validation — action endpoint refs" do
    test "action referencing undefined endpoint returns error" do
      xml = lamp_xml_with_bad_action_endpoint()
      assert {:error, msg} = LampParser.parse(xml)
      assert msg =~ "undefined endpoint"
    end
  end

  describe "validation — options-from refs" do
    test "field options-from referencing undefined endpoint returns error" do
      xml = lamp_xml_with_bad_options_from()
      assert {:error, msg} = LampParser.parse(xml)
      assert msg =~ "undefined endpoint"
    end
  end

  describe "validation — depends-on refs" do
    test "field depends-on referencing undefined field returns error" do
      xml = lamp_xml_with_bad_depends_on()
      assert {:error, msg} = LampParser.parse(xml)
      assert msg =~ "undefined field"
    end
  end

  describe "validation — aria-label on fields" do
    test "field without aria-label returns error" do
      xml = lamp_xml(field(aria_label: nil))
      assert {:error, msg} = LampParser.parse(xml)
      assert msg =~ "aria-label"
    end
  end

  describe "validation — aria-label on actions" do
    test "action without aria-label returns error" do
      xml = lamp_xml_with_action_missing_aria()
      assert {:error, msg} = LampParser.parse(xml)
      assert msg =~ "aria-label"
    end
  end

  describe "validation — aria-label on status template fields" do
    test "status template field without aria-label returns error" do
      xml = lamp_xml_with_template_field_missing_aria()
      assert {:error, msg} = LampParser.parse(xml)
      assert msg =~ "aria-label"
    end
  end

  describe "validation — genie-fill values" do
    test "invalid genie-fill value returns error" do
      xml = lamp_xml(field(genie_fill: "invalid-value"))
      assert {:error, msg} = LampParser.parse(xml)
      assert msg =~ "genie-fill"
    end
  end

  describe "validation — primary action required" do
    test "required fields without primary action returns error" do
      xml = lamp_xml_required_field_no_primary_action()
      assert {:error, msg} = LampParser.parse(xml)
      assert msg =~ "primary action"
    end
  end

  describe "depends-on preserved in FieldDef" do
    test "depends-on, depends-on-value, depends-on-behavior are all preserved" do
      xml =
        lamp_xml("""
        <field id="trigger" type="toggle"
          aria-label="Enable advanced mode"
          genie-fill="none"/>
        <field id="child" type="text"
          aria-label="Advanced setting"
          genie-fill="none"
          depends-on="trigger"
          depends-on-value="true"
          depends-on-behavior="show"/>
        """)

      {:ok, defn} = LampParser.parse(xml)
      child = Enum.find(defn.fields, &(&1.id == "child"))
      assert child.depends_on == "trigger"
      assert child.depends_on_value == "true"
      assert child.depends_on_behavior == :show
    end
  end

  describe "group sets group_id on child fields" do
    test "fields inside a group have group_id set" do
      xml =
        lamp_xml("""
        <field id="outside" type="text"
          aria-label="Outside field"
          genie-fill="none"/>
        <group id="my-group" label="Group" aria-label="My group">
          <field id="inside" type="text"
            aria-label="Inside field"
            genie-fill="none"/>
        </group>
        """)

      {:ok, defn} = LampParser.parse(xml)
      outside = Enum.find(defn.fields, &(&1.id == "outside"))
      inside = Enum.find(defn.fields, &(&1.id == "inside"))

      assert outside.group_id == nil
      assert inside.group_id == "my-group"
    end
  end

  # --- XML fixture builders ---

  defp lamp_xml(fields_xml) when is_binary(fields_xml) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <lamp id="test.lamp.fixture" version="1.0" category="compute" vendor="test">
      <meta>
        <title>Test Lamp</title>
        <description>A test lamp.</description>
        <base-url>https://example.com</base-url>
        <auth-scheme>bearer</auth-scheme>
        <requires-approval>false</requires-approval>
        <destructive>false</destructive>
        <audit>false</audit>
      </meta>
      <endpoints>
        <endpoint id="run" method="POST" path="/run" trigger="on-submit" action-id="submit"/>
      </endpoints>
      <ui>
        <form aria-label="Test form">
          #{fields_xml}
        </form>
      </ui>
      <actions>
        <action id="submit" label="Submit" aria-label="Submit the test form"
          style="primary" endpoint-id="run" behavior="submit"/>
      </actions>
    </lamp>
    """
  end

  defp field(opts) do
    id = Keyword.get(opts, :id, "test_field")
    type = Keyword.get(opts, :type, "text")
    genie_fill = Keyword.get(opts, :genie_fill, "none")
    aria_label = Keyword.get(opts, :aria_label, "Test field label")

    genie_fill_attr = if genie_fill, do: ~s(genie-fill="#{genie_fill}"), else: ""
    aria_label_attr = if aria_label, do: ~s(aria-label="#{aria_label}"), else: ""

    ~s(<field id="#{id}" type="#{type}" label="Test" #{aria_label_attr} #{genie_fill_attr}/>)
  end

  defp lamp_xml_with_id(nil) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <lamp version="1.0" category="compute" vendor="test">
      <meta><title>T</title><base-url>https://x.com</base-url><auth-scheme>bearer</auth-scheme><requires-approval>false</requires-approval><destructive>false</destructive><audit>false</audit></meta>
      <endpoints><endpoint id="run" method="POST" path="/run" trigger="on-submit" action-id="s"/></endpoints>
      <ui><form aria-label="F"><field id="f" type="text" aria-label="A field" genie-fill="none"/></form></ui>
      <actions><action id="s" label="S" aria-label="Submit" style="primary" endpoint-id="run" behavior="submit"/></actions>
    </lamp>
    """
  end

  defp lamp_xml_with_id(id) do
    lamp_xml(field([]))
    |> String.replace(~s(id="test.lamp.fixture"), ~s(id="#{id}"))
  end

  defp lamp_xml_no_fields do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <lamp id="test.lamp.nofields" version="1.0" category="compute" vendor="test">
      <meta><title>T</title><base-url>https://x.com</base-url><auth-scheme>bearer</auth-scheme><requires-approval>false</requires-approval><destructive>false</destructive><audit>false</audit></meta>
      <endpoints><endpoint id="run" method="POST" path="/run" trigger="on-submit"/></endpoints>
      <ui><form aria-label="F"></form></ui>
      <actions></actions>
    </lamp>
    """
  end

  defp lamp_xml_with_bad_action_endpoint do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <lamp id="test.lamp.badep" version="1.0" category="compute" vendor="test">
      <meta><title>T</title><base-url>https://x.com</base-url><auth-scheme>bearer</auth-scheme><requires-approval>false</requires-approval><destructive>false</destructive><audit>false</audit></meta>
      <endpoints><endpoint id="real_ep" method="POST" path="/run" trigger="on-submit"/></endpoints>
      <ui><form aria-label="F"><field id="f" type="text" aria-label="A field" genie-fill="none"/></form></ui>
      <actions><action id="s" label="S" aria-label="Submit" style="primary" endpoint-id="nonexistent_ep" behavior="submit"/></actions>
    </lamp>
    """
  end

  defp lamp_xml_with_bad_options_from do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <lamp id="test.lamp.badof" version="1.0" category="compute" vendor="test">
      <meta><title>T</title><base-url>https://x.com</base-url><auth-scheme>bearer</auth-scheme><requires-approval>false</requires-approval><destructive>false</destructive><audit>false</audit></meta>
      <endpoints><endpoint id="run" method="POST" path="/run" trigger="on-submit" action-id="s"/></endpoints>
      <ui><form aria-label="F">
        <field id="f" type="select" aria-label="A select" genie-fill="none" options-from="nonexistent_ep"/>
      </form></ui>
      <actions><action id="s" label="S" aria-label="Submit" style="primary" endpoint-id="run" behavior="submit"/></actions>
    </lamp>
    """
  end

  defp lamp_xml_with_bad_depends_on do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <lamp id="test.lamp.baddo" version="1.0" category="compute" vendor="test">
      <meta><title>T</title><base-url>https://x.com</base-url><auth-scheme>bearer</auth-scheme><requires-approval>false</requires-approval><destructive>false</destructive><audit>false</audit></meta>
      <endpoints><endpoint id="run" method="POST" path="/run" trigger="on-submit" action-id="s"/></endpoints>
      <ui><form aria-label="F">
        <field id="f" type="text" aria-label="A field" genie-fill="none" depends-on="nonexistent_field" depends-on-value="true" depends-on-behavior="show"/>
      </form></ui>
      <actions><action id="s" label="S" aria-label="Submit" style="primary" endpoint-id="run" behavior="submit"/></actions>
    </lamp>
    """
  end

  defp lamp_xml_with_action_missing_aria do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <lamp id="test.lamp.noaria" version="1.0" category="compute" vendor="test">
      <meta><title>T</title><base-url>https://x.com</base-url><auth-scheme>bearer</auth-scheme><requires-approval>false</requires-approval><destructive>false</destructive><audit>false</audit></meta>
      <endpoints><endpoint id="run" method="POST" path="/run" trigger="on-submit" action-id="s"/></endpoints>
      <ui><form aria-label="F"><field id="f" type="text" aria-label="A field" genie-fill="none"/></form></ui>
      <actions><action id="s" label="S" style="primary" endpoint-id="run" behavior="submit"/></actions>
    </lamp>
    """
  end

  defp lamp_xml_with_template_field_missing_aria do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <lamp id="test.lamp.tmplnoaria" version="1.0" category="compute" vendor="test">
      <meta><title>T</title><base-url>https://x.com</base-url><auth-scheme>bearer</auth-scheme><requires-approval>false</requires-approval><destructive>false</destructive><audit>false</audit></meta>
      <endpoints><endpoint id="run" method="POST" path="/run" trigger="on-submit" action-id="s"/></endpoints>
      <ui><form aria-label="F"><field id="f" type="text" aria-label="A field" genie-fill="none"/></form></ui>
      <actions><action id="s" label="S" aria-label="Submit" style="primary" endpoint-id="run" behavior="submit"/></actions>
      <status-templates>
        <template state="ready">
          <field type="banner" label="Done" style="success" value="OK"/>
        </template>
      </status-templates>
    </lamp>
    """
  end

  defp lamp_xml_required_field_no_primary_action do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <lamp id="test.lamp.noprimary" version="1.0" category="compute" vendor="test">
      <meta><title>T</title><base-url>https://x.com</base-url><auth-scheme>bearer</auth-scheme><requires-approval>false</requires-approval><destructive>false</destructive><audit>false</audit></meta>
      <endpoints><endpoint id="run" method="POST" path="/run" trigger="on-submit" action-id="s"/></endpoints>
      <ui><form aria-label="F">
        <field id="f" type="text" aria-label="A required field" genie-fill="none" required="true"/>
      </form></ui>
      <actions><action id="s" label="S" aria-label="Submit" style="secondary" endpoint-id="run" behavior="submit"/></actions>
    </lamp>
    """
  end
end
