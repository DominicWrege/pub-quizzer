defmodule PubQuizzerWeb.Admin.ProfileLiveTest do
  use PubQuizzerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias PubQuizzer.Accounts

  describe "profile access" do
    test "superadmin can view and update their name", %{conn: conn} do
      {:ok, view, _html} =
        conn
        |> log_in_superadmin()
        |> live(~p"/admin/profile")

      assert has_element?(view, "#profile-form")

      user = Accounts.get_user_by_email("admin@example.com")

      view
      |> form("#profile-form", %{"user" => %{"name" => "Updated Name"}})
      |> render_submit()

      assert Accounts.get_user!(user.id).name == "Updated Name"
    end

    test "moderator is redirected away from profile", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/admin/events"}}} =
               conn
               |> log_in_user()
               |> live(~p"/admin/profile")
    end
  end
end
