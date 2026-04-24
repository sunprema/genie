defmodule GenieWeb.CoreComponentsTest do
  use GenieWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GenieWeb.CoreComponents

  defp render_component_html(fun, assigns) do
    rendered = Phoenix.LiveViewTest.rendered_to_string(fun.(assigns))
    rendered
  end

  describe "input/1 — text type" do
    test "renders text input" do
      assigns = %{
        type: "text",
        name: "username",
        id: "username",
        value: "",
        label: "Username",
        errors: [],
        rest: %{}
      }

      html = render_component(&CoreComponents.input/1, assigns)
      assert html =~ "type=\"text\""
      assert html =~ "Username"
    end

    test "renders input with errors" do
      assigns = %{
        type: "text",
        name: "email",
        id: "email",
        value: "bad",
        label: "Email",
        errors: ["is invalid"],
        rest: %{}
      }

      html = render_component(&CoreComponents.input/1, assigns)
      assert html =~ "is invalid"
    end

    test "renders email input" do
      assigns = %{
        type: "email",
        name: "email",
        id: "email",
        value: "",
        label: "Email",
        errors: [],
        rest: %{}
      }

      html = render_component(&CoreComponents.input/1, assigns)
      assert html =~ "type=\"email\""
    end
  end

  describe "input/1 — select type" do
    test "renders select with options" do
      assigns = %{
        type: "select",
        name: "role",
        id: "role",
        value: "admin",
        label: "Role",
        options: [{"Admin", "admin"}, {"Member", "member"}],
        prompt: nil,
        errors: [],
        rest: %{}
      }

      html = render_component(&CoreComponents.input/1, assigns)
      assert html =~ "<select"
      assert html =~ "Admin"
      assert html =~ "Member"
    end
  end

  describe "input/1 — checkbox type" do
    test "renders checkbox" do
      assigns = %{
        type: "checkbox",
        name: "agree",
        id: "agree",
        value: "true",
        checked: true,
        label: "I agree",
        errors: [],
        rest: %{}
      }

      html = render_component(&CoreComponents.input/1, assigns)
      assert html =~ "type=\"checkbox\""
      assert html =~ "I agree"
    end
  end

  describe "input/1 — textarea type" do
    test "renders textarea" do
      assigns = %{
        type: "textarea",
        name: "bio",
        id: "bio",
        value: "hello",
        label: "Bio",
        errors: [],
        rest: %{}
      }

      html = render_component(&CoreComponents.input/1, assigns)
      assert html =~ "<textarea"
      assert html =~ "hello"
    end
  end

  describe "input/1 — hidden type" do
    test "renders hidden input" do
      assigns = %{
        type: "hidden",
        name: "token",
        id: "token",
        value: "secret",
        rest: %{}
      }

      html = render_component(&CoreComponents.input/1, assigns)
      assert html =~ "type=\"hidden\""
      assert html =~ "secret"
    end
  end


  describe "show/2 and hide/2" do
    test "show returns a JS command struct" do
      result = CoreComponents.show("#my-div")
      assert %Phoenix.LiveView.JS{} = result
    end

    test "hide returns a JS command struct" do
      result = CoreComponents.hide("#my-div")
      assert %Phoenix.LiveView.JS{} = result
    end

    test "show accepts existing JS struct" do
      js = %Phoenix.LiveView.JS{}
      result = CoreComponents.show(js, "#my-div")
      assert %Phoenix.LiveView.JS{} = result
    end

    test "hide accepts existing JS struct" do
      js = %Phoenix.LiveView.JS{}
      result = CoreComponents.hide(js, "#my-div")
      assert %Phoenix.LiveView.JS{} = result
    end
  end

  describe "icon/1" do
    test "renders hero icon" do
      html = render_component(&CoreComponents.icon/1, name: "hero-x-mark", class: "w-4 h-4")
      assert html =~ "svg" or html =~ "x-mark" or html =~ "hero"
    end
  end

  describe "translate_error/1" do
    test "returns message string for simple error" do
      assert CoreComponents.translate_error({"is invalid", []}) == "is invalid"
    end

    test "interpolates count for count errors" do
      result = CoreComponents.translate_error({"must be at most %{count} characters", [count: 10]})
      assert result =~ "10"
    end
  end

  describe "translate_errors/2" do
    test "returns empty list for no errors" do
      assert CoreComponents.translate_errors([], :name) == []
    end
  end
end
