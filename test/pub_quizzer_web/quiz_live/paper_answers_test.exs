defmodule PubQuizzerWeb.QuizLive.PaperAnswersTest do
  use PubQuizzerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias PubQuizzer.{Quiz, Repo}
  alias PubQuizzer.Quiz.Engine

  setup %{conn: conn} do
    {:ok, topic} = Quiz.create_topic(%{name: "Hybrid round"})

    questions =
      for position <- 0..1 do
        {:ok, q} =
          Quiz.create_question(%{
            topic_id: topic.id,
            position: position,
            prompt: "Question #{position + 1}",
            options: ["One", "Two", "Three", "Four"],
            correct_index: 1,
            status: "published"
          })

        q
      end

    {:ok, event} = Quiz.create_event(%{team_count: 2})
    {:ok, paper} = Quiz.claim_next_team_slot(event)
    {:ok, digital} = Quiz.claim_next_team_slot(event)
    pid = start_supervised!({Engine, event.id})
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    conn = log_in_user(conn)
    {:ok, host, _} = live(conn, ~p"/quiz/#{event.code}/host")
    host |> element("button[phx-value-topic_id='#{topic.id}']") |> render_click()

    {:ok,
     conn: conn, host: host, event: event, paper: paper, digital: digital, questions: questions}
  end

  test "a moderator can collect a whole sheet before revealing the round", ctx do
    %{host: host, event: event, paper: paper, digital: digital, questions: [first, second]} = ctx
    host |> element("#host-paper-team-#{paper.id}") |> render_click()
    assert has_element?(host, "#host-paper-round", paper.name)
    assert has_element?(host, "#host-paper-round", "Rundenende")
    refute has_element?(host, "#host-enter-paper-#{paper.id}")
    {:ok, _} = Engine.submit_answer(event.id, digital.id, 0)
    host |> element("[data-test='advance-button']") |> render_click()
    refute has_element?(host, "#next-question-modal")
    assert has_element?(host, "#host-enter-paper-#{paper.id}")
    {:ok, _} = Engine.submit_answer(event.id, digital.id, 0)
    host |> element("[data-test='advance-button']") |> render_click()
    assert has_element?(host, "#paper-answers-dialog")
    {:ok, state} = Engine.get_state(event.id)
    assert state.status == :question

    host |> element("#paper-choice-#{first.id}-1") |> render_click()
    host |> element("#paper-choice-#{second.id}-1") |> render_click()
    host |> form("#paper-answers-form") |> render_submit()
    refute has_element?(host, "#paper-answers-dialog")
    assert has_element?(host, "#host-paper-status-#{paper.id}", "Erfasst")
    refute has_element?(host, "#flash-info")
    host |> element("[data-test='advance-button']") |> render_click()
    assert has_element?(host, "#host-round-winner", paper.name)
    {:ok, state} = Engine.get_state(event.id)
    assert state.standings[paper.id] == 2
    {:ok, results, _} = live(ctx.conn, ~p"/admin/events/#{event.id}/results")

    assert has_element?(
             results,
             "#result-paper-#{state.current_round_id}-#{first.id}-#{paper.id}",
             "Papier"
           )
  end

  test "digital replacement requires a second explicit save", ctx do
    %{host: host, event: event, paper: paper, questions: [first, second]} = ctx
    {:ok, _} = Engine.submit_answer(event.id, paper.id, 0)
    host |> element("#host-paper-team-#{paper.id}") |> render_click()
    {:ok, _} = Engine.next_question(event.id)
    host |> element("#host-enter-paper-#{paper.id}") |> render_click()
    assert has_element?(host, "#paper-existing-#{first.id}", "A")
    assert has_element?(host, "#paper-existing-#{first.id}", "Digital")
    host |> element("#paper-choice-#{first.id}-1") |> render_click()
    host |> element("#paper-blank-#{second.id}") |> render_click()
    host |> form("#paper-answers-form") |> render_submit()
    assert has_element?(host, "#paper-overwrite-warning", "Frage 1")
    {:ok, state} = Engine.get_state(event.id)
    assert state.answers[0][paper.id] == 0
    host |> element("#paper-confirm-overwrite") |> render_click()
    refute has_element?(host, "#flash-info")
    {:ok, state} = Engine.get_state(event.id)
    assert state.answers[0][paper.id] == 1
    assert state.answers[1] == nil
    host |> element("#host-enter-paper-#{paper.id}") |> render_click()
    assert has_element?(host, "#paper-existing-#{first.id}", "Papier")
    assert has_element?(host, "#paper-blank-#{second.id}[aria-pressed='true']")
    refute has_element?(host, "#paper-save[disabled]")
  end

  test "a reconnecting paper team sees paper mode and cannot submit by phone", ctx do
    %{host: host, event: event, paper: paper} = ctx
    host |> element("#host-paper-team-#{paper.id}") |> render_click()
    team_conn = Plug.Test.init_test_session(build_conn(), team_id: paper.id)
    {:ok, team_view, _} = live(team_conn, ~p"/quiz/#{event.code}/lobby/#{paper.link_code}")
    assert has_element?(team_view, "#team-paper-mode")
    refute has_element?(team_view, "[phx-click='select_answer']")
    refute has_element?(team_view, "[phx-click='save_paper_answers']")

    render_click(team_view, "select_answer", %{
      "index" => "1",
      "question_id" => to_string(hd(ctx.questions).id)
    })

    {:ok, state} = Engine.get_state(event.id)
    assert state.answers == %{}
    host |> element("#host-paper-team-#{paper.id}") |> render_click()
    refute has_element?(team_view, "#team-paper-mode")
    assert has_element?(team_view, "#team-answer-0")
  end

  test "drafts do not save on cancel and close when the round changes", ctx do
    %{host: host, event: event, paper: paper} = ctx
    host |> element("#host-paper-team-#{paper.id}") |> render_click()
    {:ok, _} = Engine.next_question(event.id)
    host |> element("#host-enter-paper-#{paper.id}") |> render_click()
    assert has_element?(host, "#paper-save[disabled]")
    host |> element("#paper-answers-close") |> render_click()
    assert Quiz.list_answers_for_round(elem(Engine.get_state(event.id), 1).current_round_id) == []
    host |> element("#host-enter-paper-#{paper.id}") |> render_click()

    {:ok, _} =
      Engine.set_paper_mode(
        event.id,
        elem(Engine.get_state(event.id), 1).current_round_id,
        paper.id,
        false
      )

    refute has_element?(host, "#paper-answers-dialog")
    render_click(host, "confirm_paper_overwrite")
    assert Quiz.list_answers_for_round(elem(Engine.get_state(event.id), 1).current_round_id) == []
  end

  test "paper teams are excluded from missing digital-answer confirmation", ctx do
    %{host: host, paper: paper, digital: digital} = ctx
    host |> element("#host-paper-team-#{paper.id}") |> render_click()
    host |> element("#host-answer-count") |> render_click()
    assert has_element?(host, "#host-pending-teams", digital.name)
    refute has_element?(host, "#host-pending-teams", paper.name)
    host |> element("[data-test='advance-button']") |> render_click()
    assert has_element?(host, "#next-question-modal", digital.name)
    refute has_element?(host, "#next-question-modal", paper.name)
  end

  test "paper mode added by another moderator cannot be bypassed through an old confirmation",
       ctx do
    %{host: host, event: event, paper: paper} = ctx
    {:ok, state} = Engine.next_question(event.id)
    host |> element("[data-test='advance-button']") |> render_click()
    assert has_element?(host, "#next-question-modal")
    {:ok, _} = Engine.set_paper_mode(event.id, state.current_round_id, paper.id, true)
    host |> element("#next-question-modal-confirm") |> render_click()
    assert has_element?(host, "#paper-answers-dialog")
    {:ok, state} = Engine.get_state(event.id)
    assert state.status == :question
  end
end
