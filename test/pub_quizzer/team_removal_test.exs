defmodule PubQuizzer.Quiz.TeamRemovalTest do
  use PubQuizzer.DataCase, async: false

  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.{Engine, EngineState, Team}

  setup do
    topics =
      for name <- ["First topic", "Next topic"] do
        {:ok, topic} = Quiz.create_topic(%{name: name})

        {:ok, _} =
          Quiz.create_question(%{
            topic_id: topic.id,
            prompt: "Which answer?",
            options: ["Correct", "Wrong"],
            correct_index: 0,
            status: "published"
          })

        topic
      end

    {:ok, event} = Quiz.create_event(%{team_count: 3})
    {:ok, first} = Quiz.claim_next_team_slot(event)
    {:ok, second} = Quiz.claim_next_team_slot(event)
    start_supervised!({Engine, event.id})
    {:ok, _} = Engine.start_quiz(event.id)

    %{event: event, first: first, second: second, topics: topics}
  end

  test "removing a team excludes its answers and broadcasts the new roster", %{
    event: event,
    first: first,
    second: second,
    topics: [topic | _]
  } do
    {:ok, _} = Engine.choose_topic(event.id, topic.id)
    {:ok, _} = Engine.submit_answer(event.id, first.id, 0)
    {:ok, _} = Engine.submit_answer(event.id, second.id, 1)
    Phoenix.PubSub.subscribe(PubQuizzer.PubSub, Engine.topic(event.id))

    assert {:ok, state} = Engine.remove_team(event.id, first.id)

    assert Enum.map(state.teams, & &1.id) == [second.id]
    assert EngineState.answered_teams(state) == MapSet.new([second.id])
    assert EngineState.answer_distribution(state) == %{0 => 0, 1 => 1}
    refute Map.has_key?(state.standings, first.id)

    assert Quiz.list_answers_for_round(state.current_round_id) |> Enum.map(& &1.team_id) ==
             [second.id]

    assert Repo.get(Team, first.id) == nil
    assert Quiz.get_event!(event.id).team_count == 2
    assert_receive {:kick_team, team_id}
    assert team_id == first.id
    assert_receive {:engine_state, broadcast_state}
    assert Enum.map(broadcast_state.teams, & &1.id) == [second.id]
    assert {:error, :invalid_submission} = Engine.submit_answer(event.id, first.id, 0)

    assert {:ok, revealed} = Engine.reveal_round(event.id)
    assert revealed.current_winner_team_id == nil
    assert revealed.standings == %{second.id => 0}
  end

  for phase <- [:round_reveal, :topic_selection] do
    test "removing the winner in #{phase} clears priority, including after restart", %{
      event: event,
      first: first,
      second: second,
      topics: [topic | _]
    } do
      {:ok, _} = Engine.choose_topic(event.id, topic.id)
      {:ok, _} = Engine.submit_answer(event.id, first.id, 0)
      {:ok, _} = Engine.submit_answer(event.id, second.id, 1)
      {:ok, _} = Engine.reveal_round(event.id)
      if unquote(phase) == :topic_selection, do: Engine.next_round(event.id)

      assert {:ok, state} = Engine.remove_team(event.id, first.id)
      assert state.current_chooser_team_id == nil
      assert state.current_winner_team_id == nil
      assert Enum.all?(state.completed_rounds, &is_nil(&1.winner_team_id))
      assert EngineState.standings_sorted(state) == [{second.id, second.name, 0}]
      assert hd(Quiz.list_rounds_for_event(event.id)).winner_team_id == nil

      stop_supervised!({Engine, event.id})
      start_supervised!({Engine, event.id})
      {:ok, recovered} = Engine.get_state(event.id)
      assert Enum.map(recovered.teams, & &1.id) == [second.id]
      assert recovered.current_chooser_team_id == nil
      assert recovered.current_winner_team_id == nil
      assert recovered.standings == %{second.id => 0}
    end
  end

  test "the last participating team cannot be removed even with unused slots", %{
    event: event,
    first: first,
    second: second
  } do
    assert {:ok, _} = Engine.remove_team(event.id, first.id)
    assert {:error, :last_team} = Engine.remove_team(event.id, second.id)
    assert Repo.get(Team, second.id) != nil
    assert Quiz.get_event!(event.id).team_count == 2
  end

  test "a foreign team cannot be removed", %{event: event} do
    {:ok, other} = Quiz.create_event(%{team_count: 2})
    {:ok, foreign} = Quiz.claim_next_team_slot(other)

    assert {:error, :not_found} = Engine.remove_team(event.id, foreign.id)
    assert Repo.get(Team, foreign.id) != nil
    assert Quiz.get_event!(event.id).team_count == 3
  end

  test "an unclaimed slot cannot be registered once the quiz starts", %{event: event} do
    unused = List.last(event.teams)

    assert {:error, :quiz_started} =
             Engine.register_team(event.id, unused.id, unused.name, unused.slot_index)
  end

  test "a removed team cannot choose the next topic with a delayed request", %{
    event: event,
    first: first,
    topics: [topic, next_topic]
  } do
    {:ok, _} = Engine.choose_topic(event.id, topic.id)
    {:ok, _} = Engine.submit_answer(event.id, first.id, 0)
    {:ok, _} = Engine.reveal_round(event.id)
    {:ok, _} = Engine.next_round(event.id)
    {:ok, _} = Engine.remove_team(event.id, first.id)

    assert {:error, :invalid_chooser} = Engine.choose_topic(event.id, next_topic.id, first.id)
    assert {:ok, state} = Engine.choose_topic(event.id, next_topic.id)
    assert state.current_chooser_team_id == nil
  end

  test "registering a returning team keeps its score and answers", %{
    event: event,
    first: first,
    topics: [topic | _]
  } do
    {:ok, _} = Engine.choose_topic(event.id, topic.id)
    {:ok, _} = Engine.submit_answer(event.id, first.id, 0)
    {:ok, _} = Engine.reveal_round(event.id)

    assert {:ok, state} =
             Engine.register_team(event.id, first.id, first.name, first.slot_index)

    assert length(state.teams) == 2
    assert state.standings[first.id] == 1
    assert state.answers[0][first.id] == 0
  end

  test "finished quizzes cannot lose teams or their results", %{event: event, first: first} do
    {:ok, _} = Engine.finish_quiz(event.id)

    assert {:error, :not_in_active_quiz} = Engine.remove_team(event.id, first.id)
    assert Repo.get(Team, first.id) != nil
  end
end
