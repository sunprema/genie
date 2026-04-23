defmodule Genie.Lamp.LampRendererTest do
  use ExUnit.Case, async: true

  alias Genie.Lamp.{
    ActionDef,
    FieldDef,
    LampDefinition,
    LampParser,
    LampRenderer,
    MetaDef,
    OptionDef
  }

  @s3_xml File.read!(Path.join(:code.priv_dir(:genie), "lamps/aws_s3_create_bucket.xml"))
  @snapshot_path Path.join([__DIR__, "..", "..", "fixtures", "lamp_renderer", "aws_s3_create_bucket_snapshot.html"])

  defp parse_s3!, do: elem(LampParser.parse(@s3_xml), 1)

  defp render_to_string(defn) do
    {:safe, iodata} = LampRenderer.render(defn)
    IO.iodata_to_binary(iodata)
  end

  # --- Snapshot test ---

  describe "render/1 snapshot" do
    test "matches saved snapshot for aws_s3_create_bucket" do
      defn = parse_s3!()
      html = render_to_string(defn)

      if File.exists?(@snapshot_path) do
        assert html == File.read!(@snapshot_path)
      else
        File.mkdir_p!(Path.dirname(@snapshot_path))
        File.write!(@snapshot_path, html)
        IO.puts("Snapshot saved to #{@snapshot_path}")
      end
    end
  end

  # --- ARIA attributes ---

  describe "render/1 ARIA attributes" do
    setup do
      defn = parse_s3!()
      html = render_to_string(defn)
      %{html: html, defn: defn}
    end

    test "form has role=form and aria-label", %{html: html} do
      assert html =~ ~s(role="form")
      assert html =~ ~s(aria-label="Create S3 Bucket")
    end

    test "text input has aria-label and aria-required", %{html: html} do
      assert html =~ ~s(aria-label="S3 bucket name, must be globally unique)
      assert html =~ ~s(aria-required="true")
    end

    test "select has aria-label", %{html: html} do
      assert html =~ ~s(aria-label="AWS region where the bucket will be created")
    end

    test "toggle has role=switch and aria-checked", %{html: html} do
      assert html =~ ~s(role="switch")
      assert html =~ ~s(aria-checked="false")
    end

    test "radio group has role=radiogroup", %{html: html} do
      assert html =~ ~s(role="radiogroup")
    end

    test "radio options have role=radio and aria-checked", %{html: html} do
      assert html =~ ~s(role="radio")
      assert html =~ ~s(aria-checked="true")
      assert html =~ ~s(aria-checked="false")
    end

    test "group has role=group and aria-labelledby", %{html: html} do
      assert html =~ ~s(role="group")
      assert html =~ ~s(aria-labelledby="group-label-advanced_config")
    end

    test "hidden field preserves aria-label", %{html: html} do
      assert html =~ ~s(aria-label="Organisation identifier, set automatically from session context")
      assert html =~ ~s(aria-hidden="true")
    end

    test "actions container has role=group aria-label=Form actions", %{html: html} do
      assert html =~ ~s(role="group")
      assert html =~ ~s(aria-label="Form actions")
    end

    test "action button has aria-label", %{html: html} do
      assert html =~ ~s(aria-label="Submit form to create the S3 bucket with the configured settings")
    end

    test "lamp container has role=region and aria-label", %{html: html} do
      assert html =~ ~s(role="region")
      assert html =~ ~s(aria-label="AWS S3 Bucket Creator")
    end
  end

  # --- depends-on visibility ---

  describe "depends_on visibility" do
    test "field with depends-on show is aria-hidden when condition not met" do
      defn = parse_s3!()
      html = render_to_string(defn)

      # kms_key_id depends-on encryption_type=SSE-KMS; default encryption_type is SSE-S3 → hidden
      # The wrapper div for kms_key_id has aria-hidden="true" and the label follows immediately
      assert html =~ ~r/<div[^>]*\bhidden\b[^>]*aria-hidden="true"[^>]*>\s*<label[^>]*>[^<]*KMS Key/
    end

    test "field with depends-on show has hidden class when condition not met" do
      defn = parse_s3!()
      html = render_to_string(defn)

      # The wrapper div for kms_key_id must have the Tailwind "hidden" class
      assert html =~ ~r/<div class="[^"]*\bhidden\b[^"]*"[^>]*aria-hidden="true"/
    end

    test "field is visible when depends-on condition is met" do
      {:ok, defn} = LampParser.parse(@s3_xml)

      # Set encryption_type value to SSE-KMS so kms_key_id becomes visible
      fields =
        Enum.map(defn.fields, fn
          %FieldDef{id: "encryption_type"} = f -> %{f | value: "SSE-KMS"}
          f -> f
        end)

      defn = %{defn | fields: fields}
      html = render_to_string(defn)

      # When visible, the kms_key_id wrapper div should NOT have aria-hidden="true"
      # followed immediately by a label containing "KMS Key"
      refute html =~ ~r/<div[^>]*\bhidden\b[^>]*aria-hidden="true"[^>]*>\s*<label[^>]*>[^<]*KMS Key/
    end
  end

  # --- fill_class/1 helper ---

  describe "fill_class/1" do
    test "returns prefilled-context for :from_context" do
      assert LampRenderer.fill_class(:from_context) == "prefilled-context"
    end

    test "returns prefilled-infer for :infer" do
      assert LampRenderer.fill_class(:infer) == "prefilled-infer"
    end

    test "returns empty string for :none" do
      assert LampRenderer.fill_class(:none) == ""
    end

    test "returns empty string for nil" do
      assert LampRenderer.fill_class(nil) == ""
    end
  end

  # --- fill badges ---

  describe "fill badges in rendered output" do
    test "from_context field shows context badge" do
      defn = parse_s3!()
      html = render_to_string(defn)
      assert html =~ "context"
    end

    test "infer field shows AI badge" do
      defn = parse_s3!()
      html = render_to_string(defn)
      assert html =~ "AI"
    end
  end

  # --- Field types ---

  describe "field type rendering" do
    defp simple_defn(field, extra_fields \\ []) do
      fields = [field | extra_fields]

      %LampDefinition{
        id: "test.lamp.test",
        version: "1.0",
        category: "test",
        vendor: "test",
        meta: %MetaDef{title: "Test Lamp"},
        fields: fields,
        groups: [],
        actions: [
          %ActionDef{
            id: "submit",
            label: "Submit",
            aria_label: "Submit the form",
            style: "primary",
            behavior: :submit
          }
        ],
        endpoints: [],
        status_templates: [],
        form_aria_label: "Test Form"
      }
    end

    test "text field renders input type=text" do
      field = %FieldDef{
        id: "name",
        type: :text,
        label: "Name",
        aria_label: "Full name",
        genie_fill: :none,
        required: true
      }

      html = render_to_string(simple_defn(field))
      assert html =~ ~s(type="text")
      assert html =~ ~s(aria-label="Full name")
      assert html =~ ~s(aria-required="true")
    end

    test "textarea field renders textarea" do
      field = %FieldDef{
        id: "bio",
        type: :textarea,
        label: "Bio",
        aria_label: "Short biography",
        genie_fill: :none,
        rows: 5
      }

      html = render_to_string(simple_defn(field))
      assert html =~ "<textarea"
      assert html =~ ~s(rows="5")
      assert html =~ ~s(aria-label="Short biography")
    end

    test "select field renders select element" do
      field = %FieldDef{
        id: "size",
        type: :select,
        label: "Size",
        aria_label: "Bucket size",
        genie_fill: :none,
        options: [
          %OptionDef{value: "sm", label: "Small"},
          %OptionDef{value: "lg", label: "Large"}
        ]
      }

      html = render_to_string(simple_defn(field))
      assert html =~ "<select"
      assert html =~ ~s(value="sm")
      assert html =~ "Small"
    end

    test "select with default pre-selects correct option" do
      field = %FieldDef{
        id: "size",
        type: :select,
        label: "Size",
        aria_label: "Bucket size",
        genie_fill: :none,
        default: "lg",
        options: [
          %OptionDef{value: "sm", label: "Small"},
          %OptionDef{value: "lg", label: "Large"}
        ]
      }

      html = render_to_string(simple_defn(field))
      assert html =~ ~s(value="lg" selected)
    end

    test "toggle renders role=switch with aria-checked" do
      field = %FieldDef{
        id: "enabled",
        type: :toggle,
        label: "Enable Feature",
        aria_label: "Toggle feature on or off",
        genie_fill: :none,
        default: "true"
      }

      html = render_to_string(simple_defn(field))
      assert html =~ ~s(role="switch")
      assert html =~ ~s(aria-checked="true")
    end

    test "toggle is aria-checked=false when default is false" do
      field = %FieldDef{
        id: "enabled",
        type: :toggle,
        label: "Enable Feature",
        aria_label: "Toggle feature on or off",
        genie_fill: :none,
        default: "false"
      }

      html = render_to_string(simple_defn(field))
      assert html =~ ~s(aria-checked="false")
    end

    test "number field renders input type=number" do
      field = %FieldDef{
        id: "count",
        type: :number,
        label: "Count",
        aria_label: "Number of items",
        genie_fill: :none,
        min: 0,
        max: 100,
        step: 1
      }

      html = render_to_string(simple_defn(field))
      assert html =~ ~s(type="number")
      assert html =~ ~s(min="0")
      assert html =~ ~s(max="100")
      assert html =~ ~s(step="1")
    end

    test "date field renders input type=date" do
      field = %FieldDef{
        id: "expires",
        type: :date,
        label: "Expiry",
        aria_label: "Expiry date",
        genie_fill: :none
      }

      html = render_to_string(simple_defn(field))
      assert html =~ ~s(type="date")
    end

    test "date field computes min/max from offset days" do
      today = Date.utc_today()
      min_expected = today |> Date.add(1) |> Date.to_iso8601()
      max_expected = today |> Date.add(30) |> Date.to_iso8601()

      field = %FieldDef{
        id: "expires",
        type: :date,
        label: "Expiry",
        aria_label: "Expiry date",
        genie_fill: :none,
        min_offset_days: 1,
        max_offset_days: 30
      }

      html = render_to_string(simple_defn(field))
      assert html =~ ~s(min="#{min_expected}")
      assert html =~ ~s(max="#{max_expected}")
    end

    test "checkbox_group renders role=group with role=checkbox items" do
      field = %FieldDef{
        id: "tags",
        type: :checkbox_group,
        label: "Tags",
        aria_label: "Select tags",
        genie_fill: :none,
        options: [
          %OptionDef{value: "prod", label: "Production"},
          %OptionDef{value: "dev", label: "Development"}
        ]
      }

      html = render_to_string(simple_defn(field))
      assert html =~ ~s(role="group")
      assert html =~ ~s(role="checkbox")
      assert html =~ "Production"
      assert html =~ "Development"
    end

    test "checkbox_group items have aria-checked" do
      field = %FieldDef{
        id: "tags",
        type: :checkbox_group,
        label: "Tags",
        aria_label: "Select tags",
        genie_fill: :none,
        options: [
          %OptionDef{value: "prod", label: "Production"}
        ]
      }

      html = render_to_string(simple_defn(field))
      assert html =~ ~s(aria-checked="false")
    end

    test "hidden field renders with aria-hidden=true and preserves aria-label" do
      field = %FieldDef{
        id: "org_id",
        type: :hidden,
        label: "Org ID",
        aria_label: "Organisation identifier",
        genie_fill: :from_context,
        value: "org_123"
      }

      html = render_to_string(simple_defn(field))
      assert html =~ ~s(aria-hidden="true")
      assert html =~ ~s(aria-label="Organisation identifier")
      assert html =~ ~s(value="org_123")
    end
  end

  # --- render_status/2 ---

  describe "render_status/2" do
    setup do
      {:ok, defn} = LampParser.parse(@s3_xml)
      %{defn: defn}
    end

    test "interpolates bucket_name in status template aria-label", %{defn: defn} do
      result = %{
        "state" => "ready",
        "bucket_name" => "my-test-bucket",
        "region" => "us-east-1",
        "console_url" => "https://console.aws.amazon.com/s3/buckets/my-test-bucket"
      }

      {:safe, iodata} = LampRenderer.render_status(defn, result)
      html = IO.iodata_to_binary(iodata)

      assert html =~ "my-test-bucket"
      assert html =~ "us-east-1"
    end

    test "renders submitting template with spinner", %{defn: defn} do
      result = %{"state" => "submitting", "bucket_name" => "acme-bucket"}
      {:safe, iodata} = LampRenderer.render_status(defn, result)
      html = IO.iodata_to_binary(iodata)

      assert html =~ "animate-spin"
      assert html =~ "Creating bucket"
    end

    test "renders ready template with banner and link", %{defn: defn} do
      result = %{
        "state" => "ready",
        "bucket_name" => "acme-prod",
        "region" => "us-east-1",
        "console_url" => "https://console.aws.amazon.com/s3"
      }

      {:safe, iodata} = LampRenderer.render_status(defn, result)
      html = IO.iodata_to_binary(iodata)

      # banner label and interpolated value
      assert html =~ "Bucket Created"
      assert html =~ "Bucket acme-prod created successfully"
      assert html =~ "https://console.aws.amazon.com/s3"
      assert html =~ "View in AWS Console"
    end

    test "renders failed template with error message", %{defn: defn} do
      result = %{"state" => "failed", "error_message" => "Bucket already exists"}
      {:safe, iodata} = LampRenderer.render_status(defn, result)
      html = IO.iodata_to_binary(iodata)

      assert html =~ "Bucket already exists"
    end

    test "renders pending-approval template", %{defn: defn} do
      result = %{
        "state" => "pending-approval",
        "bucket_name" => "acme-bucket",
        "region" => "us-east-1"
      }

      {:safe, iodata} = LampRenderer.render_status(defn, result)
      html = IO.iodata_to_binary(iodata)

      assert html =~ "Pending Approval"
    end

    test "returns empty safe string for unknown state", %{defn: defn} do
      result = %{"state" => "nonexistent"}
      assert {:safe, ""} = LampRenderer.render_status(defn, result)
    end
  end
end
