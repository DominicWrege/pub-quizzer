defmodule PubQuizzerWeb.Admin.QuestionReportLiveTest do
  use PubQuizzerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.{Answer, Round}
  alias PubQuizzer.Repo

  defp create_question(topic, prompt, correct \\ 1) do
    {:ok, q} =
      Quiz.create_question(%{
        prompt: prompt,
        options: ["a", "b", "c", "d"],
        correct_index: correct,
        topic_id: topic.id,
        status: "published"
      })

    q
  end

  defp finished_event_with_round(topic, name) do
    {:ok, event} = Quiz.create_event(%{team_count: 3, name: name})
    {:ok, t1} = Quiz.claim_next_team_slot(event)
    {:ok, t2} = Quiz.claim_next_team_slot(event)
    {:ok, t3} = Quiz.claim_next_team_slot(event)

    {:ok, event} = Quiz.update_event(event, %{status: "finished"})

    round =
      %Round{}
      |> Round.changeset(%{round_number: 1, quiz_event_id: event.id, topic_id: topic.id})
      |> Repo.insert!()

    {event, [t1, t2, t3], round}
  end

  defp insert_answer(round, question, team, selected_index) do
    %Answer{}
    |> Answer.changeset(%{
      round_id: round.id,
      question_id: question.id,
      team_id: team.id,
      selected_index: selected_index
    })
    |> Repo.insert!()
  end

  defp seed do
    {:ok, topic} = Quiz.create_topic(%{name: "Report Topic"})
    q1 = create_question(topic, "Hard question")
    q2 = create_question(topic, "Easy question")

    {event_a, [a1, a2, a3], round_a} = finished_event_with_round(topic, "Quiz A")
    {event_b, [b1, b2, _b3], round_b} = finished_event_with_round(topic, "Quiz B")

    insert_answer(round_a, q1, a1, 1)
    insert_answer(round_a, q1, a2, 1)
    insert_answer(round_a, q1, a3, 0)
    insert_answer(round_a, q2, a1, 1)

    insert_answer(round_b, q1, b1, 1)
    insert_answer(round_b, q1, b2, 0)
    insert_answer(round_b, q2, b1, 1)

    # Unfinished event: its answers must not count
    {:ok, topic_c} = Quiz.create_topic(%{name: "Other Topic"})
    qc = create_question(topic_c, "Unfinished quiz question")
    {:ok, event_c} = Quiz.create_event(%{team_count: 2, name: "Quiz C"})
    {:ok, c1} = Quiz.claim_next_team_slot(event_c)
    {:ok, _c2} = Quiz.claim_next_team_slot(event_c)

    round_c =
      %Round{}
      |> Round.changeset(%{round_number: 1, quiz_event_id: event_c.id, topic_id: topic_c.id})
      |> Repo.insert!()

    insert_answer(round_c, qc, c1, 0)

    %{q1: q1, q2: q2, qc: qc, topic: topic, topic_c: topic_c, events: [event_a, event_b]}
  end

  describe "cross-quiz question report" do
    test "aggregates answers across finished events", %{conn: conn} do
      %{q1: q1, q2: q2} = seed()

      {:ok, view, _html} =
        conn
        |> log_in_user()
        |> live(~p"/admin/question-report")

      # q1: 5 answers, 3 correct = 60 %; asked in 2 finished rounds
      assert has_element?(view, "#question-report-#{q1.id}", "60 %")
      assert has_element?(view, "#question-report-#{q1.id}", "2×")

      # q2: 2 answers, 2 correct = 100 %
      assert has_element?(view, "#question-report-#{q2.id}", "100 %")
    end

    test "ignores answers from unfinished events", %{conn: conn} do
      %{q1: q1, qc: qc} = seed()

      {:ok, view, _html} =
        conn
        |> log_in_user()
        |> live(~p"/admin/question-report")

      # qc only asked in an unfinished event -> not listed
      refute has_element?(view, "#question-report-#{qc.id}")
      # q1 pct unaffected by the unfinished event's wrong answer
      assert has_element?(view, "#question-report-#{q1.id}", "60 %")
    end

    test "sorts hardest question first by default", %{conn: conn} do
      %{q1: q1, q2: q2} = seed()

      {:ok, _view, html} =
        conn
        |> log_in_user()
        |> live(~p"/admin/question-report")

      assert html =~ ~r/Hard question.*Easy question/s
    end

    test "filters by topic", %{conn: conn} do
      %{q1: q1, qc: qc, topic_c: topic_c} = seed()

      {:ok, view, _html} =
        conn
        |> log_in_user()
        |> live(~p"/admin/question-report")

      view
      |> element("#question-report-filters form")
      |> render_change(%{"topic_id" => topic_c.id})

      refute has_element?(view, "#question-report-#{q1.id}")
      # qc has no finished-event rounds, so the filtered list is empty
      refute has_element?(view, "#question-report-#{qc.id}")
      assert has_element?(view, "#question-report-empty")
    end
  end
end
