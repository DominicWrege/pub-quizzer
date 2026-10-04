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
          position: idx,
          status: "published"
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
    {:ok, view, _html} = live(log_in_user(conn), ~p"/quiz/#{event.code}/host")
    view
  end

  defp host_reveal_round(view) do
    view |> element("button[phx-click='next_question']", "Runde auflösen") |> render_click()
  end

  defp host_finish_quiz(view) do
    view |> element("#host-finish-quiz") |> render_click()
    view |> element("button[phx-click='confirm_finish_quiz']") |> render_click()
  end

  defp submit_all(event, teams, correct_for, view \\ nil) do
    for t <- teams do
      val = if t.id == correct_for.id, do: 1, else: 0
      Engine.submit_answer(event.id, t.id, val)
    end

    # LiveView broadcasts from the engine arrive as messages in the test
    # process; render/1 pumps them so the next render_click sees the updated
    # state (e.g. the "next question" button being enabled once all answered).
    if view, do: render(view)
  end

  setup do
    {event, topic, [team | _] = teams} = setup_event()
    start_engine(event)
    on_exit(fn -> stop_engine(event.id) end)
    {:ok, event: event, topic: topic, team: team, teams: teams}
  end

  describe "lobby" do
    test "puts the finish action in the top navigation without a separate moderator heading", %{
      conn: conn,
      event: event
    } do
      view = host_start_quiz(conn, event)
      assert has_element?(view, "header.sticky")
      assert has_element?(view, "header #host-quiz-menu #host-finish-quiz-menu")

      assert has_element?(view, "header #host-home[href='/admin/events']")
      assert has_element?(view, "header #host-finish-quiz")

      assert has_element?(
               view,
               "header #host-live-values[href='/admin/events/#{event.id}/results']"
             )

      assert has_element?(
               view,
               "header #host-quiz-menu #host-live-values-menu[href='/admin/events/#{event.id}/results']"
             )

      refute has_element?(view, "#host-quiz-menu #host-live-values")
      assert has_element?(view, "#host-live-values svg")

      refute has_element?(view, "main #host-finish-quiz")
      refute has_element?(view, "h1", "Moderator")
    end

    test "auto-starts to topic selection on mount", %{conn: conn, event: event, topic: _topic} do
      {:ok, view, html} = live(log_in_user(conn), ~p"/quiz/#{event.code}/host")

      assert html =~ event.code
      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :topic_selection
      assert has_element?(view, "button[phx-click='choose_topic'].px-3.py-2")
    end
  end

  describe "start quiz" do
    test "clicking start transitions to topic selection", %{
      conn: conn,
      event: event,
      topic: topic
    } do
      {:ok, view, _html} = live(log_in_user(conn), ~p"/quiz/#{event.code}/host")

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
            position: idx,
            status: "published"
          })
      end

      # Play round 1: team 1 wins
      Engine.start_quiz(event.id)
      Engine.choose_topic(event.id, topic.id, nil)
      submit_all(event, teams, team)
      Engine.reveal_round(event.id)
      Engine.next_round(event.id)

      # Host connects — should see waiting message, not topic buttons
      {:ok, view, html} = live(log_in_user(conn), ~p"/quiz/#{event.code}/host")

      assert html =~ "wählt das Thema"
      assert html =~ "Runde 2"
      assert has_element?(view, "button[phx-click='choose_topic']")
    end
  end

  describe "question phase" do
    test "presents the complete question and all answers as an accessible reading script", %{
      conn: conn,
      event: event,
      topic: topic
    } do
      view = host_start_quiz(conn, event)
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()

      assert has_element?(view, "#host-question-card[aria-labelledby='host-question-prompt']")
      assert has_element?(view, "#host-question-prompt", "What is 2+2?")
      assert has_element?(view, "#host-answer-options[aria-label='Antwortmöglichkeiten']")

      for {answer, index} <- Enum.with_index(["3", "4", "5", "6"]) do
        assert has_element?(view, "#host-answer-option-#{index}:nth-child(#{index + 1})")
        assert has_element?(view, "#host-answer-text-#{index}", answer)
      end

      refute has_element?(view, "#host-question-card [phx-click]")
    end

    test "the question card has extra top spacing", %{conn: conn, event: event, topic: topic} do
      view = host_start_quiz(conn, event)
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()
      assert has_element?(view, "#host-question-card.mt-4")
    end

    test "question context and controls share one header without branding", %{
      conn: conn,
      event: event,
      topic: topic
    } do
      view = host_start_quiz(conn, event)
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()
      assert has_element?(view, "header #host-question-topic", topic.name)
      assert has_element?(view, "header #host-answer-count")
      assert has_element?(view, "header #host-quiz-menu")
      refute has_element?(view, "header a[href='/']")
      refute has_element?(view, "main #host-answer-count")
      refute has_element?(view, "main #host-question-topic")
    end

    test "shows the question timer next to the advance button", %{
      conn: conn,
      event: event,
      topic: topic
    } do
      view = host_start_quiz(conn, event)
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()

      assert has_element?(view, ".sticky #host-question-timer[role='timer']", "00:00")
      assert has_element?(view, ".sticky [data-test='advance-button']")
      refute has_element?(view, "header #host-question-timer")
    end

    test "the topic name has normal text contrast", %{conn: conn, event: event, topic: topic} do
      view = host_start_quiz(conn, event)
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()
      assert has_element?(view, "#host-question-topic.text-base-content", topic.name)
      assert has_element?(view, "#host-question-card.text-base-content")
    end

    test "advancing with missing answers requires confirmation naming only missing teams", %{
      conn: conn,
      event: event,
      topic: topic,
      teams: [first, second, third]
    } do
      view = host_start_quiz(conn, event)
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()
      {:ok, _} = Engine.submit_answer(event.id, first.id, 1)
      refute has_element?(view, "[data-test='advance-button'][disabled]")
      view |> element("[data-test='advance-button']") |> render_click()
      assert has_element?(view, "#next-question-modal", second.name)
      assert has_element?(view, "#next-question-modal", third.name)
      refute has_element?(view, "#next-question-modal", first.name)
      assert has_element?(view, "#next-question-modal", "0 Punkte")
      {:ok, state} = Engine.get_state(event.id)
      assert state.question_index == 0

      view |> element("#next-question-modal-cancel") |> render_click()
      refute has_element?(view, "#next-question-modal")
      {:ok, state} = Engine.get_state(event.id)
      assert state.question_index == 0

      view |> element("[data-test='advance-button']") |> render_click()
      view |> element("#next-question-modal-confirm") |> render_click()
      {:ok, state} = Engine.get_state(event.id)
      assert state.question_index == 1
      assert state.answers[0] == %{first.id => 1}
      assert {:ok, _} = Engine.submit_answer(event.id, first.id, 1)
      host_reveal_round(view)
      assert has_element?(view, "#next-question-modal", second.name)
      view |> element("#next-question-modal-confirm") |> render_click()
      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :round_reveal
      assert state.standings == %{first.id => 2, second.id => 0, third.id => 0}
    end

    test "all teams answering allows immediate advancement without confirmation", %{
      conn: conn,
      event: event,
      topic: topic,
      team: team,
      teams: teams
    } do
      view = host_start_quiz(conn, event)
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()
      submit_all(event, teams, team, view)
      view |> element("[data-test='advance-button']") |> render_click()
      refute has_element?(view, "#next-question-modal")
      {:ok, state} = Engine.get_state(event.id)
      assert state.question_index == 1
    end

    test "a stale confirmation cannot skip another question", %{
      conn: conn,
      event: event,
      topic: topic
    } do
      view = host_start_quiz(conn, event)
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()
      view |> element("[data-test='advance-button']") |> render_click()
      assert has_element?(view, "#next-question-modal")
      {:ok, _} = Engine.next_question(event.id)
      refute has_element?(view, "#next-question-modal")
      render_click(view, "confirm_next_question")
      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :question
      assert state.question_index == 1
    end

    test "shows the teams still missing an answer for the current question", %{
      conn: conn,
      event: event,
      topic: topic,
      teams: [first, second, third]
    } do
      view = host_start_quiz(conn, event)
      refute has_element?(view, "#host-pending-teams")
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()

      assert has_element?(view, "#host-pending-teams[hidden]")
      view |> element("#host-answer-count") |> render_click()
      refute has_element?(view, "#host-pending-teams[hidden]")

      for team <- [first, second, third] do
        assert has_element?(view, "#host-pending-teams", team.name)
        refute has_element?(view, "#host-team-answer-#{team.id}")
      end

      {:ok, _} = Engine.submit_answer(event.id, first.id, 0)
      refute has_element?(view, "#host-pending-teams", first.name)
      assert has_element?(view, "#host-pending-teams", second.name)
      refute has_element?(view, "#host-team-answer-#{first.id}")

      {:ok, _} = Engine.submit_answer(event.id, second.id, 1)
      view |> element("#host-remove-team-#{third.id}") |> render_click()
      view |> element("#remove-team-modal-confirm") |> render_click()
      assert has_element?(view, "#host-pending-teams", "Alle Teams haben geantwortet")

      view |> element("button[data-test='advance-button']") |> render_click()

      assert has_element?(view, "#host-pending-teams[hidden]")

      for team <- [first, second] do
        assert has_element?(view, "#host-pending-teams", team.name)
        refute has_element?(view, "#host-team-answer-#{team.id}")
      end
    end

    test "the team management list updates connection status live", %{
      conn: conn,
      event: event,
      team: team
    } do
      view = host_start_quiz(conn, event)
      assert has_element?(view, "#teams-#{team.id} .badge", "Offline")
      assert has_element?(view, "#host-remove-team-#{team.id}", "Team entfernen")
      refute has_element?(view, "#host-teams p")

      send(view.pid, {:team_connected, team.id})
      assert has_element?(view, "#teams-#{team.id} .badge", "Online")

      send(view.pid, {:team_disconnected, team.id})
      assert has_element?(view, "#teams-#{team.id} .badge", "Offline")
    end

    test "the last team has a clear explanation instead of a disabled trash button", %{
      conn: conn,
      event: event,
      teams: [remaining, second, third]
    } do
      view = host_start_quiz(conn, event)
      {:ok, _} = Engine.remove_team(event.id, second.id)
      {:ok, _} = Engine.remove_team(event.id, third.id)
      refute has_element?(view, "[phx-click='ask_remove_team']")
      assert has_element?(view, "#host-last-team-#{remaining.id}", "Ein Team muss bleiben")
    end

    test "removal disconnects the team's devices and invalidates its session and QR", %{
      conn: conn,
      event: event,
      team: team
    } do
      host = host_start_quiz(conn, event)
      team_conn = Plug.Test.init_test_session(build_conn(), team_id: team.id)
      {:ok, team_view, _} = live(team_conn, ~p"/quiz/#{event.code}/lobby")
      {:ok, admin_view, _} = live(log_in_user(conn), ~p"/admin/events/#{event.id}")

      host |> element("#host-remove-team-#{team.id}") |> render_click()
      host |> element("#remove-team-modal-confirm") |> render_click()

      assert_redirect(team_view, "/")
      assert has_element?(admin_view, "a[href='/quiz/#{event.code}/host']")

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(team_conn, ~p"/quiz/#{event.code}/lobby")

      rejoin = post(recycle(team_conn), "/quiz/join", %{"code" => event.code})
      document = rejoin |> html_response(200) |> LazyHTML.from_document()
      assert document |> LazyHTML.query("#quiz-join-blocked") |> LazyHTML.to_tree() != []
      qr = get(build_conn(), ~p"/quiz/join/#{event.code}/#{team.slot_index + 1}")
      assert redirected_to(qr) == "/"
      assert is_nil(get_session(qr, :team_id))
    end

    test "confirmed removal updates answer counts for the remaining teams", %{
      conn: conn,
      event: event,
      topic: topic,
      teams: [first, second, disconnected]
    } do
      view = host_start_quiz(conn, event)
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()
      {:ok, _} = Engine.submit_answer(event.id, first.id, 1)
      {:ok, _} = Engine.submit_answer(event.id, second.id, 0)
      refute has_element?(view, "button[data-test='advance-button'][disabled]")

      view |> element("#host-remove-team-#{disconnected.id}") |> render_click()
      assert has_element?(view, "#remove-team-modal")
      assert Quiz.team_belongs_to_event?(disconnected.id, event.id)
      view |> element("#remove-team-modal-confirm") |> render_click()

      refute has_element?(view, "#host-team-#{disconnected.id}")
      assert has_element?(view, "[data-test='answered-badge']", "2 / 2")
      refute has_element?(view, "button[data-test='advance-button'][disabled]")
      view |> element("button[data-test='advance-button']") |> render_click()
      {:ok, state} = Engine.get_state(event.id)
      assert state.question_index == 1
    end

    test "cancelling team removal keeps the team", %{conn: conn, event: event, team: team} do
      view = host_start_quiz(conn, event)
      view |> element("#host-remove-team-#{team.id}") |> render_click()
      view |> element("#remove-team-modal-cancel") |> render_click()

      refute has_element?(view, "#remove-team-modal")
      assert has_element?(view, "#host-team-#{team.id}")
      assert Quiz.team_belongs_to_event?(team.id, event.id)
    end

    test "forged removal requests cannot target another event", %{conn: conn, event: event} do
      {:ok, other} = Quiz.create_event(%{team_count: 2})
      {:ok, foreign} = Quiz.claim_next_team_slot(other)
      view = host_start_quiz(conn, event)

      render_click(view, "ask_remove_team", %{"team_id" => Integer.to_string(foreign.id)})
      render_click(view, "confirm_remove_team")

      refute has_element?(view, "#remove-team-modal")
      assert Quiz.team_belongs_to_event?(foreign.id, other.id)
    end

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

      submit_all(event, teams, team, view)
      view |> element("button[phx-click='next_question']") |> render_click()

      assert has_element?(view, "button[phx-click='next_question']", "Runde auflösen")
    end

    test "keeps answer options visible without per-option counts after answers come in", %{
      conn: conn,
      event: event,
      topic: topic,
      teams: teams
    } do
      view = host_start_quiz(conn, event)
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()

      # The host sees the question and its fixed-order answer options.
      html = render(view)
      assert html =~ "data-test=\"answer-distribution\""
      assert has_element?(view, "[data-test='distribution-row']")

      # Submit 2 different answers: `team` picks 1 (correct), the rest pick 0
      [team | others] = teams
      Engine.submit_answer(event.id, team.id, 1)
      for t <- others, do: Engine.submit_answer(event.id, t.id, 0)
      render(view)

      refute has_element?(view, "[data-test='distribution-row'] > :nth-child(3)")

      html = render(view)
      # Answer submissions must not replace the question or add option counts.
      assert html =~ "What is 2+2?"
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

      submit_all(event, teams, team, view)
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
      submit_all(event, teams, team, view)

      view |> element("button[phx-click='next_question']") |> render_click()
      submit_all(event, teams, team, view)
      host_reveal_round(view)

      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :round_reveal

      html = render(view)
      # New shadow-console round_reveal: stats-first list (no paginated slide).
      assert html =~ "Auswertung"
      assert has_element?(view, "[data-test='round-stat-list']")
    end
  end

  describe "round reveal" do
    test "names only the teams tied for the round lead and keeps the tie visible with standings",
         %{
           conn: conn,
           event: event,
           topic: topic,
           teams: [first, second, third]
         } do
      view = host_start_quiz(conn, event)
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()

      for {team, answer} <- [{first, 1}, {second, 0}, {third, 0}] do
        {:ok, _} = Engine.submit_answer(event.id, team.id, answer)
      end

      view |> element("button[data-test='advance-button']") |> render_click()

      for {team, answer} <- [{first, 0}, {second, 1}, {third, 0}] do
        {:ok, _} = Engine.submit_answer(event.id, team.id, answer)
      end

      host_reveal_round(view)

      assert has_element?(view, "#host-round-tie", first.name)
      assert has_element?(view, "#host-round-tie", second.name)
      assert has_element?(view, "#host-round-tie", "je 1 Punkt")
      refute has_element?(view, "#host-round-tie", third.name)
      assert has_element?(view, "#host-round-tie", first.name)
      assert has_element?(view, "#host-round-tie", second.name)
    end

    test "names every team when the round is tied at zero points", %{
      conn: conn,
      event: event,
      topic: topic,
      teams: teams
    } do
      view = host_start_quiz(conn, event)
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()
      {:ok, _} = Engine.reveal_round(event.id)

      for team <- teams do
        assert has_element?(view, "#host-round-tie", team.name)
      end

      assert has_element?(view, "#host-round-tie", "je 0 Punkten")
    end

    test "shows the winner next to the next-topic button with stats collapsed and ranking open",
         %{
           conn: conn,
           event: event,
           topic: topic,
           team: team,
           teams: teams
         } do
      view = host_start_quiz(conn, event)
      view |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()

      submit_all(event, teams, team, view)
      view |> element("button[phx-click='next_question']") |> render_click()
      submit_all(event, teams, team, view)
      host_reveal_round(view)

      assert has_element?(view, ".sticky #host-round-winner", team.name)
      assert has_element?(view, ".sticky button[phx-click='next_round']", "Nächstes Thema wählen")
      refute has_element?(view, "#host-round-stats[open]")
      assert has_element?(view, "#host-round-standings[open]")
      assert has_element?(view, ~s|[id^="standing-"]|)
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

      submit_all(event, teams, team, view)
      view |> element("button[phx-click='next_question']") |> render_click()
      submit_all(event, teams, team, view)
      host_reveal_round(view)

      view |> element("button[phx-click='next_round']") |> render_click()

      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :finished

      html = render(view)
      assert html =~ "Quiz beendet!"
      assert has_element?(view, "button[phx-click='reveal_final_results']")

      assert view
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("a[href='/admin/events']")
             |> LazyHTML.to_tree()
             |> length() == 1

      view |> element("button[phx-click='reveal_final_results']") |> render_click()
      assert has_element?(view, ~s|#host-winner-line|)
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

      submit_all(event, teams, team, view)
      view |> element("button[phx-click='next_question']") |> render_click()
      submit_all(event, teams, team, view)
      host_reveal_round(view)

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

      submit_all(event, teams, team, view)
      view |> element("button[phx-click='next_question']") |> render_click()
      submit_all(event, teams, team, view)
      host_reveal_round(view)
      view |> element("button[phx-click='next_round']") |> render_click()

      html = render(view)
      assert html =~ "Quiz beendet!"
      assert has_element?(view, "button[phx-click='reveal_final_results']")

      view |> element("button[phx-click='reveal_final_results']") |> render_click()

      html = render(view)
      assert html =~ "Punkten!"
      assert has_element?(view, ~s|#host-winner-line|)

      assert has_element?(view, "header #host-home[href='/admin/events']")

      assert has_element?(
               view,
               "a[href='/admin/events/#{event.id}/results']",
               "Antworten ansehen"
             )

      assert view
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("a[href='/admin/events']")
             |> LazyHTML.to_tree()
             |> length() == 1
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
      {:ok, view, _html} = live(log_in_user(conn), ~p"/quiz/#{event.code}/host")

      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :question
      assert state.current_topic_id == topic.id

      html = render(view)
      assert html =~ "What is 2+2?"
    end
  end
end
