defmodule PubQuizzerWeb.QuizJoinTest do
  use PubQuizzerWeb.ConnCase, async: false

  alias PubQuizzer.Quiz

  defp assert_join_blocked(conn) do
    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert document
           |> LazyHTML.query("#quiz-join-blocked.alert[role='alert']")
           |> LazyHTML.to_tree() != []

    assert document |> LazyHTML.query("#join-existing-team") |> LazyHTML.to_tree() != []
  end

  describe "POST /quiz/join" do
    test "with valid code assigns a team and redirects to lobby", %{conn: conn} do
      {:ok, event} = Quiz.create_event(%{team_count: 3})

      conn = post(conn, "/quiz/join", %{"code" => event.code})

      team = Quiz.get_team!(get_session(conn, :team_id))
      assert redirected_to(conn) == "/quiz/#{event.code}/lobby/#{team.link_code}"
      assert get_session(conn, :team_id) != nil
      assert get_session(conn, :event_code) == event.code
    end

    test "with invalid code redirects back with error", %{conn: conn} do
      conn = post(conn, "/quiz/join", %{"code" => "9999"})
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Kein Quiz mit diesem Code gefunden"
    end

    test "when quiz already started redirects back with error", %{conn: conn} do
      {:ok, event} = Quiz.create_event(%{team_count: 3})
      {:ok, _} = Quiz.start_event(event)

      conn = post(conn, "/quiz/join", %{"code" => event.code})
      assert_join_blocked(conn)
    end

    test "when quiz is full redirects back with error", %{conn: conn} do
      {:ok, event} = Quiz.create_event(%{team_count: 1})
      {:ok, _} = Quiz.claim_next_team_slot(event)

      conn = post(conn, "/quiz/join", %{"code" => event.code})
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "voll"
    end

    test "reconnect: existing session for same event goes straight to lobby", %{conn: conn} do
      {:ok, event} = Quiz.create_event(%{team_count: 3})
      {:ok, team} = Quiz.claim_next_team_slot(event)

      conn =
        conn
        |> Plug.Test.init_test_session(team_id: team.id, event_code: event.code)
        |> post("/quiz/join", %{"code" => event.code})

      assert redirected_to(conn) == "/quiz/#{event.code}/lobby/#{team.link_code}"
    end
  end

  describe "rejoining after the quiz starts" do
    test "joining puts a stable three-letter team code in the lobby URL", %{conn: conn} do
      {:ok, event} = Quiz.create_event(%{team_count: 12})
      codes = Enum.map(event.teams, &Map.get(&1, :link_code, ""))
      assert Enum.all?(codes, &Regex.match?(~r/^[a-z]{3}$/, &1))
      assert length(Enum.uniq(codes)) == 12

      joined = post(conn, "/quiz/join", %{"code" => event.code})
      team_id = get_session(joined, :team_id)
      team = Quiz.get_team!(team_id)
      assert redirected_to(joined) == "/quiz/#{event.code}/lobby/#{team.link_code}"

      {:ok, _} = Quiz.start_event(event)
      rejoined = get(build_conn(), "/quiz/join/#{event.code}/#{team.link_code}")
      assert redirected_to(rejoined) == redirected_to(joined)
      assert get_session(rejoined, :team_id) == team_id
      assert Enum.count(Quiz.list_teams_for_event(event.id), & &1.claimed_at) == 1
    end

    for status <- ~w(topic_selection question round_reveal finished) do
      test "an existing session can rejoin in #{status}", %{conn: conn} do
        {:ok, event} = Quiz.create_event(%{team_count: 3})
        {:ok, team} = Quiz.claim_next_team_slot(event)
        {:ok, _} = Quiz.update_event(event, %{status: unquote(status)})

        conn =
          conn
          |> Plug.Test.init_test_session(team_id: team.id)
          |> post("/quiz/join", %{"code" => event.code})

        assert redirected_to(conn) == "/quiz/#{event.code}/lobby/#{team.link_code}"
        assert get_session(conn, :team_id) == team.id
        assert get_session(conn, :event_code) == event.code
        assert Enum.count(Quiz.list_teams_for_event(event.id), & &1.claimed_at) == 1
      end
    end

    test "a code link restores an existing team session", %{conn: conn} do
      {:ok, event} = Quiz.create_event(%{team_count: 3})
      {:ok, team} = Quiz.claim_next_team_slot(event)
      {:ok, _} = Quiz.start_event(event)

      conn =
        conn
        |> Plug.Test.init_test_session(team_id: team.id)
        |> get(~p"/quiz/join/#{event.code}")

      assert redirected_to(conn) == "/quiz/#{event.code}/lobby/#{team.link_code}"
      assert get_session(conn, :team_id) == team.id
    end

    test "an unclaimed slot in the session cannot rejoin", %{conn: conn} do
      {:ok, event} = Quiz.create_event(%{team_count: 3})
      {:ok, _} = Quiz.start_event(event)

      conn =
        conn
        |> Plug.Test.init_test_session(team_id: hd(event.teams).id)
        |> post("/quiz/join", %{"code" => event.code})

      assert_join_blocked(conn)
      assert Enum.all?(Quiz.list_teams_for_event(event.id), &is_nil(&1.claimed_at))
    end

    test "a session from another event cannot join a running quiz", %{conn: conn} do
      {:ok, other} = Quiz.create_event(%{team_count: 2})
      {:ok, team} = Quiz.claim_next_team_slot(other)
      {:ok, event} = Quiz.create_event(%{team_count: 3})
      {:ok, _} = Quiz.start_event(event)

      conn =
        conn
        |> Plug.Test.init_test_session(team_id: team.id)
        |> post("/quiz/join", %{"code" => event.code})

      assert_join_blocked(conn)
      assert Enum.all?(Quiz.list_teams_for_event(event.id), &is_nil(&1.claimed_at))
    end
  end
end
