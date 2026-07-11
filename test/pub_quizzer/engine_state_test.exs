defmodule PubQuizzer.Quiz.EngineStateTest do
  use PubQuizzer.DataCase, async: false

  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.EngineState

  @topic_attrs %{name: "Test Topic", description: "Test"}
  @questions [
    {"What is 2+2?", ["3", "4", "5", "6"], 1},
    {"Capital of France?", ["London", "Paris", "Rome", "Berlin"], 1},
    {"Color of sky?", ["Red", "Green", "Blue", "Yellow"], 2}
  ]

  defp create_topic_with_questions do
    {:ok, topic} = Quiz.create_topic(@topic_attrs)

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

    topic
  end

  defp create_event_with_teams(team_count \\ 3) do
    {:ok, event} = Quiz.create_event(%{team_count: team_count})

    for _ <- 1..team_count do
      {:ok, _} = Quiz.claim_next_team_slot(event)
    end

    Quiz.get_event_with_teams!(event.id)
  end

  defp fresh_state do
    event = create_event_with_teams()
    topic = create_topic_with_questions()
    EngineState.new(event, event.teams, [topic], max_rounds: 7)
  end

  defp fresh_state_multi_topic do
    event = create_event_with_teams()
    t1 = create_topic_with_questions()
    t2 = Quiz.create_topic(%{name: "Second Topic"}) |> elem(1)

    for {{prompt, options, correct}, idx} <- Enum.with_index(@questions) do
      Quiz.create_question(%{
        prompt: "Second: #{prompt}",
        options: options,
        correct_index: correct,
        topic_id: t2.id,
        position: idx
      })
    end

    EngineState.new(event, event.teams, [t1, t2], max_rounds: 7)
  end

  describe "new/3" do
    test "creates initial state in lobby" do
      state = fresh_state()
      assert state.status == :lobby
      assert state.round_number == 0
      assert state.question_index == 0
      assert length(state.teams) == 3
      assert length(state.available_topics) == 1

      for team <- state.teams do
        assert Map.get(state.standings, team.id) == 0
      end
    end

    test "initializes standings to 0 for all teams" do
      state = fresh_state()

      for team <- state.teams do
        assert Map.get(state.standings, team.id) == 0
      end
    end
  end

  describe "start_quiz/1" do
    test "transitions from lobby to topic_selection" do
      state = fresh_state()
      {:ok, new_state} = EngineState.start_quiz(state)
      assert new_state.status == :topic_selection
      assert new_state.round_number == 0
      # host picks round 1
      assert new_state.current_chooser_team_id == nil
    end

    test "fails if not in lobby" do
      state = fresh_state() |> Map.put(:status, :topic_selection)
      assert {:error, :not_in_lobby} = EngineState.start_quiz(state)
    end
  end

  describe "choose_topic/3" do
    test "transitions from topic_selection to question" do
      state = fresh_state() |> then_engine_start()
      topic_id = hd(state.available_topics).id
      {:ok, new_state} = EngineState.choose_topic(state, topic_id, nil)
      assert new_state.status == :question
      assert new_state.current_topic_id == topic_id
      assert new_state.question_index == 0
      assert length(new_state.current_questions) == 3
      assert new_state.answers == %{}
    end

    test "fails if topic not available" do
      state = fresh_state() |> then_engine_start()
      assert {:error, :topic_not_available} = EngineState.choose_topic(state, 99999, nil)
    end

    test "fails if not in topic_selection" do
      state = fresh_state()
      topic_id = hd(state.available_topics).id
      assert {:error, :not_in_topic_selection} = EngineState.choose_topic(state, topic_id, nil)
    end
  end

  describe "submit_answer/3" do
    test "records an answer for the current question" do
      state = fresh_state() |> then_engine_start() |> then_choose_topic()
      team_id = hd(state.teams).id
      {:ok, new_state} = EngineState.submit_answer(state, team_id, 1)
      answers = Map.get(new_state.answers, 0)
      assert Map.get(answers, team_id) == 1
    end

    test "allows updating an answer" do
      state = fresh_state() |> then_engine_start() |> then_choose_topic()
      team_id = hd(state.teams).id
      {:ok, s1} = EngineState.submit_answer(state, team_id, 0)
      {:ok, s2} = EngineState.submit_answer(s1, team_id, 1)
      answers = Map.get(s2.answers, 0)
      assert Map.get(answers, team_id) == 1
    end

    test "rejects invalid team" do
      state = fresh_state() |> then_engine_start() |> then_choose_topic()
      assert {:error, :invalid_submission} = EngineState.submit_answer(state, 99999, 0)
    end

    test "rejects out-of-range option index" do
      state = fresh_state() |> then_engine_start() |> then_choose_topic()
      team_id = hd(state.teams).id
      assert {:error, :invalid_submission} = EngineState.submit_answer(state, team_id, 99)
    end

    test "fails if not in question phase" do
      state = fresh_state()
      team_id = hd(state.teams).id
      assert {:error, :not_in_question_phase} = EngineState.submit_answer(state, team_id, 0)
    end
  end

  describe "next_question/1" do
    test "advances to the next question" do
      state = fresh_state() |> then_engine_start() |> then_choose_topic()
      {:ok, new_state} = EngineState.next_question(state)
      assert new_state.question_index == 1
    end

    test "fails on last question" do
      state = fresh_state() |> then_engine_start() |> then_choose_topic()
      # Q0 → Q1
      {:ok, s1} = EngineState.next_question(state)
      # Q1 → Q2
      {:ok, s2} = EngineState.next_question(s1)
      # Q2 is last
      assert {:error, :end_of_round} = EngineState.next_question(s2)
    end
  end

  describe "reveal_round/1" do
    test "transitions from question to round_reveal" do
      state = fresh_state() |> then_engine_start() |> then_choose_topic()
      {:ok, new_state} = EngineState.reveal_round(state)
      assert new_state.status == :round_reveal
    end

    test "computes correct scores and determines winner" do
      state = fresh_state() |> then_engine_start() |> then_choose_topic()
      # Q0 correct answer is index 1 ("4")
      # Team 1 answers correctly, Team 2 answers wrong, Team 3 answers correctly
      [t1, t2, t3 | _] = state.teams
      # correct
      {:ok, s1} = EngineState.submit_answer(state, t1.id, 1)
      # wrong
      {:ok, s2} = EngineState.submit_answer(s1, t2.id, 0)
      # correct
      {:ok, s3} = EngineState.submit_answer(s2, t3.id, 1)

      {:ok, revealed} = EngineState.reveal_round(s3)
      # Two teams tied at 1 point each → nil (tie → host picks)
      assert revealed.current_winner_team_id == nil
    end

    test "single winner gets identified" do
      state = fresh_state() |> then_engine_start() |> then_choose_topic()
      [t1, t2, t3 | _] = state.teams
      # correct
      {:ok, s1} = EngineState.submit_answer(state, t1.id, 1)
      # wrong
      {:ok, s2} = EngineState.submit_answer(s1, t2.id, 0)
      # wrong
      {:ok, s3} = EngineState.submit_answer(s2, t3.id, 0)

      {:ok, revealed} = EngineState.reveal_round(s3)
      assert revealed.current_winner_team_id == t1.id
    end

    test "updates cumulative standings" do
      state = fresh_state() |> then_engine_start() |> then_choose_topic()
      [t1, _t2, t3 | _] = state.teams
      # correct
      {:ok, s1} = EngineState.submit_answer(state, t1.id, 1)
      # correct
      {:ok, s2} = EngineState.submit_answer(s1, t3.id, 1)

      {:ok, revealed} = EngineState.reveal_round(s2)
      assert Map.get(revealed.standings, t1.id) == 1
      assert Map.get(revealed.standings, t3.id) == 1
    end

    test "records completed round" do
      state = fresh_state() |> then_engine_start() |> then_choose_topic()
      {:ok, revealed} = EngineState.reveal_round(state)
      assert length(revealed.completed_rounds) == 1
      assert hd(revealed.completed_rounds).round_number == 0
    end
  end

  describe "next_round/1" do
    test "transitions to topic_selection with winner as chooser" do
      state = fresh_state_multi_topic() |> then_engine_start()
      {:ok, chosen} = then_choose_topic_multi(state)
      [t1, t2, t3 | _] = chosen.teams
      # correct
      {:ok, s1} = EngineState.submit_answer(chosen, t1.id, 1)
      # wrong
      {:ok, s2} = EngineState.submit_answer(s1, t2.id, 0)
      # wrong
      {:ok, s3} = EngineState.submit_answer(s2, t3.id, 0)
      {:ok, revealed} = EngineState.reveal_round(s3)

      {:ok, next} = EngineState.next_round(revealed)
      assert next.status == :topic_selection
      assert next.round_number == 1
      assert next.current_chooser_team_id == t1.id
    end

    test "transitions to topic_selection with host as chooser on tie" do
      state = fresh_state_multi_topic() |> then_engine_start()
      {:ok, chosen} = then_choose_topic_multi(state)
      [t1, _t2, t3 | _] = chosen.teams
      # correct
      {:ok, s1} = EngineState.submit_answer(chosen, t1.id, 1)
      # correct
      {:ok, s2} = EngineState.submit_answer(s1, t3.id, 1)
      {:ok, revealed} = EngineState.reveal_round(s2)

      {:ok, next} = EngineState.next_round(revealed)
      assert next.status == :topic_selection
      # host picks on tie
      assert next.current_chooser_team_id == nil
    end

    test "transitions to finished when no topics remain" do
      state = fresh_state() |> then_engine_start() |> then_choose_topic()
      {:ok, revealed} = EngineState.reveal_round(state)
      {:ok, next} = EngineState.next_round(revealed)
      assert next.status == :finished
    end

    test "transitions to finished when max_rounds reached" do
      state = fresh_state_multi_topic() |> Map.put(:max_rounds, 1)
      {:ok, started} = EngineState.start_quiz(state)
      topic_id = hd(state.available_topics).id
      {:ok, chosen} = EngineState.choose_topic(started, topic_id, nil)
      {:ok, revealed} = EngineState.reveal_round(chosen)
      {:ok, next} = EngineState.next_round(revealed)
      assert next.status == :finished
    end

    test "transitions to host chooser when no winner (all wrong)" do
      state = fresh_state_multi_topic() |> then_engine_start()
      {:ok, chosen} = then_choose_topic_multi(state)
      [t1, t2, _t3 | _] = chosen.teams
      # wrong
      {:ok, s1} = EngineState.submit_answer(chosen, t1.id, 0)
      # wrong
      {:ok, s2} = EngineState.submit_answer(s1, t2.id, 0)
      {:ok, revealed} = EngineState.reveal_round(s2)

      {:ok, next} = EngineState.next_round(revealed)
      assert next.status == :topic_selection
      # host picks (no winner)
      assert next.current_chooser_team_id == nil
    end
  end

  describe "full game cycle" do
    test "complete game: start → 2 rounds → finish" do
      state = fresh_state_multi_topic()

      # Round 1
      {:ok, s1} = EngineState.start_quiz(state)
      topic1_id = hd(s1.available_topics).id
      {:ok, s2} = EngineState.choose_topic(s1, topic1_id, nil)
      [t1, t2, t3 | _] = s2.teams
      {:ok, s3} = EngineState.submit_answer(s2, t1.id, 1)
      {:ok, s4} = EngineState.submit_answer(s3, t2.id, 0)
      {:ok, s5} = EngineState.submit_answer(s4, t3.id, 0)
      {:ok, s6} = EngineState.reveal_round(s5)
      assert s6.current_winner_team_id == t1.id

      # Round 2
      {:ok, s7} = EngineState.next_round(s6)
      assert s7.status == :topic_selection
      assert s7.current_chooser_team_id == t1.id

      topic2_id = Enum.at(s7.available_topics, 1).id
      {:ok, s8} = EngineState.choose_topic(s7, topic2_id, t1.id)
      {:ok, s9} = EngineState.submit_answer(s8, t1.id, 1)
      {:ok, s10} = EngineState.submit_answer(s9, t2.id, 1)
      {:ok, s11} = EngineState.submit_answer(s10, t3.id, 0)
      {:ok, s12} = EngineState.reveal_round(s11)

      # No more topics → finished
      {:ok, s13} = EngineState.next_round(s12)
      assert s13.status == :finished
      assert length(s13.completed_rounds) == 2
    end
  end

  describe "queries" do
    test "current_question returns the active question" do
      state = fresh_state() |> then_engine_start() |> then_choose_topic()
      q = EngineState.current_question(state)
      assert q.prompt == "What is 2+2?"
    end

    test "answered_teams returns set of teams who answered current question" do
      state = fresh_state() |> then_engine_start() |> then_choose_topic()
      [t1, _t2, _t3 | _] = state.teams
      {:ok, s1} = EngineState.submit_answer(state, t1.id, 1)

      answered = EngineState.answered_teams(s1)
      assert MapSet.size(answered) == 1
      assert MapSet.member?(answered, t1.id)
    end

    test "standings_sorted returns teams sorted by score desc" do
      state = fresh_state() |> then_engine_start() |> then_choose_topic()
      [t1, t2, t3 | _] = state.teams
      # correct
      {:ok, s1} = EngineState.submit_answer(state, t1.id, 1)
      # wrong
      {:ok, s2} = EngineState.submit_answer(s1, t2.id, 0)
      # correct
      {:ok, s3} = EngineState.submit_answer(s2, t3.id, 1)
      {:ok, revealed} = EngineState.reveal_round(s3)

      sorted = EngineState.standings_sorted(revealed)
      {_, _, s1_score} = Enum.at(sorted, 0)
      {_, _, s2_score} = Enum.at(sorted, 1)
      {_, _, s3_score} = Enum.at(sorted, 2)
      assert s1_score >= s2_score
      assert s2_score >= s3_score
    end
  end

  # --- Helpers ---

  defp then_engine_start(state) do
    {:ok, new_state} = EngineState.start_quiz(state)
    new_state
  end

  defp then_choose_topic(state) do
    topic_id = hd(state.available_topics).id
    {:ok, new_state} = EngineState.choose_topic(state, topic_id, nil)
    new_state
  end

  defp then_choose_topic_multi(state) do
    topic_id = hd(state.available_topics).id
    {:ok, new_state} = EngineState.choose_topic(state, topic_id, nil)
    {:ok, new_state}
  end
end
