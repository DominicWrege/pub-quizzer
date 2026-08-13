defmodule PubQuizzerWeb.Admin.ReportLiveTest do
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
    {:ok, topic} = Quiz.create_topic(%{name: "ReportLive Test Topic"})

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

    {:ok, event} = Quiz.create_event(%{team_count: 3})
    {:ok, t1} = Quiz.claim_next_team_slot(event)
    {:ok, t2} = Quiz.claim_next_team_slot(event)
    {:ok, t3} = Quiz.claim_next_team_slot(event)

    {:ok, event} =
      Quiz.update_event(event, %{
        status: "finished",
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
    insert_answer(round, q1, t3, 0, ~U[2026-08-01 20:11:45Z])
    insert_answer(round, q2, t1, 1, ~U[2026-08-01 20:12:00Z])
    insert_answer(round, q2, t2, 1, ~U[2026-08-01 20:11:50Z])

    %{event: event, round: round, questions: questions}
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

  describe "report" do
    test "shows question cards with option distribution and no-answer segment", %{conn: conn} do
      %{event: event, round: round, questions: [q1, q2]} = setup_finished_event()

      {:ok, view, _html} =
        conn
        |> log_in_user()
        |> live(~p"/admin/events/#{event.id}/report")

      card1 = "#question-card-#{round.id}-#{q1.id}"
      card2 = "#question-card-#{round.id}-#{q2.id}"
      assert has_element?(view, card1)
      assert has_element?(view, "#{card1} [data-correct='true']", "B")
      assert has_element?(view, "#{card1} [data-correct='false']", "A")
      assert has_element?(view, "#{card1}", "33 % richtig")
      assert has_element?(view, "#{card2} [data-no-answer]", "1")
      assert has_element?(view, "#{card2}", "67 % richtig")
    end

    test "shows hardest and easiest question plus most popular trap", %{conn: conn} do
      %{event: event, questions: [q1, q2]} = setup_finished_event()

      {:ok, view, _html} =
        conn
        |> log_in_user()
        |> live(~p"/admin/events/#{event.id}/report")

      assert has_element?(view, "#report-hardest", q1.prompt)
      assert has_element?(view, "#report-easiest", q2.prompt)
      assert has_element?(view, "#report-trap", q1.prompt)
      assert has_element?(view, "#report-trap", "A")
    end

    test "shows total and per-round answering duration", %{conn: conn} do
      %{event: event} = setup_finished_event()

      {:ok, view, _html} =
        conn
        |> log_in_user()
        |> live(~p"/admin/events/#{event.id}/report")

      assert has_element?(view, "#report-timing", "47 Min.")
      assert has_element?(view, "#report-timing", "2 Min.")
    end

    test "never shows team names", %{conn: conn} do
      %{event: event} = setup_finished_event()

      {:ok, _view, html} =
        conn
        |> log_in_user()
        |> live(~p"/admin/events/#{event.id}/report")

      refute html =~ "Team 1"
      refute html =~ "Team 2"
      refute html =~ "Team 3"
    end

    test "redirects to results for unfinished events", %{conn: conn} do
      {:ok, event} = Quiz.create_event(%{team_count: 2})
      results_path = ~p"/admin/events/#{event.id}/results"

      assert {:error, {:redirect, %{to: ^results_path}}} =
               conn
               |> log_in_user()
               |> live(~p"/admin/events/#{event.id}/report")
    end

    test "event list shows Bericht link only for finished events", %{conn: conn} do
      %{event: finished} = setup_finished_event()
      {:ok, lobby_event} = Quiz.create_event(%{team_count: 2})

      {:ok, view, _html} =
        conn
        |> log_in_user()
        |> live(~p"/admin/events")

      assert has_element?(view, "a[href='/admin/events/#{finished.id}/report']", "Bericht")
      refute has_element?(view, "a[href='/admin/events/#{lobby_event.id}/report']")
    end
  end
end
