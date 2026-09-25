defmodule PubQuizzerWeb.SetupLiveTest do
  use PubQuizzerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias PubQuizzer.Accounts

  test "creating the first superadmin redirects to login", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/setup")

    view
    |> form("#setup-form", %{"email" => "admin@example.com", "name" => "Admin"})
    |> render_submit()

    assert_redirect(view, "/admin/login")

    assert %{role: "superadmin", login_code_hash: nil} =
             Accounts.get_user_by_email("admin@example.com")
  end
end
