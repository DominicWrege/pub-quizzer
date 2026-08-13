defmodule PubQuizzerWeb.Admin.ResultLiveTest do
  use PubQuizzerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.{Answer, Round}
  alias PubQuizzer.Repo

  @questions [
    {"What is 2+2?", ["3", "4", "5", "6"], 1},
    {"Capital of France?", ["London", "Paris", "Rome", "Berlin"], 1}
  ]

  defp setup_finished_event do
    {:ok, topic} = Quiz.create_topic(%{name: "ResultLive Test Topic"})

    questions =
      for {{prompt, options, correct}, idx} <- Enum.with_index(@questions) do
        {:ok, q} =
          Quiz.create_question(%{
            prompt: prompt,
            options: options,
            correct_index: correct,
            topic_id: topic.id,
            position: idx,
            status: "published"
          })

        q
      end

    {:ok, event} = Quiz.create_event(%{team_count: 2})
    {:ok, t1} = Quiz.claim_next_team_slot(event)
    {:ok, t2} = Quiz.claim_next_team_slot(event)

    {:ok, event} =
      Quiz.update_event(event, %{
        started_at: ~U[2026-08-01 20:00:00Z],
        finished_at: ~U[2026-08-01 20:47:00Z]
      })

    round =
      %Round{}
      |> Round.changeset(%{round_number: 1, quiz_event_id: event.id, topic_id: topic.id})
      |> Ecto.Changeset.force_change(:inserted_at, ~U[2026-08-01 20:10:00Z])
      |> Repo.insert!()

    [q1, q2] = questions

    insert_answer(round, q1, t1, 1, ~U[2026-08-01 20:11:00Z])
    insert_answer(round, q1, t2, 0, ~U[2026-08-01 20:11:30Z])
    insert_answer(round, q2, t1, 1, ~U[2026-08-01 20:12:00Z])

    %{event: event, round: round, questions: questions, teams: [t1, t2]}
  end

  defp insert_answer(round, question, team, selected_index, inserted_at) do
    %Answer{}
    |> Answer.changeset(%{
      round_id: round.id,
      question_id: question.id,
      team_id: team.id,
      selected_index: selected_index
    })
    |> Ecto.Changeset.force_change(:inserted_at, inserted_at)
    |> Repo.insert!()
  end

  describe "stats" do
    test "shows total duration and pure answering time", %{conn: conn} do
      %{event: event} = setup_finished_event()

      {:ok, view, _html} =
        conn
        |> log_in_user()
        |> live(~p"/admin/events/#{event.id}/results")

      assert has_element?(view, "#result-timing")
      assert has_element?(view, "#result-timing", "47 Min.")
      assert has_element?(view, "#result-timing", "2 Min.")
    end

    test "shows per-question option distribution with highlighted correct option", %{conn: conn} do
      %{event: event, round: round, questions: [q1 | _]} = setup_finished_event()

      {:ok, view, _html} =
        conn
        |> log_in_user()
        |> live(~p"/admin/events/#{event.id}/results")

      stats_id = "#question-stats-#{round.id}-#{q1.id}"
      assert has_element?(view, stats_id)
      assert has_element?(view, "#{stats_id} [data-correct='true']", "B")
      assert has_element?(view, "#{stats_id} [data-correct='false']", "A")
    end

    test "shows a segment for teams that did not answer", %{conn: conn} do
      %{event: event, round: round, questions: [_q1, q2]} = setup_finished_event()

      {:ok, view, _html} =
        conn
        |> log_in_user()
        |> live(~p"/admin/events/#{event.id}/results")

      assert has_element?(view, "#question-stats-#{round.id}-#{q2.id} [data-no-answer]", "1")
    end

    test "shows accuracy per team", %{conn: conn} do
      %{event: event, teams: [t1, t2]} = setup_finished_event()

      {:ok, view, _html} =
        conn
        |> log_in_user()
        |> live(~p"/admin/events/#{event.id}/results")

      assert has_element?(view, "#team-quote-#{t1.id}", "100 %")
      assert has_element?(view, "#team-quote-#{t2.id}", "0 %")
    end

    test "hides stats for events without rounds", %{conn: conn} do
      {:ok, event} = Quiz.create_event(%{team_count: 2})

      {:ok, view, _html} =
        conn
        |> log_in_user()
        |> live(~p"/admin/events/#{event.id}/results")

      refute has_element?(view, "#result-stats")
    end
  end
end
