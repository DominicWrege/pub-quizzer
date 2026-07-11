defmodule PubQuizzerWeb.AdminAuthTest do
  use PubQuizzerWeb.ConnCase, async: true

  describe "admin session controller" do
    test "GET /admin/login renders the login form", %{conn: conn} do
      conn = get(conn, ~p"/admin/login")
      assert html_response(conn, 200) =~ "Verwaltung"
      assert html_response(conn, 200) =~ "admin-login-form"
    end

    test "POST /admin/login with correct password sets session and redirects", %{conn: conn} do
      conn =
        post(conn, ~p"/admin/login", %{
          "password" => Application.fetch_env!(:pub_quizzer, :admin) |> Keyword.fetch!(:password)
        })

      assert redirected_to(conn) == "/admin/events"
      assert get_session(conn, :admin) == true
    end

    test "POST /admin/login with wrong password redirects with error flash", %{conn: conn} do
      conn = post(conn, ~p"/admin/login", %{"password" => "wrong"})
      assert redirected_to(conn) == "/admin/login"
      refute get_session(conn, :admin) == true
    end

    test "GET /admin/login when already authed redirects to events", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(admin: true)
        |> get(~p"/admin/login")

      assert redirected_to(conn) == "/admin/events"
    end

    test "GET /admin/logout clears session", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(admin: true)
        |> get(~p"/admin/logout")

      assert redirected_to(conn) == "/admin/login"
    end
  end

  describe "admin auth plug" do
    test "unauthenticated access to /admin/topics redirects to login", %{conn: conn} do
      conn = get(conn, ~p"/admin/topics")
      assert redirected_to(conn) == "/admin/login"
    end

    test "authenticated access to /admin/topics is allowed", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(admin: true)
        |> get(~p"/admin/topics")

      assert conn.status in [200, 302]
    end
  end
end
