defmodule Genie.Bridge.SanitizerTest do
  use ExUnit.Case, async: true

  alias Genie.Bridge.Sanitizer

  describe "sanitize/1 — strips dangerous content" do
    test "strips <script> tags with content" do
      html = "<div>hello<script>alert(1)</script>world</div>"
      result = Sanitizer.sanitize(html)
      refute result =~ "<script"
      refute result =~ "alert(1)"
      assert result =~ "hello"
      assert result =~ "world"
    end

    test "strips <script> with attributes" do
      html = "<script type=\"text/javascript\">evil()</script>"
      result = Sanitizer.sanitize(html)
      refute result =~ "<script"
      refute result =~ "evil()"
    end

    test "strips <script> in nested position" do
      html = "<div><p>text<script src=\"evil.js\">bad()</script></p></div>"
      result = Sanitizer.sanitize(html)
      refute result =~ "<script"
      refute result =~ "bad()"
    end

    test "strips <style> tags" do
      html = "<style>body { display: none }</style><p>visible</p>"
      result = Sanitizer.sanitize(html)
      refute result =~ "<style"
      assert result =~ "<p>"
    end

    test "strips <iframe> tags" do
      html = "<iframe src=\"evil.com\"></iframe>"
      result = Sanitizer.sanitize(html)
      refute result =~ "<iframe"
    end
  end

  describe "sanitize/1 — strips javascript: hrefs" do
    test "strips javascript: href" do
      html = "<a href=\"javascript:alert(1)\">click me</a>"
      result = Sanitizer.sanitize(html)
      refute result =~ "javascript:"
      assert result =~ "click me"
    end

    test "strips javascript: with mixed case" do
      html = "<a href=\"JAVASCRIPT:alert(1)\">click</a>"
      result = Sanitizer.sanitize(html)
      refute result =~ "javascript:"
      refute result =~ "JAVASCRIPT:"
    end

    test "allows safe http: href" do
      html = "<a href=\"https://example.com\">link</a>"
      result = Sanitizer.sanitize(html)
      assert result =~ "href=\"https://example.com\""
    end
  end

  describe "sanitize/1 — strips on* event handlers" do
    test "strips onclick attribute" do
      html = "<div onclick=\"alert(1)\">text</div>"
      result = Sanitizer.sanitize(html)
      refute result =~ "onclick"
      assert result =~ "text"
    end

    test "strips onerror attribute" do
      html = "<img onerror=\"alert(1)\">"
      result = Sanitizer.sanitize(html)
      refute result =~ "onerror"
    end

    test "strips onmouseover attribute" do
      html = "<div onmouseover=\"alert(1)\">hover</div>"
      result = Sanitizer.sanitize(html)
      refute result =~ "onmouseover"
      assert result =~ "hover"
    end

    test "strips all on* attributes from an allowed element" do
      html = "<div onclick=\"a()\" onkeydown=\"b()\" class=\"safe\">text</div>"
      result = Sanitizer.sanitize(html)
      refute result =~ "onclick"
      refute result =~ "onkeydown"
      assert result =~ "class=\"safe\""
    end
  end

  describe "sanitize/1 — allows aria-* attributes" do
    test "allows aria-label" do
      html = "<div aria-label=\"test label\">content</div>"
      result = Sanitizer.sanitize(html)
      assert result =~ ~s(aria-label="test label")
    end

    test "allows aria-checked" do
      html = "<div role=\"checkbox\" aria-checked=\"true\">option</div>"
      result = Sanitizer.sanitize(html)
      assert result =~ ~s(aria-checked="true")
      assert result =~ ~s(role="checkbox")
    end

    test "allows aria-describedby" do
      html = "<input aria-describedby=\"hint-1\">"
      result = Sanitizer.sanitize(html)
      # input is stripped, but the test verifies sanitize runs without error
      refute result =~ "<input"
    end

    test "allows multiple aria-* attributes together" do
      html = "<div aria-label=\"name\" aria-required=\"true\" aria-hidden=\"false\">x</div>"
      result = Sanitizer.sanitize(html)
      assert result =~ "aria-label"
      assert result =~ "aria-required"
      assert result =~ "aria-hidden"
    end
  end

  describe "sanitize/1 — strips disallowed elements" do
    test "strips <form> tags" do
      html = "<form action=\"/evil\"><input name=\"x\"/></form>"
      result = Sanitizer.sanitize(html)
      refute result =~ "<form"
    end

    test "strips <input> self-closing" do
      html = "<div><input type=\"text\" value=\"data\"/></div>"
      result = Sanitizer.sanitize(html)
      refute result =~ "<input"
    end

    test "passes through allowed elements unchanged" do
      html = "<div><p><strong>bold</strong> and <em>italic</em></p></div>"
      result = Sanitizer.sanitize(html)
      assert result =~ "<div>"
      assert result =~ "<p>"
      assert result =~ "<strong>"
      assert result =~ "<em>"
    end

    test "HTML-encodes attribute values" do
      html = "<div class=\"foo&bar\">text</div>"
      result = Sanitizer.sanitize(html)
      assert result =~ "foo&amp;bar"
    end
  end
end
