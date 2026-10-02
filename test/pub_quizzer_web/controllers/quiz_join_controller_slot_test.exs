defmodule PubQuizzerWeb.QuizJoinControllerSlotTest do
  use PubQuizzerWeb.ConnCase, async: false

  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.Engine

  setup do
    {:ok, event} = Quiz.create_event(%{team_count: 3})
    start_supervised!({Engine, event.id})
    {:ok, event: event}
  end

  describe "GET /quiz/join/:code/:slot" do
    test "claims the specific slot, sets session, redirects to lobby", %{conn: conn, event: event} do
      conn = get(conn, ~p"/quiz/join/#{event.code}/1")

      assert redirected_to(conn) == "/quiz/#{event.code}/lobby/#{hd(event.teams).link_code}"
      assert get_session(conn, :event_code) == event.code
      team_id = get_session(conn, :team_id)
      assert team_id != nil

      team = Quiz.get_team!(team_id)
      assert team.slot_index == 0
      assert team.claimed_at != nil
    end

    test "is idempotent — re-scanning an already-claimed slot re-joins the same team", %{
      conn: conn,
      event: event
    } do
      first_conn = get(conn, ~p"/quiz/join/#{event.code}/2")
      first_team_id = get_session(first_conn, :team_id)

      second_conn = get(build_conn(), ~p"/quiz/join/#{event.code}/2")
      second_team_id = get_session(second_conn, :team_id)

      assert first_team_id == second_team_id
    end

    test "rejects slot out of range with a flash", %{conn: conn, event: event} do
      conn = get(conn, ~p"/quiz/join/#{event.code}/99")
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "ngültig"
    end

    test "a fresh browser can rejoin a claimed QR slot during the quiz", %{
      conn: conn,
      event: event
    } do
      first_conn = get(conn, ~p"/quiz/join/#{event.code}/2")
      team_id = get_session(first_conn, :team_id)
      {:ok, _} = Engine.start_quiz(event.id)

      conn = get(build_conn(), ~p"/quiz/join/#{event.code}/2")

      assert redirected_to(conn) ==
               "/quiz/#{event.code}/lobby/#{Enum.at(event.teams, 1).link_code}"

      assert get_session(conn, :team_id) == team_id
      {:ok, state} = Engine.get_state(event.id)
      assert Enum.map(state.teams, & &1.id) == [team_id]
    end

    test "an unused QR slot cannot join after the quiz starts", %{conn: conn, event: event} do
      {:ok, _} = Engine.start_quiz(event.id)

      conn = get(conn, ~p"/quiz/join/#{event.code}/2")

      document = conn |> html_response(200) |> LazyHTML.from_document()
      assert document |> LazyHTML.query("#quiz-join-blocked") |> LazyHTML.to_tree() != []
      assert is_nil(get_session(conn, :team_id))
      assert is_nil(Quiz.get_team!(Enum.at(event.teams, 1).id).claimed_at)
    end

    test "rejects zero / non-numeric slot", %{conn: conn, event: event} do
      conn = get(conn, ~p"/quiz/join/#{event.code}/0")
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "ngültig"
    end

    test "rejects unknown event code", %{conn: conn} do
      conn = get(conn, ~p"/quiz/join/NOCODE/1")
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Kein Quiz"
    end
  end
end
