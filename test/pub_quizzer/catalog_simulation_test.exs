defmodule PubQuizzer.Quiz.CatalogSimulationTest do
  use PubQuizzer.DataCase, async: false

  # Run with QUIZ_CATALOG_PATH=/path/to/quizzes.json mix test test/pub_quizzer/catalog_simulation_test.exs
  if System.get_env("QUIZ_CATALOG_PATH") do
    alias PubQuizzer.Quiz
    alias PubQuizzer.Quiz.{Engine, Import}

    test "seven real topics play to completion with four teams and survive reconnects" do
      json = File.read!(System.fetch_env!("QUIZ_CATALOG_PATH"))
      {:ok, catalog} = Import.parse_and_validate(json)
      assert catalog.skipped == []
      assert catalog.warnings == []
      assert length(catalog.importable) == 7
      assert Enum.all?(catalog.importable, &(length(&1.questions) == 5))

      {:ok, _} = Import.import(catalog.importable)

      topics =
        Enum.map(catalog.importable, fn entry ->
          topic = Enum.find(Quiz.list_topics(), &(&1.name == entry.name))

          for question <- topic.questions do
            {:ok, _} = Quiz.update_question(question, %{status: "published"})
          end

          topic
        end)

      {:ok, event} = Quiz.create_event(%{team_count: 4})
      for _ <- 1..4, do: {:ok, _} = Quiz.claim_next_team_slot(event)
      {:ok, _} = Engine.ensure_started(event.id)

      on_exit(fn ->
        try do
          GenServer.stop(Engine.via_tuple(event.id), :normal)
        catch
          :exit, _ -> :ok
        end
      end)

      {:ok, state} = Engine.start_quiz(event.id)
      [leader, challenger, wrong, absent] = state.teams

      state =
        Enum.reduce(Enum.with_index(topics), state, fn {topic, round_index}, state ->
          {:ok, state} = Engine.choose_topic(event.id, topic.id, state.current_chooser_team_id)
          assert length(state.current_questions) == 5

          for {question, index} <- Enum.with_index(state.current_questions) do
            assert question.prompt ==
                     Enum.at(Enum.at(catalog.importable, round_index).questions, index)["prompt"]

            assert {:ok, _} =
                     Engine.submit_answer(
                       event.id,
                       leader.id,
                       question.correct_index,
                       question.id
                     )

            if index < 2 do
              assert {:ok, _} =
                       Engine.submit_answer(
                         event.id,
                         challenger.id,
                         question.correct_index,
                         question.id
                       )
            end

            assert {:ok, _} =
                     Engine.submit_answer(
                       event.id,
                       wrong.id,
                       rem(question.correct_index + 1, 4),
                       question.id
                     )

            # Team 4 has a patchy connection and misses this question entirely.
            if index < 4 do
              {:ok, _} = Engine.next_question(event.id)

              assert {:error, :stale_question} =
                       Engine.submit_answer(event.id, absent.id, 0, question.id)
            end
          end

          {:ok, revealed} = Engine.reveal_round(event.id)
          assert revealed.current_winner_team_id == leader.id
          assert revealed.standings[leader.id] == (round_index + 1) * 5
          assert revealed.standings[challenger.id] == (round_index + 1) * 2

          {:ok, _} = Engine.reveal_standings(event.id)
          GenServer.stop(Engine.via_tuple(event.id), :normal)
          {:ok, _} = Engine.ensure_started(event.id)
          {:ok, restored} = Engine.get_state(event.id)
          assert restored.standings_revealed
          {:ok, next_state} = Engine.next_round(event.id)
          next_state
        end)

      assert state.status == :finished
      assert state.standings[leader.id] == 35
      assert state.standings[challenger.id] == 14
      assert state.standings[wrong.id] == 0
      assert state.standings[absent.id] == 0
      assert length(Quiz.list_rounds_for_event(event.id)) == 7
      assert length(Quiz.list_answers_for_event(event.id)) == 84

      results = Quiz.get_event_results(event.id)
      assert Enum.map(results.standings, &elem(&1, 2)) == [35, 14, 0, 0]
      assert results.team_accuracy[leader.id] == {35, 35}
      assert results.team_accuracy[absent.id] == {0, 35}

      for %{round: round, questions: questions} <- results.rounds_data,
          {question, index} <- Enum.with_index(questions) do
        stats = results.question_stats[{round.id, question.id}]
        assert stats.no_answer == if(index < 2, do: 1, else: 2)
      end

      report = Quiz.get_question_report()
      assert length(report) == 35
      assert Enum.all?(report, &(&1.asked_in == 1))

      {:ok, _} = Engine.reveal_final_results(event.id)
      GenServer.stop(Engine.via_tuple(event.id), :normal)
      {:ok, _} = Engine.ensure_started(event.id)
      assert {:ok, %{final_results_revealed: true}} = Engine.get_state(event.id)
    end
  end
end
