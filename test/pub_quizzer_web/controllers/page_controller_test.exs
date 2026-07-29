defmodule PubQuizzerWeb.PageControllerTest do
  use PubQuizzerWeb.ConnCase

  test "GET / redirects to setup when no users exist", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/setup"
  end

  test "GET / shows home page when users exist", %{conn: conn} do
    Accounts.create_user!(%{email: "host@test.com", name: "Host", role: "moderator"})
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Beitreten"
  end
end
