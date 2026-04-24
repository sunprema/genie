defmodule GenieWeb.AuthLiveTest do
  use GenieWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "sign-in page" do
    test "renders sign-in form", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/sign-in")

      assert html =~ "sign" or html =~ "Sign" or html =~ "Log in" or html =~ "login"
    end

    test "unauthenticated /cockpit redirects to sign-in", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, "/cockpit")
      assert path =~ "sign-in" or path =~ "login"
    end
  end

  describe "register page" do
    test "renders registration form", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/register")

      assert html =~ "register" or html =~ "Register" or html =~ "Create account" or
               html =~ "email" or html =~ "Email"
    end
  end
end
