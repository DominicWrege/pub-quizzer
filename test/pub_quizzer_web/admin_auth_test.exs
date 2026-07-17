defmodule PubQuizzerWeb.AdminAuthTest do
  use PubQuizzerWeb.ConnCase, async: true

  alias PubQuizzer.Accounts

  describe "admin session controller" do
    test "GET /admin/login renders the login form", %{conn: conn} do
      # Create a user so we don't get redirected to /setup
      {:ok, _} =
        Accounts.create_user(%{email: "admin@test.com", name: "Admin", role: "superadmin"})

      conn = get(conn, ~p"/admin/login")
      assert html_response(conn, 200) =~ "Login"
      assert html_response(conn, 200) =~ "admin-login-form"
    end

    test "GET /admin/login redirects to /setup when no users exist", %{conn: conn} do
      conn = get(conn, ~p"/admin/login")
      assert redirected_to(conn) == "/setup"
    end

    test "GET /admin/login when already authed redirects to events", %{conn: conn} do
      {:ok, _} =
        Accounts.create_user(%{email: "admin@test.com", name: "Admin", role: "superadmin"})

      conn =
        conn
        |> log_in_user()
        |> get(~p"/admin/login")

      assert redirected_to(conn) == "/admin/events"
    end

    test "POST /admin/login with known email renders link sent page", %{conn: conn} do
      {:ok, user} =
        Accounts.create_user(%{
          email: "admin@test.com",
          name: "Admin",
          role: "superadmin",
          active: true
        })

      conn = post(conn, ~p"/admin/login", %{"email" => user.email})
      assert html_response(conn, 200) =~ "Link gesendet"
      assert html_response(conn, 200) =~ user.email
    end

    test "POST /admin/login with unknown email shows error", %{conn: conn} do
      {:ok, _} =
        Accounts.create_user(%{email: "admin@test.com", name: "Admin", role: "superadmin"})

      conn = post(conn, ~p"/admin/login", %{"email" => "nobody@test.com"})
      assert redirected_to(conn) == "/admin/login"
      assert %{message: msg} = Phoenix.Flash.get(conn.assigns.flash, :error)
      assert msg =~ "nicht gefunden"
    end

    test "GET /admin/logout clears session", %{conn: conn} do
      conn =
        conn
        |> log_in_user()
        |> get(~p"/admin/logout")

      assert redirected_to(conn) == "/admin/login"
    end
  end

  describe "magic link" do
    test "valid token creates session and redirects", %{conn: conn} do
      {:ok, user} =
        Accounts.create_user(%{email: "admin@test.com", name: "Admin", role: "superadmin"})

      {:ok, raw_token} = Accounts.generate_invite_link(user)

      conn = get(conn, ~p"/admin/magic?token=#{raw_token}")

      assert redirected_to(conn) == "/admin/events"
      assert get_session(conn, :user_id) == user.id
    end

    test "invalid token shows error", %{conn: conn} do
      conn = get(conn, ~p"/admin/magic?token=invalid")

      assert redirected_to(conn) == "/admin/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Ungültig"
    end

    test "expired token shows error", %{conn: conn} do
      {:ok, user} =
        Accounts.create_user(%{email: "admin@test.com", name: "Admin", role: "superadmin"})

      {:ok, raw_token} = Accounts.generate_invite_link(user)

      eleven_min_ago =
        DateTime.utc_now()
        |> DateTime.add(-11, :minute)
        |> DateTime.truncate(:second)

      {:ok, _} =
        user
        |> Ecto.Changeset.change(%{magic_link_sent_at: eleven_min_ago})
        |> PubQuizzer.Repo.update()

      conn = get(conn, ~p"/admin/magic?token=#{raw_token}")

      assert redirected_to(conn) == "/admin/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "abgelaufen"
    end

    test "token is single-use", %{conn: conn} do
      {:ok, user} =
        Accounts.create_user(%{email: "admin@test.com", name: "Admin", role: "superadmin"})

      {:ok, raw_token} = Accounts.generate_invite_link(user)

      conn1 = get(conn, ~p"/admin/magic?token=#{raw_token}")
      assert redirected_to(conn1) == "/admin/events"

      conn2 = get(build_conn(), ~p"/admin/magic?token=#{raw_token}")
      assert redirected_to(conn2) == "/admin/login"
    end
  end

  describe "moderator auth plug" do
    test "unauthenticated access to /admin/topics redirects to login", %{conn: conn} do
      conn = get(conn, ~p"/admin/topics")
      assert redirected_to(conn) == "/admin/login"
    end

    test "authenticated access to /admin/topics is allowed", %{conn: conn} do
      conn =
        conn
        |> log_in_user()
        |> get(~p"/admin/topics")

      assert conn.status in [200, 302]
    end
  end

  describe "superadmin auth plug" do
    test "moderator cannot access /admin/users", %{conn: conn} do
      conn =
        conn
        |> log_in_user()
        |> get(~p"/admin/users")

      assert redirected_to(conn) == "/admin/events"
    end

    test "superadmin can access /admin/users", %{conn: conn} do
      conn =
        conn
        |> log_in_superadmin()
        |> get(~p"/admin/users")

      assert conn.status in [200, 302]
    end
  end

  describe "host lobby auth" do
    test "unauthenticated access to host lobby redirects to login", %{conn: conn} do
      conn = get(conn, ~p"/quiz/0000/host")
      assert redirected_to(conn) == "/admin/login"
    end
  end
end
