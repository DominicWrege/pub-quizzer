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

    test "GET /admin/login when already authed redirects to topics", %{conn: conn} do
      {:ok, _} =
        Accounts.create_user(%{email: "admin@test.com", name: "Admin", role: "superadmin"})

      conn =
        conn
        |> log_in_user()
        |> get(~p"/admin/login")

      assert redirected_to(conn) == "/admin/topics"
    end

    test "POST /admin/login with known email renders code entry page", %{conn: conn} do
      {:ok, user} =
        Accounts.create_user(%{
          email: "admin@test.com",
          name: "Admin",
          role: "superadmin",
          active: true
        })

      conn = post(conn, ~p"/admin/login", %{"email" => user.email})
      assert html_response(conn, 200) =~ "Code eingeben"
      assert html_response(conn, 200) =~ user.email
      assert html_response(conn, 200) =~ "admin-code-form"
    end

    test "POST /admin/login with unknown email shows error", %{conn: conn} do
      {:ok, _} =
        Accounts.create_user(%{email: "admin@test.com", name: "Admin", role: "superadmin"})

      conn = post(conn, ~p"/admin/login", %{"email" => "nobody@test.com"})
      assert redirected_to(conn) == "/admin/login"
      assert %{message: msg} = Phoenix.Flash.get(conn.assigns.flash, :error)
      assert msg =~ "nicht gefunden"
    end

    test "POST /admin/logout clears session", %{conn: conn} do
      conn =
        conn
        |> log_in_user()
        |> post(~p"/admin/logout")

      assert redirected_to(conn) == "/admin/login"
    end
  end

  describe "login code verification" do
    test "valid code creates session and redirects", %{conn: conn} do
      {:ok, user} =
        Accounts.create_user(%{email: "admin@test.com", name: "Admin", role: "superadmin"})

      {:ok, code} = Accounts.generate_login_code_for(user)

      conn = post(conn, ~p"/admin/login/verify", %{"email" => user.email, "code" => code})

      assert redirected_to(conn) == "/admin/topics"
      assert get_session(conn, :user_id) == user.id
    end

    test "code is case-insensitive and trimmed", %{conn: conn} do
      {:ok, user} =
        Accounts.create_user(%{email: "admin@test.com", name: "Admin", role: "superadmin"})

      {:ok, code} = Accounts.generate_login_code_for(user)

      conn =
        post(conn, ~p"/admin/login/verify", %{
          "email" => user.email,
          "code" => "  #{String.downcase(code)}  "
        })

      assert redirected_to(conn) == "/admin/topics"
    end

    test "invalid code re-renders with error", %{conn: conn} do
      {:ok, user} =
        Accounts.create_user(%{email: "admin@test.com", name: "Admin", role: "superadmin"})

      {:ok, _code} = Accounts.generate_login_code_for(user)

      conn = post(conn, ~p"/admin/login/verify", %{"email" => user.email, "code" => "ZZZZZZ"})

      assert html_response(conn, 200) =~ "Ungültiger Code"
      assert get_session(conn, :user_id) == nil
    end

    test "expired code shows error", %{conn: conn} do
      {:ok, user} =
        Accounts.create_user(%{email: "admin@test.com", name: "Admin", role: "superadmin"})

      {:ok, code} = Accounts.generate_login_code_for(user)

      eleven_min_ago =
        DateTime.utc_now()
        |> DateTime.add(-11, :minute)
        |> DateTime.truncate(:second)

      {:ok, _} =
        user
        |> Ecto.Changeset.change(%{login_code_sent_at: eleven_min_ago})
        |> PubQuizzer.Repo.update()

      conn = post(conn, ~p"/admin/login/verify", %{"email" => user.email, "code" => code})

      assert html_response(conn, 200) =~ "abgelaufen"
      assert get_session(conn, :user_id) == nil
    end

    test "code is single-use", %{conn: conn} do
      {:ok, user} =
        Accounts.create_user(%{email: "admin@test.com", name: "Admin", role: "superadmin"})

      {:ok, code} = Accounts.generate_login_code_for(user)

      conn1 = post(conn, ~p"/admin/login/verify", %{"email" => user.email, "code" => code})
      assert redirected_to(conn1) == "/admin/topics"

      conn2 =
        build_conn()
        |> post(~p"/admin/login/verify", %{"email" => user.email, "code" => code})

      assert html_response(conn2, 200) =~ "Ungültiger Code"
    end

    test "code is invalidated after 5 failed attempts", %{conn: conn} do
      {:ok, user} =
        Accounts.create_user(%{email: "admin@test.com", name: "Admin", role: "superadmin"})

      {:ok, code} = Accounts.generate_login_code_for(user)

      for _ <- 1..5 do
        conn =
          build_conn()
          |> post(~p"/admin/login/verify", %{"email" => user.email, "code" => "ZZZZZZ"})

        assert html_response(conn, 200) =~ "Ungültiger Code"
      end

      conn = post(conn, ~p"/admin/login/verify", %{"email" => user.email, "code" => code})
      assert html_response(conn, 200) =~ "Zu viele Fehlversuche"
      assert get_session(conn, :user_id) == nil
    end

    test "resend issues a fresh code and re-renders", %{conn: conn} do
      {:ok, user} =
        Accounts.create_user(%{email: "admin@test.com", name: "Admin", role: "superadmin"})

      conn = post(conn, ~p"/admin/login/resend", %{"email" => user.email})

      assert html_response(conn, 200) =~ "Code eingeben"
      assert html_response(conn, 200) =~ "code-resent"
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

      assert redirected_to(conn) == "/admin/topics"
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
