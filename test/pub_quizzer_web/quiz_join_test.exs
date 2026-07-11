defmodule PubQuizzerWeb.QuizJoinTest do
  use PubQuizzerWeb.ConnCase, async: false

  alias PubQuizzer.Quiz

  describe "POST /quiz/join" do
    test "with valid code assigns a team and redirects to lobby", %{conn: conn} do
      {:ok, event} = Quiz.create_event(%{team_count: 3})

      conn = post(conn, "/quiz/join", %{"code" => event.code})

      assert redirected_to(conn) == "/quiz/#{event.code}/lobby"
      assert get_session(conn, :team_id) != nil
      assert get_session(conn, :event_code) == event.code
    end

    test "with invalid code redirects back with error", %{conn: conn} do
      conn = post(conn, "/quiz/join", %{"code" => "9999"})
      assert redirected_to(conn) == "/join"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Kein Quiz mit diesem Code gefunden"
    end

    test "when quiz already started redirects back with error", %{conn: conn} do
      {:ok, event} = Quiz.create_event(%{team_count: 3})
      {:ok, _} = Quiz.start_event(event)

      conn = post(conn, "/quiz/join", %{"code" => event.code})
      assert redirected_to(conn) == "/join"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "bereits begonnen"
    end

    test "when quiz is full redirects back with error", %{conn: conn} do
      {:ok, event} = Quiz.create_event(%{team_count: 1})
      {:ok, _} = Quiz.claim_next_team_slot(event)

      conn = post(conn, "/quiz/join", %{"code" => event.code})
      assert redirected_to(conn) == "/join"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "voll"
    end

    test "reconnect: existing session for same event goes straight to lobby", %{conn: conn} do
      {:ok, event} = Quiz.create_event(%{team_count: 3})
      {:ok, team} = Quiz.claim_next_team_slot(event)

      conn =
        conn
        |> Plug.Test.init_test_session(team_id: team.id, event_code: event.code)
        |> post("/quiz/join", %{"code" => event.code})

      assert redirected_to(conn) == "/quiz/#{event.code}/lobby"
    end
  end

  describe "GET /join" do
    test "renders the join form", %{conn: conn} do
      conn = get(conn, "/join")
      assert html_response(conn, 200) =~ "Quiz beitreten"
      assert html_response(conn, 200) =~ "join-form"
    end
  end
end
