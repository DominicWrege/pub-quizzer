defmodule PubQuizzerWeb.AdminSessionControllerTest do
  use PubQuizzerWeb.ConnCase

  describe "GET /admin/login/status" do
    test "returns authenticated: false when logged out", %{conn: conn} do
      conn = get(conn, ~p"/admin/login/status")
      assert json_response(conn, 200) == %{"authenticated" => false}
    end

    test "returns authenticated: true when logged in", %{conn: conn} do
      conn = conn |> log_in_user() |> get(~p"/admin/login/status")
      assert json_response(conn, 200) == %{"authenticated" => true}
    end
  end
end
