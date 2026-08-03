defmodule PubQuizzerWeb.Admin.UserLiveTest do
  use PubQuizzerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias PubQuizzer.Accounts

  defp auth_conn(conn) do
    log_in_superadmin(conn)
  end

  defp create_user(attrs) do
    {:ok, user} =
      Accounts.create_user(
        Map.merge(
          %{name: "Some User", email: "user@test.com", role: "moderator", active: true},
          Map.new(attrs)
        )
      )

    user
  end

  describe "index" do
    test "renders the user list with created users present", %{conn: conn} do
      create_user(name: "Zoe", email: "zoe@test.com")
      create_user(name: "Anna", email: "anna@test.com")
      create_user(name: "Max", email: "max@test.com")

      {:ok, _view, html} = conn |> auth_conn() |> live(~p"/admin/users")

      assert html =~ "Zoe"
      assert html =~ "Anna"
      assert html =~ "Max"
    end
  end

  describe "edit user" do
    test "opens the edit dialog and saves changes", %{conn: conn} do
      user = create_user(name: "Old Name", email: "old@test.com")

      {:ok, view, _html} = conn |> auth_conn() |> live(~p"/admin/users")

      view
      |> element("#user-#{user.id} button[phx-click='start_edit_user']")
      |> render_click()

      assert has_element?(view, "#edit-user-form")

      view
      |> form("#edit-user-form", %{
        "user" => %{"name" => "New Name", "email" => "new@test.com"}
      })
      |> render_submit()

      updated = Accounts.get_user!(user.id)
      assert updated.name == "New Name"
      assert updated.email == "new@test.com"
      refute has_element?(view, "#edit-user-form")
    end

    test "shows an error for duplicate email", %{conn: conn} do
      create_user(name: "User A", email: "a@x.com")
      user_b = create_user(name: "User B", email: "b@x.com")

      {:ok, view, _html} = conn |> auth_conn() |> live(~p"/admin/users")

      view
      |> element("#user-#{user_b.id} button[phx-click='start_edit_user']")
      |> render_click()

      assert has_element?(view, "#edit-user-form")

      view
      |> form("#edit-user-form", %{"user" => %{"email" => "a@x.com"}})
      |> render_submit()

      assert has_element?(view, "#edit-user-form")
    end
  end

  describe "authorization" do
    test "non-superadmin is redirected to events", %{conn: conn} do
      conn = log_in_user(conn)

      assert {:error, {:redirect, %{to: "/admin/events"}}} =
               live(conn, ~p"/admin/users")
    end
  end
end
