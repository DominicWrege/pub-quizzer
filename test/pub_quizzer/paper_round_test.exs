defmodule PubQuizzer.Quiz.PaperRoundTest do
  use PubQuizzer.DataCase, async: false

  alias PubQuizzer.{Accounts, Quiz, Repo}
  alias PubQuizzer.Quiz.{Answer, Engine, EngineState, Round}

  setup do
    {:ok, user} =
      Accounts.create_user(%{
        email: "paper@example.com",
        name: "Paper Moderator",
        role: "moderator",
        active: true
      })

    {:ok, topic} = Quiz.create_topic(%{name: "Paper round"})

    questions =
      for position <- 0..1 do
        {:ok, question} =
          Quiz.create_question(%{
            topic_id: topic.id,
            position: position,
            prompt: "Question #{position + 1}",
            options: ["One", "Two", "Three", "Four"],
            correct_index: 1,
            status: "published"
          })

        question
      end

    {:ok, event} = Quiz.create_event(%{team_count: 2})
    {:ok, paper} = Quiz.claim_next_team_slot(event)
    {:ok, digital} = Quiz.claim_next_team_slot(event)
    pid = start_supervised!({Engine, event.id})
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    {:ok, _} = Engine.start_quiz(event.id)
    {:ok, state} = Engine.choose_topic(event.id, topic.id)

    {:ok,
     event: event,
     paper: paper,
     digital: digital,
     round_id: state.current_round_id,
     questions: questions,
     user: user}
  end

  test "paper answers are collected as a whole round and score like digital answers", ctx do
    %{
      event: event,
      paper: paper,
      digital: digital,
      round_id: round_id,
      questions: [first, second],
      user: user
    } = ctx

    assert {:ok, state} = Engine.set_paper_mode(event.id, round_id, paper.id, true)

    assert EngineState.pending_digital_teams(state) == [
             state.teams |> Enum.find(&(&1.id == digital.id))
           ]

    assert {:error, :paper_mode} = Engine.submit_answer(event.id, paper.id, 0)
    assert {:ok, _} = Engine.submit_answer(event.id, digital.id, 0)
    assert {:ok, _} = Engine.next_question(event.id)
    assert {:error, :paper_answers_pending} = Engine.reveal_round(event.id)

    picks = %{first.id => 1, second.id => 1}

    assert {:ok, state} =
             Engine.submit_paper_answers(event.id, round_id, paper.id, picks, user.id)

    assert state.answers == %{0 => %{paper.id => 1, digital.id => 0}, 1 => %{paper.id => 1}}
    assert EngineState.pending_paper_teams(state) == []
    assert {:ok, state} = Engine.reveal_round(event.id)
    assert state.standings == %{paper.id => 2, digital.id => 0}
    assert state.current_winner_team_id == paper.id
    assert [{_, _, 2}, {_, _, 0}] = Quiz.get_event_results(event.id).standings

    saved = Quiz.list_answers_for_round(round_id) |> Enum.filter(&(&1.team_id == paper.id))
    assert length(saved) == 2
    assert Enum.all?(saved, &(&1.source == "paper" and &1.recorded_by_user_id == user.id))
    assert Repo.get!(Round, round_id).winner_team_id == paper.id
  end

  test "paper entry timestamps are excluded from digital answering time", ctx do
    %{
      event: event,
      paper: paper,
      digital: digital,
      round_id: round_id,
      questions: [first, second],
      user: user
    } = ctx

    {:ok, _} = Engine.submit_answer(event.id, digital.id, 0)
    {:ok, _} = Engine.set_paper_mode(event.id, round_id, paper.id, true)
    {:ok, _} = Engine.next_question(event.id)

    {:ok, _} =
      Engine.submit_paper_answers(
        event.id,
        round_id,
        paper.id,
        %{first.id => 1, second.id => nil},
        user.id
      )

    start = ~U[2026-10-04 18:00:00Z]
    Repo.get!(Round, round_id) |> Ecto.Changeset.change(inserted_at: start) |> Repo.update!()

    for answer <- Quiz.list_answers_for_round(round_id) do
      seconds = if answer.source == "digital", do: 10, else: 600
      answer |> Ecto.Changeset.change(inserted_at: DateTime.add(start, seconds)) |> Repo.update!()
    end

    results = Quiz.get_event_results(event.id)
    assert results.timing.answering_seconds == 10
    assert results.answer_sources[{round_id, first.id, paper.id}] == "paper"
    assert results.answer_sources[{round_id, first.id, digital.id}] == "digital"
    {:ok, _} = Engine.reveal_round(event.id)
    {:ok, _} = Engine.next_round(event.id)
    report = Enum.find(Quiz.get_question_report(event.id), &(&1.question.id == first.id))
    assert report.answers == 2
    assert report.pct == 50.0
  end

  test "existing digital answers need explicit replacement and blanks preserve them", ctx do
    %{event: event, paper: paper, round_id: round_id, questions: [first, second], user: user} =
      ctx

    {:ok, _} = Engine.submit_answer(event.id, paper.id, 0)
    {:ok, _} = Engine.set_paper_mode(event.id, round_id, paper.id, true)
    {:ok, _} = Engine.next_question(event.id)

    assert {:error, :overwrite_required} =
             Engine.submit_paper_answers(
               event.id,
               round_id,
               paper.id,
               %{first.id => 1, second.id => 1},
               user.id
             )

    assert length(Quiz.list_answers_for_round(round_id)) == 1

    assert {:ok, state} =
             Engine.submit_paper_answers(
               event.id,
               round_id,
               paper.id,
               %{first.id => nil, second.id => 1},
               user.id
             )

    assert state.answers[0][paper.id] == 0

    assert Enum.find(Quiz.list_answers_for_round(round_id), &(&1.question_id == first.id)).source ==
             "digital"

    assert {:ok, state} =
             Engine.submit_paper_answers(
               event.id,
               round_id,
               paper.id,
               %{first.id => 1, second.id => 1},
               user.id,
               replace_existing?: true
             )

    assert state.answers[0][paper.id] == 1
  end

  test "entry is only allowed after the last question and rejects incomplete or foreign data",
       ctx do
    %{event: event, paper: paper, round_id: round_id, questions: [first, second], user: user} =
      ctx

    {:ok, _} = Engine.set_paper_mode(event.id, round_id, paper.id, true)
    picks = %{first.id => 1, second.id => 1}

    assert {:error, :round_not_complete} =
             Engine.submit_paper_answers(event.id, round_id, paper.id, picks, user.id)

    {:ok, _} = Engine.next_question(event.id)

    for invalid <- [
          %{first.id => 4, second.id => 1},
          %{first.id => "1", second.id => 1},
          %{first.id => 1},
          %{first.id => 1, second.id => 1, 999_999 => 0}
        ] do
      assert {:error, :invalid_submission} =
               Engine.submit_paper_answers(event.id, round_id, paper.id, invalid, user.id)
    end

    assert {:error, :stale_round} =
             Engine.submit_paper_answers(event.id, round_id + 1, paper.id, picks, user.id)

    assert {:error, :invalid_team} = Engine.set_paper_mode(event.id, round_id, 999_999, true)

    assert {:error, :not_in_paper_mode} =
             Engine.submit_paper_answers(event.id, round_id, ctx.digital.id, picks, user.id)

    assert Quiz.list_answers_for_round(round_id) == []
  end

  test "only active moderators or admins can record paper answers", ctx do
    %{event: event, paper: paper, round_id: round_id, questions: [first, second], user: user} =
      ctx

    {:ok, _} = Engine.set_paper_mode(event.id, round_id, paper.id, true)
    {:ok, _} = Engine.next_question(event.id)
    picks = %{first.id => 1, second.id => nil}

    assert {:error, :unauthorized} =
             Engine.submit_paper_answers(event.id, round_id, paper.id, picks, nil)

    {:ok, _} = Accounts.toggle_active(user)

    assert {:error, :unauthorized} =
             Engine.submit_paper_answers(event.id, round_id, paper.id, picks, user.id)
  end

  test "concurrent editors cannot silently overwrite each other's paper entries", ctx do
    %{event: event, paper: paper, round_id: round_id, questions: [first, second], user: user} =
      ctx

    {:ok, _} = Engine.set_paper_mode(event.id, round_id, paper.id, true)
    {:ok, _} = Engine.next_question(event.id)

    {:ok, _} =
      Engine.submit_paper_answers(
        event.id,
        round_id,
        paper.id,
        %{first.id => 1, second.id => nil},
        user.id
      )

    assert {:error, :answers_changed} =
             Engine.submit_paper_answers(
               event.id,
               round_id,
               paper.id,
               %{first.id => 0, second.id => 0},
               user.id,
               replace_existing?: true,
               expected_answers: %{first.id => nil, second.id => nil}
             )

    assert Repo.one!(Answer).selected_index == 1
  end

  test "paper mode and collected sheets survive engine restarts", ctx do
    %{event: event, paper: paper, round_id: round_id, questions: [first, second], user: user} =
      ctx

    {:ok, _} = Engine.set_paper_mode(event.id, round_id, paper.id, true)
    {:ok, _} = Engine.next_question(event.id)
    restart_engine(event.id)
    {:ok, state} = Engine.get_state(event.id)
    assert state.paper_team_ids == [paper.id]
    assert Enum.map(EngineState.pending_paper_teams(state), & &1.id) == [paper.id]

    {:ok, _} =
      Engine.submit_paper_answers(
        event.id,
        round_id,
        paper.id,
        %{first.id => 1, second.id => nil},
        user.id
      )

    restart_engine(event.id)
    {:ok, state} = Engine.get_state(event.id)
    assert EngineState.pending_paper_teams(state) == []
    assert state.answers == %{0 => %{paper.id => 1}}
    assert {:ok, state} = Engine.reveal_round(event.id)
    assert state.standings[paper.id] == 1
  end

  test "switching back to phones keeps answers and removes the pending-sheet requirement", ctx do
    {:ok, _} = Engine.set_paper_mode(ctx.event.id, ctx.round_id, ctx.paper.id, true)
    assert {:ok, state} = Engine.set_paper_mode(ctx.event.id, ctx.round_id, ctx.paper.id, false)
    assert state.paper_team_ids == []
    assert {:ok, _} = Engine.submit_answer(ctx.event.id, ctx.paper.id, 1)
    assert {:ok, _} = Engine.reveal_round(ctx.event.id)
  end

  test "every paper sheet must be collected, and the following round starts digitally", ctx do
    {:ok, next_topic} = Quiz.create_topic(%{name: "Following round"})

    {:ok, _} =
      Quiz.create_question(%{
        topic_id: next_topic.id,
        position: 0,
        prompt: "Next",
        options: ["One", "Two", "Three", "Four"],
        correct_index: 0,
        status: "published"
      })

    restart_engine(ctx.event.id)

    for team <- [ctx.paper, ctx.digital] do
      {:ok, _} = Engine.set_paper_mode(ctx.event.id, ctx.round_id, team.id, true)
    end

    {:ok, _} = Engine.next_question(ctx.event.id)
    blanks = Map.new(ctx.questions, &{&1.id, nil})

    {:ok, _} =
      Engine.submit_paper_answers(ctx.event.id, ctx.round_id, ctx.paper.id, blanks, ctx.user.id)

    assert {:error, :paper_answers_pending} = Engine.reveal_round(ctx.event.id)

    {:ok, _} =
      Engine.submit_paper_answers(ctx.event.id, ctx.round_id, ctx.digital.id, blanks, ctx.user.id)

    {:ok, _} = Engine.reveal_round(ctx.event.id)
    restart_engine(ctx.event.id)
    assert {:ok, _} = Engine.next_round(ctx.event.id)
    assert {:ok, state} = Engine.choose_topic(ctx.event.id, next_topic.id)
    assert state.paper_team_ids == []
    assert state.paper_submitted_team_ids == []
    assert state.answers == %{}
    assert {:ok, _} = Engine.submit_answer(ctx.event.id, ctx.paper.id, 0)
  end

  test "removal clears pending paper teams and the next round returns to digital mode", ctx do
    {:ok, topic2} = Quiz.create_topic(%{name: "Next topic"})

    {:ok, _} =
      Quiz.create_question(%{
        topic_id: topic2.id,
        position: 0,
        prompt: "Next",
        options: ["One", "Two"],
        correct_index: 0,
        status: "published"
      })

    restart_engine(ctx.event.id)
    {:ok, _} = Engine.set_paper_mode(ctx.event.id, ctx.round_id, ctx.paper.id, true)
    assert {:ok, state} = Engine.remove_team(ctx.event.id, ctx.paper.id)
    assert state.paper_team_ids == []
    assert {:ok, _} = Engine.reveal_round(ctx.event.id)
    assert {:ok, _} = Engine.next_round(ctx.event.id)
    {:ok, state} = Engine.choose_topic(ctx.event.id, topic2.id)
    assert state.paper_team_ids == []
    assert state.paper_submitted_team_ids == []
  end

  defp restart_engine(event_id) do
    :ok = stop_supervised({Engine, event_id})
    pid = start_supervised!({Engine, event_id})
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
  end
end
