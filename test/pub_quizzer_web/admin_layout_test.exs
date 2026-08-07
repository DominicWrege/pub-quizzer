defmodule PubQuizzerWeb.AdminLayoutTest do
  use PubQuizzerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "mobile nav drawer" do
    test "mobile nav drawer renders nav links for moderator", %{conn: conn} do
      {:ok, view, _html} =
        conn
        |> log_in_user()
        |> live(~p"/admin/events")

      assert has_element?(view, "#nav-drawer-toggle")
      assert has_element?(view, "label[for='nav-drawer-toggle']")
      assert has_element?(view, "aside a[href='/admin/events']")
      assert has_element?(view, "aside a[href='/admin/topics']")
      refute has_element?(view, "aside a[href='/admin/users']")
    end

    test "mobile nav drawer shows Benutzer link for superadmin", %{conn: conn} do
      {:ok, view, _html} =
        conn
        |> log_in_superadmin()
        |> live(~p"/admin/events")

      assert has_element?(view, "aside a[href='/admin/users']")
    end

    test "Profil link is in the avatar dropdown for superadmin, never in the drawer", %{
      conn: conn
    } do
      {:ok, view_super, _html} =
        conn
        |> log_in_superadmin()
        |> live(~p"/admin/events")

      assert has_element?(view_super, "a[href='/admin/profile']")
      refute has_element?(view_super, "aside a[href='/admin/profile']")
    end

    test "moderator sees no Profil link anywhere", %{conn: conn} do
      {:ok, view, _html} =
        conn
        |> log_in_user()
        |> live(~p"/admin/events")

      # Profil link is superadmin-only
      refute has_element?(view, "a[href='/admin/profile']")

      # Logout lives in the avatar dropdown (a CSRF-protected POST form), not the
      # mobile nav drawer.
      refute has_element?(view, "aside form[action='/admin/logout']")
      assert has_element?(view, "details form[action='/admin/logout']")
    end
  end
end
