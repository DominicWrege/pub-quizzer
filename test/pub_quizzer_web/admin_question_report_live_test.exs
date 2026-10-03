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

  defp row_ids(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#question-report-rows > tr")
    |> LazyHTML.attribute("id")
  end

  describe "cross-quiz question report" do
    test "identifies rows by topic and question number, with text available on demand", %{
      conn: conn
    } do
      %{q1: q1, q2: q2} = seed()
      {:ok, view, _html} = conn |> log_in_user() |> live(~p"/admin/question-report")

      assert has_element?(
               view,
               "#question-report-#{q1.id} [data-test='question-label']",
               "Frage 1"
             )

      assert has_element?(
               view,
               "#question-report-#{q2.id} [data-test='question-label']",
               "Frage 2"
             )

      assert has_element?(view, "#question-report-#{q1.id}", "Report Topic")
      refute has_element?(view, "#question-report-#{q1.id} td:first-child", "Richtig:")
      refute has_element?(view, "#question-report-rows", "Hard question")
      refute has_element?(view, "#question-report-details")

      view |> element("#view-question-#{q1.id}") |> render_click()
      assert has_element?(view, "#question-report-details", "Hard question")
      assert has_element?(view, "#question-report-details [data-option='1']", "b")
      refute has_element?(view, "#question-report-details", "Richtig")

      assert has_element?(
               view,
               "#question-report-details [data-option='1'] [data-test='answer-text']",
               "b"
             )

      refute has_element?(view, "#question-report-details [data-test='correct-label']")

      close_buttons =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#question-report-details button[phx-click='close_question']")
        |> LazyHTML.attribute("id")

      assert close_buttons == ["question-report-details-close"]

      view |> element("#question-report-details-close") |> render_click()
      refute has_element?(view, "#question-report-details")
    end

    test "shows each option's answer count, including zero, separately from its bar", %{
      conn: conn
    } do
      %{q1: q1} = seed()
      {:ok, view, _html} = conn |> log_in_user() |> live(~p"/admin/question-report")
      row = "#question-report-#{q1.id}"

      assert has_element?(view, "#{row} [data-answer-index='0'] [data-test='answer-count']", "2")
      assert has_element?(view, "#{row} [data-answer-index='1'] [data-test='answer-count']", "3")
      assert has_element?(view, "#{row} [data-answer-index='2'] [data-test='answer-count']", "0")
      assert has_element?(view, "#{row} [data-answer-index='3'] [data-test='answer-count']", "0")
      assert has_element?(view, "#{row} [data-answer-index='1'][data-correct='true']")
    end

    test "switching quizzes closes the question details", %{conn: conn} do
      %{q1: q1, events: [_, event_b]} = seed()
      {:ok, view, _html} = conn |> log_in_user() |> live(~p"/admin/question-report")
      view |> element("#view-question-#{q1.id}") |> render_click()
      assert has_element?(view, "#question-report-details")
      view |> form("#question-report-quiz-form", %{event_id: event_b.id}) |> render_change()
      refute has_element?(view, "#question-report-details")
    end

    test "is available as a separate desktop and mobile navigation tab", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_user() |> live(~p"/admin/events")

      assert has_element?(view, "#question-report-nav[href='/admin/question-report']")
      assert has_element?(view, "#question-report-mobile-nav[href='/admin/question-report']")
      assert has_element?(view, "a[href='/admin/topics'] + #question-report-nav")
      assert has_element?(view, "a[href='/admin/topics'] + #question-report-mobile-nav")
      refute has_element?(view, "#question-report-btn")

      {:ok, report, _html} = conn |> log_in_user() |> live(~p"/admin/question-report")
      assert has_element?(report, "#question-report-nav[aria-current='page']")
      assert has_element?(report, "#question-report-mobile-nav[aria-current='page']")
      refute has_element?(report, "a[aria-label='Zurück']")
      refute has_element?(report, "main header p")
    end

    test "switches quiz statistics immediately and can return to all quizzes", %{conn: conn} do
      %{q1: q1, events: [event_a, event_b]} = seed()
      {:ok, view, _html} = conn |> log_in_user() |> live(~p"/admin/question-report")

      assert has_element?(view, "#question-report-quiz option[value='#{event_a.id}']", "Quiz A")
      assert has_element?(view, "#question-report-quiz option[value='#{event_b.id}']", "Quiz B")
      refute has_element?(view, "#question-report-quiz option", "Quiz C")

      view |> form("#question-report-quiz-form", %{event_id: event_a.id}) |> render_change()
      assert has_element?(view, "#question-report-#{q1.id}", "67 %")
      assert has_element?(view, "#question-report-#{q1.id}", "1×")

      view |> form("#question-report-quiz-form", %{event_id: event_b.id}) |> render_change()
      assert has_element?(view, "#question-report-#{q1.id}", "50 %")

      view |> form("#question-report-quiz-form", %{event_id: ""}) |> render_change()
      assert has_element?(view, "#question-report-#{q1.id}", "60 %")
      assert has_element?(view, "#question-report-#{q1.id}", "2×")
      assert has_element?(view, "#question-report-distribution-help", "Anzahl der Teams")
    end

    test "selecting a topic defaults to question numbers and resets when changing topics", %{
      conn: conn
    } do
      %{q1: q1, q2: q2, qc: qc, topic: topic, topic_c: topic_c} = seed()
      q3 = create_question(topic, "Third question")
      q4 = create_question(topic, "Fourth question")
      q5 = create_question(topic, "Fifth question")
      {_event, [team | _], round} = finished_event_with_round(topic, "Extra questions")
      insert_answer(round, q3, team, 0)
      insert_answer(round, q4, team, 1)
      insert_answer(round, q5, team, 0)
      {_event, [other_team | _], other_round} = finished_event_with_round(topic_c, "Other topic")
      insert_answer(other_round, qc, other_team, 1)

      {:ok, view, _html} = conn |> log_in_user() |> live(~p"/admin/question-report")
      view |> form("#question-report-filter-form", %{topic_id: topic.id}) |> render_change()
      expected = Enum.map([q1, q2, q3, q4, q5], &"question-report-#{&1.id}")
      assert row_ids(view) == expected
      assert has_element?(view, "#sort-question[aria-sort='asc']")

      view |> element("#sort-question") |> render_click()
      assert row_ids(view) == Enum.reverse(expected)

      view |> form("#question-report-filter-form", %{topic_id: topic_c.id}) |> render_change()
      assert row_ids(view) == ["question-report-#{qc.id}"]
      assert has_element?(view, "#sort-question[aria-sort='asc']")

      view |> form("#question-report-filter-form", %{topic_id: topic.id}) |> render_change()
      assert row_ids(view) == expected
    end

    test "question-number sorting works on mobile and survives quiz switching", %{conn: conn} do
      %{q1: q1, q2: q2, topic: topic, events: [event_a, _]} = seed()
      {:ok, view, _html} = conn |> log_in_user() |> live(~p"/admin/question-report")
      view |> form("#question-report-filter-form", %{topic_id: topic.id}) |> render_change()
      assert has_element?(view, "#question-report-mobile-sort option[value='question'][selected]")

      view |> element("#question-report-sort-direction") |> render_click()
      assert row_ids(view) == ["question-report-#{q2.id}", "question-report-#{q1.id}"]
      view |> form("#question-report-quiz-form", %{event_id: event_a.id}) |> render_change()
      assert row_ids(view) == ["question-report-#{q2.id}", "question-report-#{q1.id}"]
      assert has_element?(view, "#sort-question[aria-sort='desc']")

      view |> form("#question-report-filter-form", %{topic_id: ""}) |> render_change()
      refute has_element?(view, "#sort-question")
      assert has_element?(view, "#sort-right[aria-sort='asc']")
      assert has_element?(view, "#question-report-mobile-sort option[value='right'][selected]")
    end

    test "quiz switching preserves topic filtering and sorting", %{conn: conn} do
      %{q1: q1, q2: q2, topic: topic, events: [event_a, _]} = seed()
      {:ok, other_topic} = Quiz.create_topic(%{name: "Another finished topic"})
      other_question = create_question(other_topic, "Other quiz question")
      {_event, [team | _], round} = finished_event_with_round(other_topic, "Other Quiz")
      insert_answer(round, other_question, team, 1)

      {:ok, view, _html} = conn |> log_in_user() |> live(~p"/admin/question-report")
      view |> form("#question-report-filter-form", %{topic_id: topic.id}) |> render_change()
      view |> element("#sort-right") |> render_click()
      view |> element("#sort-right") |> render_click()
      view |> form("#question-report-quiz-form", %{event_id: event_a.id}) |> render_change()

      assert has_element?(view, "#question-report-#{q1.id}", "67 %")
      assert has_element?(view, "#question-report-#{q2.id}", "100 %")
      refute has_element?(view, "#question-report-#{other_question.id}")
      assert has_element?(view, "#sort-right[aria-sort='desc']")
      assert has_element?(view, "#question-report-topic option[value='#{topic.id}'][selected]")

      view |> form("#question-report-quiz-form", %{event_id: ""}) |> render_change()
      refute has_element?(view, "#question-report-#{other_question.id}")
    end

    test "a completed quiz without questions shows an empty report", %{conn: conn} do
      seed()
      {:ok, empty} = Quiz.create_event(%{team_count: 1})
      {:ok, empty} = Quiz.update_event(empty, %{status: "finished"})
      {:ok, view, _html} = conn |> log_in_user() |> live(~p"/admin/question-report")

      assert has_element?(view, "#question-report-quiz option[value='#{empty.id}']", empty.code)
      view |> form("#question-report-quiz-form", %{event_id: empty.id}) |> render_change()
      assert has_element?(view, "#question-report-empty")
    end

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

      {:ok, view, _html} =
        conn
        |> log_in_user()
        |> live(~p"/admin/question-report")

      assert row_ids(view) == ["question-report-#{q1.id}", "question-report-#{q2.id}"]
    end

    test "clicking column headers re-sorts the table", %{conn: conn} do
      %{q1: q1, q2: q2} = seed()

      {:ok, view, _html} =
        conn
        |> log_in_user()
        |> live(~p"/admin/question-report")

      # default: hardest first (q1 60 % before q2 100 %)
      assert row_ids(view) == ["question-report-#{q1.id}", "question-report-#{q2.id}"]

      # toggle Richtig to desc -> q2 first
      view |> element("#sort-right") |> render_click()
      assert row_ids(view) == ["question-report-#{q2.id}", "question-report-#{q1.id}"]

      # Antworten desc -> q1 (5 answers) before q2 (2)
      view |> element("#sort-answers") |> render_click()
      assert row_ids(view) == ["question-report-#{q1.id}", "question-report-#{q2.id}"]

      refute has_element?(view, "#sort-name")
    end

    test "mobile sort control reorders the questions", %{conn: conn} do
      %{q1: q1, q2: q2} = seed()

      {:ok, view, _html} = conn |> log_in_user() |> live(~p"/admin/question-report")

      assert has_element?(view, "#question-report-mobile-sort select")
      refute has_element?(view, "#question-report-mobile-sort option[value='name']")
      refute has_element?(view, "header a.btn-square[aria-label='Zurück']")

      view
      |> element("#question-report-mobile-sort")
      |> render_change(%{"key" => "right"})

      assert has_element?(view, "#question-report-#{q1.id}")
      assert has_element?(view, "#question-report-#{q2.id}")
      assert row_ids(view) == ["question-report-#{q2.id}", "question-report-#{q1.id}"]
    end

    test "filters by topic", %{conn: conn} do
      %{q1: q1, qc: qc, topic_c: topic_c} = seed()

      {:ok, view, _html} =
        conn
        |> log_in_user()
        |> live(~p"/admin/question-report")

      view
      |> element("#question-report-filter-form")
      |> render_change(%{"topic_id" => topic_c.id})

      refute has_element?(view, "#question-report-#{q1.id}")
      # qc has no finished-event rounds, so the filtered list is empty
      refute has_element?(view, "#question-report-#{qc.id}")
      assert has_element?(view, "#question-report-empty")
    end

    test "marks the correct option even when every team picked a wrong one", %{conn: conn} do
      {:ok, topic} = Quiz.create_topic(%{name: "Tricky Topic"})
      question = create_question(topic, "Everyone missed this", 2)
      {_event, [team | _], round} = finished_event_with_round(topic, "Tricky Quiz")
      insert_answer(round, question, team, 0)

      {:ok, view, _html} = conn |> log_in_user() |> live(~p"/admin/question-report")

      assert has_element?(
               view,
               "#question-report-#{question.id} [data-answer-index='2'][data-correct='true']"
             )
    end
  end
end
