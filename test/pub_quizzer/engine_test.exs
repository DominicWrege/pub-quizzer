defmodule PubQuizzer.Quiz.EngineTest do
  use PubQuizzer.DataCase, async: false

  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.Engine

  @topic_attrs %{name: "Engine Test Topic"}
  @questions [
    {"What is 2+2?", ["3", "4", "5", "6"], 1},
    {"Capital of France?", ["London", "Paris", "Rome", "Berlin"], 1},
    {"Color of sky?", ["Red", "Green", "Blue", "Yellow"], 2}
  ]

  defp setup_event_with_topics do
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

    {:ok, event} = Quiz.create_event(%{team_count: 3})

    # Claim all team slots so they appear in engine state
    for _ <- 1..3 do
      {:ok, _} = Quiz.claim_next_team_slot(event)
    end

    event = Quiz.get_event_with_teams!(event.id)
    {event, topic}
  end

  setup do
    {event, topic} = setup_event_with_topics()
    start_engine(event)

    on_exit(fn -> stop_engine(event.id) end)

    {:ok, event: event, topic: topic}
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

  describe "engine lifecycle" do
    test "ensure_started is idempotent", %{event: event} do
      {:ok, pid1} = Engine.ensure_started(event.id)
      {:ok, pid2} = Engine.ensure_started(event.id)
      assert pid1 == pid2
    end

    test "get_state returns the engine state", %{event: event} do
      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :lobby
      assert state.event_id == event.id
    end
  end

  describe "game flow via GenServer" do
    test "full round: start → choose topic → answer → reveal", %{event: event, topic: topic} do
      {:ok, _state} = Engine.start_quiz(event.id)

      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :topic_selection

      {:ok, _state} = Engine.choose_topic(event.id, topic.id, nil)

      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :question
      [t1, t2, _t3 | _] = state.teams

      # correct
      {:ok, _state} = Engine.submit_answer(event.id, t1.id, 1)
      # wrong
      {:ok, _state} = Engine.submit_answer(event.id, t2.id, 0)

      {:ok, state} = Engine.get_state(event.id)
      assert Map.has_key?(state.answers, 0)

      {:ok, _state} = Engine.reveal_round(event.id)

      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :round_reveal
      assert state.current_winner_team_id == t1.id
    end

    test "next_round finishes when no topics remain", %{event: event, topic: topic} do
      Engine.start_quiz(event.id)
      Engine.choose_topic(event.id, topic.id, nil)
      Engine.reveal_round(event.id)
      Engine.next_round(event.id)

      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :finished
    end

    test "broadcasts state via PubSub", %{event: event, topic: topic} do
      Phoenix.PubSub.subscribe(PubQuizzer.PubSub, Engine.topic(event.id))

      Engine.start_quiz(event.id)
      assert_receive {:engine_state, state}
      assert state.status == :topic_selection

      Engine.choose_topic(event.id, topic.id, nil)
      assert_receive {:engine_state, state}
      assert state.status == :question
    end
  end

  describe "persistence" do
    test "persists round on topic choice", %{event: event, topic: topic} do
      Engine.start_quiz(event.id)
      Engine.choose_topic(event.id, topic.id, nil)

      round = PubQuizzer.Repo.one(PubQuizzer.Quiz.Round)
      assert round != nil
      assert round.topic_id == topic.id
      assert round.round_number == 0
    end

    test "persists answers on submission", %{event: event, topic: topic} do
      Engine.start_quiz(event.id)
      Engine.choose_topic(event.id, topic.id, nil)
      {:ok, state} = Engine.get_state(event.id)
      [t1 | _] = state.teams

      Engine.submit_answer(event.id, t1.id, 1)

      answer = PubQuizzer.Repo.one(PubQuizzer.Quiz.Answer)
      assert answer != nil
      assert answer.selected_index == 1
      assert answer.team_id == t1.id
    end

    test "persists round winner on reveal", %{event: event, topic: topic} do
      Engine.start_quiz(event.id)
      Engine.choose_topic(event.id, topic.id, nil)
      {:ok, state} = Engine.get_state(event.id)
      [t1, t2 | _] = state.teams

      # correct
      Engine.submit_answer(event.id, t1.id, 1)
      # wrong
      Engine.submit_answer(event.id, t2.id, 0)
      Engine.reveal_round(event.id)

      round = PubQuizzer.Repo.one(PubQuizzer.Quiz.Round)
      assert round.winner_team_id == t1.id
    end

    test "updates event status on transitions", %{event: event, topic: topic} do
      event_id = event.id

      Engine.start_quiz(event_id)
      event = PubQuizzer.Repo.get!(PubQuizzer.Quiz.QuizEvent, event_id)
      assert event.status == "topic_selection"

      Engine.choose_topic(event_id, topic.id, nil)
      event = PubQuizzer.Repo.get!(PubQuizzer.Quiz.QuizEvent, event_id)
      assert event.status == "question"

      Engine.reveal_round(event_id)
      event = PubQuizzer.Repo.get!(PubQuizzer.Quiz.QuizEvent, event_id)
      assert event.status == "round_reveal"
    end
  end

  describe "error handling" do
    test "get_state on non-existent engine returns error" do
      assert {:error, :not_found} = Engine.get_state(99999)
    end

    test "submit_answer before question phase returns error", %{event: event} do
      {:ok, state} = Engine.get_state(event.id)
      [t1 | _] = state.teams

      assert {:error, :not_in_question_phase} = Engine.submit_answer(event.id, t1.id, 0)
    end
  end

  describe "state recovery after restart" do
    setup do
      # Create a second topic so the game doesn't finish after one round
      {:ok, topic2} = Quiz.create_topic(%{name: "Recovery Topic 2"})

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

      {:ok, topic2: topic2}
    end

    test "recovers :question state with answers", %{event: event, topic: topic} do
      [t1, t2 | _] = Quiz.list_teams_for_event(event.id)

      Engine.start_quiz(event.id)
      Engine.choose_topic(event.id, topic.id, nil)
      Engine.submit_answer(event.id, t1.id, 1)
      Engine.submit_answer(event.id, t2.id, 0)

      # Stop engine (simulates crash)
      stop_engine(event.id)

      # Restart — state should be recovered from DB
      {:ok, _pid} = Engine.ensure_started(event.id)

      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :question
      assert state.current_topic_id == topic.id
      assert state.round_number == 0
      assert state.question_index == 0
      assert length(state.current_questions) == 3

      # Answers recovered
      q0_answers = Map.get(state.answers, 0, %{})
      assert Map.get(q0_answers, t1.id) == 1
      assert Map.get(q0_answers, t2.id) == 0

      # Standings not yet updated (reveal hasn't happened)
      assert Map.get(state.standings, t1.id) == 0
    end

    test "recovers :round_reveal state with winner and standings", %{
      event: event,
      topic: topic,
      topic2: topic2
    } do
      [t1, t2 | _] = Quiz.list_teams_for_event(event.id)

      Engine.start_quiz(event.id)
      Engine.choose_topic(event.id, topic.id, nil)
      Engine.submit_answer(event.id, t1.id, 1)
      Engine.submit_answer(event.id, t2.id, 0)
      Engine.reveal_round(event.id)

      # Stop and restart
      stop_engine(event.id)
      {:ok, _pid} = Engine.ensure_started(event.id)

      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :round_reveal
      assert state.current_winner_team_id == t1.id
      assert Map.get(state.standings, t1.id) == 1
      assert Map.get(state.standings, t2.id) == 0
      assert length(state.completed_rounds) == 1

      # Can continue: next_round → topic_selection with chooser = t1
      Engine.next_round(event.id)
      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :topic_selection
      assert state.current_chooser_team_id == t1.id

      # Can choose topic2 and play
      Engine.choose_topic(event.id, topic2.id, t1.id)
      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :question
      assert state.current_topic_id == topic2.id
    end

    test "recovers :topic_selection state with chooser", %{
      event: event,
      topic: topic
    } do
      [t1, t2 | _] = Quiz.list_teams_for_event(event.id)

      Engine.start_quiz(event.id)
      Engine.choose_topic(event.id, topic.id, nil)
      Engine.submit_answer(event.id, t1.id, 1)
      Engine.submit_answer(event.id, t2.id, 0)
      Engine.reveal_round(event.id)
      Engine.next_round(event.id)

      # Stop and restart
      stop_engine(event.id)
      {:ok, _pid} = Engine.ensure_started(event.id)

      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :topic_selection
      assert state.round_number == 1
      assert state.current_chooser_team_id == t1.id
      assert length(state.completed_rounds) == 1
    end

    test "recovers :finished state with final standings", %{
      event: event,
      topic: topic,
      topic2: topic2
    } do
      [t1, t2 | _] = Quiz.list_teams_for_event(event.id)

      # Play round 1
      Engine.start_quiz(event.id)
      Engine.choose_topic(event.id, topic.id, nil)
      Engine.submit_answer(event.id, t1.id, 1)
      Engine.submit_answer(event.id, t2.id, 0)
      Engine.reveal_round(event.id)
      Engine.next_round(event.id)

      # Play round 2 (last topic)
      {:ok, state} = Engine.get_state(event.id)
      Engine.choose_topic(event.id, topic2.id, state.current_chooser_team_id)
      Engine.submit_answer(event.id, t1.id, 1)
      Engine.submit_answer(event.id, t2.id, 0)
      Engine.reveal_round(event.id)
      Engine.next_round(event.id)

      # Stop and restart
      stop_engine(event.id)
      {:ok, _pid} = Engine.ensure_started(event.id)

      {:ok, state} = Engine.get_state(event.id)
      assert state.status == :finished
      assert Map.get(state.standings, t1.id) == 2
      assert Map.get(state.standings, t2.id) == 0
    end
  end
end
