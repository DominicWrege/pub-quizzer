defmodule PubQuizzerWeb.AdminSessionControllerTest do
  use PubQuizzerWeb.ConnCase

  alias PubQuizzer.Accounts

  describe "POST /admin/login" do
    test "redirects to /admin/login when email param is missing", %{conn: conn} do
      {:ok, _} =
        Accounts.create_user(%{email: "admin@test.com", name: "Admin", role: "superadmin"})

      conn = post(conn, ~p"/admin/login", %{})
      assert redirected_to(conn) == "/admin/login"
    end
  end

  describe "POST /admin/login/verify" do
    test "redirects to /admin/login when params are missing", %{conn: conn} do
      conn = post(conn, ~p"/admin/login/verify", %{})
      assert redirected_to(conn) == "/admin/login"
    end
  end

  describe "POST /admin/login/resend" do
    test "redirects to /admin/login when email param is missing", %{conn: conn} do
      conn = post(conn, ~p"/admin/login/resend", %{})
      assert redirected_to(conn) == "/admin/login"
    end
  end
end
