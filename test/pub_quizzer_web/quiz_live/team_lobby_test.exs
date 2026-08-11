defmodule PubQuizzerWeb.QuizLive.TeamLobbyTest do
  use PubQuizzerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.Engine

  @questions [
    {"What is 2+2?", ["3", "4", "5", "6"], 1},
    {"Capital of France?", ["London", "Paris", "Rome", "Berlin"], 1}
  ]

  defp setup_event do
    {:ok, topic} = Quiz.create_topic(%{name: "TeamLobby Test Topic"})

    for {{prompt, options, correct}, idx} <- Enum.with_index(@questions) do
      {:ok, _} =
        Quiz.create_question(%{
          prompt: prompt,
          options: options,
          correct_index: correct,
          topic_id: topic.id,
          position: idx,
          status: "published"
        })
    end

    {:ok, event} = Quiz.create_event(%{team_count: 3})
    {:ok, team} = Quiz.claim_next_team_slot(event)
    {event, topic, team}
  end

  defp start_engine(event) do
    {:ok, pid} = Engine.ensure_started(event.id)
    Ecto.Adapters.SQL.Sandbox.allow(PubQuizzer.Repo, self(), pid)
    :ok
  end

  defp stop_engine(event_id) do
    GenServer.stop(Engine.via_tuple(event_id), :normal)
  catch
    :exit, _ -> :ok
  end

  # Connect as a team device — sets session team_id
  defp team_conn(conn, team) do
    Plug.Test.init_test_session(conn, team_id: team.id)
  end

  setup do
    {event, topic, team} = setup_event()
    start_engine(event)
    on_exit(fn -> stop_engine(event.id) end)
    {:ok, event: event, topic: topic, team: team}
  end

  describe "lobby" do
    test "shows team name and waiting message", %{conn: conn, event: event, team: team} do
      {:ok, _view, html} =
        conn |> team_conn(team) |> live(~p"/quiz/#{event.code}/lobby")

      assert html =~ team.name
      assert html =~ "Warte auf den Quiz-Start"
      assert html =~ event.code
    end
  end

  describe "topic selection" do
    test "shows host picking message for round 1", %{conn: conn, event: event, team: team} do
      Engine.start_quiz(event.id)

      {:ok, _view, html} =
        conn |> team_conn(team) |> live(~p"/quiz/#{event.code}/lobby")

      assert html =~ "Der Moderator wählt ein Thema"
    end

    test "chooser team sees topic buttons and can pick a topic", %{
      conn: conn,
      event: event,
      topic: topic,
      team: team
    } do
      # Create a second topic so there's one available for round 2
      {:ok, topic2} = Quiz.create_topic(%{name: "Round 2 Topic"})

      for {{prompt, options, correct}, idx} <- Enum.with_index(@questions) do
        {:ok, _} =
          Quiz.create_question(%{
            prompt: prompt,
            options: options,
            correct_index: correct,
            topic_id: topic2.id,
            position: idx,
            status: "published"
          })
      end

      # Claim a second team so there's a competitor
      {:ok, team2} = Quiz.claim_next_team_slot(event)

      # Play round 1: team 1 answers correctly, team 2 answers wrong
      Engine.start_quiz(event.id)
      Engine.choose_topic(event.id, topic.id, nil)
      Engine.submit_answer(event.id, team.id, 1)
      Engine.submit_answer(event.id, team2.id, 0)
      Engine.reveal_round(event.id)
      Engine.next_round(event.id)

      # Now team 1 has priority — connect and verify they see the alert
      {:ok, view, html} =
        conn |> team_conn(team) |> live(~p"/quiz/#{event.code}/lobby")

      assert html =~ "Dein Team hat Runde 1 gewonnen"
      refute has_element?(view, "button[phx-click='choose_topic']")

      # Host chooses the topic instead
      Engine.choose_topic(event.id, topic2.id, nil)

      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :question
      assert state.current_topic_id == topic2.id
    end

    test "non-chooser team sees waiting message", %{
      conn: conn,
      event: event,
      topic: topic,
      team: team
    } do
      {:ok, topic2} = Quiz.create_topic(%{name: "Round 2 Topic"})

      for {{prompt, options, correct}, idx} <- Enum.with_index(@questions) do
        {:ok, _} =
          Quiz.create_question(%{
            prompt: prompt,
            options: options,
            correct_index: correct,
            topic_id: topic2.id,
            position: idx,
            status: "published"
          })
      end

      {:ok, team2} = Quiz.claim_next_team_slot(event)

      Engine.start_quiz(event.id)
      Engine.choose_topic(event.id, topic.id, nil)
      Engine.submit_answer(event.id, team.id, 1)
      Engine.submit_answer(event.id, team2.id, 0)
      Engine.reveal_round(event.id)
      Engine.next_round(event.id)

      # team2 is NOT the chooser — should see waiting message
      {:ok, view, html} =
        conn |> team_conn(team2) |> live(~p"/quiz/#{event.code}/lobby")

      assert html =~ "hat Vortritt"
      refute has_element?(view, "button[phx-click='choose_topic']")
    end
  end

  describe "question phase" do
    test "shows option buttons without question or answers", %{
      conn: conn,
      event: event,
      topic: topic,
      team: team
    } do
      Engine.start_quiz(event.id)
      Engine.choose_topic(event.id, topic.id, nil)

      {:ok, view, html} =
        conn |> team_conn(team) |> live(~p"/quiz/#{event.code}/lobby")

      assert has_element?(view, "button[phx-click='select_answer']")
      refute html =~ "What is 2+2?"
    end

    test "clicking an option submits the answer", %{
      conn: conn,
      event: event,
      topic: topic,
      team: team
    } do
      Engine.start_quiz(event.id)
      Engine.choose_topic(event.id, topic.id, nil)

      {:ok, view, _html} =
        conn |> team_conn(team) |> live(~p"/quiz/#{event.code}/lobby")

      view |> element("button[phx-click='select_answer'][phx-value-index='0']") |> render_click()

      {:ok, state} = Engine.get_state(event.id)
      answers = Map.get(state.answers, 0, %{})
      assert Map.has_key?(answers, team.id)
    end

    test "shows answered message after submitting", %{
      conn: conn,
      event: event,
      topic: topic,
      team: team
    } do
      Engine.start_quiz(event.id)
      Engine.choose_topic(event.id, topic.id, nil)

      {:ok, view, _html} =
        conn |> team_conn(team) |> live(~p"/quiz/#{event.code}/lobby")

      view |> element("button[phx-click='select_answer'][phx-value-index='0']") |> render_click()

      html = render(view)
      assert html =~ "Antwort abgegeben!"
    end

    test "shows no question text or image on team device", %{conn: conn, event: event, team: team} do
      {:ok, topic_with_image} = Quiz.create_topic(%{name: "Image Topic"})

      {:ok, _} =
        Quiz.create_question(%{
          prompt: "What is in this picture?",
          options: ["A", "B", "C", "D"],
          correct_index: 0,
          topic_id: topic_with_image.id,
          position: 0,
          image: "/uploads/test_image.jpg",
          status: "published"
        })

      Engine.start_quiz(event.id)
      Engine.choose_topic(event.id, topic_with_image.id, nil)

      {:ok, _view, html} =
        conn |> team_conn(team) |> live(~p"/quiz/#{event.code}/lobby")

      refute html =~ "What is in this picture?"
      refute html =~ "test_image.jpg"
      refute html =~ "Fragebild"
    end
  end

  describe "round reveal" do
    test "shows standings", %{
      conn: conn,
      event: event,
      topic: topic,
      team: team
    } do
      Engine.start_quiz(event.id)
      Engine.choose_topic(event.id, topic.id, nil)
      Engine.submit_answer(event.id, team.id, 1)
      Engine.reveal_round(event.id)
      Engine.reveal_standings(event.id)

      {:ok, view, _html} =
        conn |> team_conn(team) |> live(~p"/quiz/#{event.code}/lobby")

      assert has_element?(view, ~s|[id^="team-standing-"]|)
    end

    test "shows winner banner when team won", %{
      conn: conn,
      event: event,
      topic: topic,
      team: team
    } do
      Engine.start_quiz(event.id)
      Engine.choose_topic(event.id, topic.id, nil)
      Engine.submit_answer(event.id, team.id, 1)
      Engine.reveal_round(event.id)

      {:ok, _view, html} =
        conn |> team_conn(team) |> live(~p"/quiz/#{event.code}/lobby")

      assert html =~ "Dein Team hat Runde"
    end
  end

  describe "finished" do
    test "shows final standings", %{
      conn: conn,
      event: event,
      topic: topic,
      team: team
    } do
      Engine.start_quiz(event.id)
      Engine.choose_topic(event.id, topic.id, nil)
      Engine.submit_answer(event.id, team.id, 1)
      Engine.reveal_round(event.id)
      Engine.next_round(event.id)
      Engine.reveal_final_results(event.id)

      {:ok, view, html} =
        conn |> team_conn(team) |> live(~p"/quiz/#{event.code}/lobby")

      assert html =~ "Quiz beendet!"
      assert has_element?(view, ~s|[id^="team-final-"]|)
    end
  end

  describe "without session" do
    test "redirects to /join when no team_id in session", %{conn: conn, event: event} do
      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn, ~p"/quiz/#{event.code}/lobby")

      assert to == "/"
    end
  end
end
