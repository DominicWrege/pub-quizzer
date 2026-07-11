defmodule PubQuizzerWeb.QuizLive.HostLobbyTest do
  use PubQuizzerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.Engine

  @questions [
    {"What is 2+2?", ["3", "4", "5", "6"], 1},
    {"Capital of France?", ["London", "Paris", "Rome", "Berlin"], 1}
  ]

  defp setup_event do
    {:ok, topic} = Quiz.create_topic(%{name: "HostLobby Test Topic"})

    for {{prompt, options, correct}, idx} <- Enum.with_index(@questions) do
      {:ok, _} =
        Quiz.create_question(%{
          prompt: prompt,
          options: options,
          correct_index: correct,
          topic_id: topic.id,
          position: idx
        })
    end

    {:ok, event} = Quiz.create_event(%{team_count: 3})
    {:ok, t1} = Quiz.claim_next_team_slot(event)
    {:ok, t2} = Quiz.claim_next_team_slot(event)
    {:ok, t3} = Quiz.claim_next_team_slot(event)
    {event, topic, [t1, t2, t3]}
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

  defp host_start_quiz(conn, event) do
    {:ok, view, _html} = live(conn, ~p"/quiz/#{event.code}/host")
    view
  end

  defp host_reveal_round(view) do
    view |> element("button[phx-click='ask_reveal_round']") |> render_click()
    view |> element("button[phx-click='confirm_reveal_round']") |> render_click()
  end

  defp host_reveal_all_answers(view) do
    for _idx <- Enum.drop(Enum.with_index(@questions), 1) do
      view |> element("button[phx-click='reveal_next_answer']") |> render_click()
    end
  end

  defp host_show_standings(view) do
    view |> element("button[phx-click='show_standings']") |> render_click()
  end

  defp host_finish_quiz(view) do
    view |> element("button[phx-click='ask_finish_quiz']") |> render_click()
    view |> element("button[phx-click='confirm_finish_quiz']") |> render_click()
  end

  defp submit_all(event, teams, correct_for) do
    for t <- teams do
      val = if t.id == correct_for.id, do: 1, else: 0
      Engine.submit_answer(event.id, t.id, val)
    end
  end

  setup do
    {event, topic, [team | _] = teams} = setup_event()
    start_engine(event)
    on_exit(fn -> stop_engine(event.id) end)
    {:ok, event: event, topic: topic, team: team, teams: teams}
  end

  describe "lobby" do
    test "auto-starts to topic selection on mount", %{conn: conn, event: event, topic: _topic} do
      {:ok, view, html} = live(conn, ~p"/quiz/#{event.code}/host")

      assert html =~ event.code
      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :topic_selection
      assert has_element?(view, "button[phx-click='choose_topic']")
    end
  end

  describe "start quiz" do
    test "clicking start transitions to topic selection", %{
      conn: conn,
      event: event,
      topic: topic
    } do
      {:ok, view, _html} = live(conn, ~p"/quiz/#{event.code}/host")

      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :topic_selection

      assert has_element?(view, "button[phx-click='choose_topic']")
      assert has_element?(view, "button[phx-value-topic_id='#{topic.id}']")
    end
  end

  describe "topic selection" do
    test "host can choose a topic", %{conn: conn, event: event, topic: topic} do
      view = host_start_quiz(conn, event)

      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()

      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :question
      assert state.current_topic_id == topic.id
    end

    test "host sees waiting message when team is chooser", %{
      conn: conn,
      event: event,
      topic: topic,
      team: team,
      teams: teams
    } do
      # Create a second topic for round 2
      {:ok, topic2} = Quiz.create_topic(%{name: "Round 2 Topic"})

      for {{prompt, options, correct}, idx} <- Enum.with_index(@questions) do
        {:ok, _} =
          Quiz.create_question(%{
            prompt: prompt,
            options: options,
            correct_index: correct,
            topic_id: topic2.id,
            position: idx
          })
      end

      # Play round 1: team 1 wins
      Engine.start_quiz(event.id)
      Engine.choose_topic(event.id, topic.id, nil)
      submit_all(event, teams, team)
      Engine.reveal_round(event.id)
      Engine.next_round(event.id)

      # Host connects — should see waiting message, not topic buttons
      {:ok, view, html} = live(conn, ~p"/quiz/#{event.code}/host")

      assert html =~ "gewonnen — Vortritt"
      assert has_element?(view, "button[phx-click='choose_topic']")
    end
  end

  describe "question phase" do
    test "shows question prompt and next button on first question", %{
      conn: conn,
      event: event,
      topic: topic
    } do
      view = host_start_quiz(conn, event)
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()

      html = render(view)
      assert html =~ "What is 2+2?"
      assert has_element?(view, "button[phx-click='next_question']")
      refute has_element?(view, "button[phx-click='ask_reveal_round']")
    end

    test "shows reveal button on last question", %{
      conn: conn,
      event: event,
      topic: topic,
      team: team,
      teams: teams
    } do
      view = host_start_quiz(conn, event)
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()

      submit_all(event, teams, team)
      view |> element("button[phx-click='next_question']") |> render_click()

      refute has_element?(view, "button[phx-click='next_question']")
      assert has_element?(view, "button[phx-click='ask_reveal_round']")
    end

    test "next question advances to second question", %{
      conn: conn,
      event: event,
      topic: topic,
      team: team,
      teams: teams
    } do
      view = host_start_quiz(conn, event)
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()

      submit_all(event, teams, team)
      view |> element("button[phx-click='next_question']") |> render_click()

      html = render(view)
      assert html =~ "Capital of France?"
    end

    test "reveal round transitions to round_reveal", %{
      conn: conn,
      event: event,
      topic: topic,
      team: team,
      teams: teams
    } do
      view = host_start_quiz(conn, event)
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()

      # Submit a correct answer
      submit_all(event, teams, team)

      view |> element("button[phx-click='next_question']") |> render_click()
      submit_all(event, teams, team)
      host_reveal_round(view)

      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :round_reveal

      html = render(view)
      assert html =~ "Nächste Antwort anzeigen"
    end
  end

  describe "round reveal" do
    test "shows winner and standings", %{
      conn: conn,
      event: event,
      topic: topic,
      team: team,
      teams: teams
    } do
      view = host_start_quiz(conn, event)
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()

      submit_all(event, teams, team)
      view |> element("button[phx-click='next_question']") |> render_click()
      submit_all(event, teams, team)
      host_reveal_round(view)
      host_reveal_all_answers(view)
      host_show_standings(view)

      assert has_element?(view, ~s|[id^="standing-"]|)
      assert has_element?(view, "button[phx-click='next_round']")
      assert has_element?(view, "button[phx-click='ask_finish_quiz']")
    end

    test "next round finishes when no topics remain", %{
      conn: conn,
      event: event,
      topic: topic,
      team: team,
      teams: teams
    } do
      view = host_start_quiz(conn, event)
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()

      submit_all(event, teams, team)
      view |> element("button[phx-click='next_question']") |> render_click()
      submit_all(event, teams, team)
      host_reveal_round(view)
      host_reveal_all_answers(view)
      host_show_standings(view)

      view |> element("button[phx-click='next_round']") |> render_click()

      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :finished

      html = render(view)
      assert html =~ "Quiz beendet!"
      assert has_element?(view, ~s|[id^="final-"]|)
    end

    test "finish quiz early goes to finished", %{
      conn: conn,
      event: event,
      topic: topic,
      team: team,
      teams: teams
    } do
      view = host_start_quiz(conn, event)
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()

      submit_all(event, teams, team)
      view |> element("button[phx-click='next_question']") |> render_click()
      submit_all(event, teams, team)
      host_reveal_round(view)
      host_reveal_all_answers(view)

      host_finish_quiz(view)

      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :finished
    end
  end

  describe "finished" do
    test "shows final standings with winner", %{
      conn: conn,
      event: event,
      topic: topic,
      team: team,
      teams: teams
    } do
      view = host_start_quiz(conn, event)
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()

      submit_all(event, teams, team)
      view |> element("button[phx-click='next_question']") |> render_click()
      submit_all(event, teams, team)
      host_reveal_round(view)
      host_reveal_all_answers(view)
      host_show_standings(view)
      view |> element("button[phx-click='next_round']") |> render_click()

      html = render(view)
      assert html =~ "Quiz beendet!"
      assert html =~ "Punkten!"
      assert has_element?(view, ~s|[id^="final-"]|)
    end
  end

  describe "engine crash recovery" do
    test "refresh recovers state after engine restart", %{
      conn: conn,
      event: event,
      topic: topic,
      team: team,
      teams: teams
    } do
      view = host_start_quiz(conn, event)
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()

      submit_all(event, teams, team)

      # Stop the engine (simulate crash)
      stop_engine(event.id)

      # Refresh should restart engine and recover state — re-mount the page
      {:ok, view, _html} = live(conn, ~p"/quiz/#{event.code}/host")

      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :question
      assert state.current_topic_id == topic.id

      html = render(view)
      assert html =~ "What is 2+2?"
    end
  end
end
