defmodule PubQuizzer.Quiz.EngineState do
  @moduledoc """
  Pure state struct and transition functions for the quiz game engine.

  All functions take a state and return {:ok, new_state} or {:error, reason}.
  No side effects — the GenServer handles persistence and broadcasting.
  """

  defstruct [
    :event_id,
    :code,
    status: :lobby,
    round_number: 0,
    question_index: 0,
    teams: [],
    available_topics: [],
    current_topic_id: nil,
    current_questions: [],
    current_chooser_team_id: nil,
    current_winner_team_id: nil,
    # DB id of the Round row for the in-progress/current round. Set by the
    # engine after persisting the round; nil in lobby/topic_selection/finished.
    current_round_id: nil,
    reveal_answer_index: 0,
    standings_revealed: false,
    final_results_revealed: false,
    # answers: %{question_index => %{team_id => selected_index}}
    answers: %{},
    # standings: %{team_id => total_points}
    standings: %{},
    # completed rounds: list of %{round_number, topic_id, winner_team_id}
    completed_rounds: [],
    max_rounds: 7
  ]

  @type t :: %__MODULE__{}
  @type command_result :: {:ok, t()} | {:error, atom()}

  @doc """
  Returns a copy of the state safe for team clients.

  During the `:question` phase, teams see only A/B/C/D buttons — they never need
  `correct_index`, the question `prompt`, or option `text`/`image`. Stripping
  these prevents leaks via dev tools and shrinks the assigns.

  During `:round_reveal` the host shows the answers, so the full question set
  must be preserved.
  """
  def strip_for_team(%__MODULE__{status: :question} = state) do
    slim_questions =
      Enum.map(state.current_questions, fn q ->
        # Preserve option count (shuffle relies on list length); drop text/image/correct_index.
        blank_options = Enum.map(q.options, fn _ -> %{} end)
        %{id: q.id, position: q.position, options: blank_options}
      end)

    %{state | current_questions: slim_questions}
  end

  def strip_for_team(%__MODULE__{} = state), do: state

  # --- Initialization ---

  def new(event, teams, topics, opts \\ []) do
    claimed = Enum.filter(teams, & &1.claimed_at)

    %__MODULE__{
      event_id: event.id,
      code: event.code,
      status: :lobby,
      teams: Enum.map(claimed, fn t -> %{id: t.id, name: t.name, slot_index: t.slot_index} end),
      available_topics: Enum.map(topics, fn t -> %{id: t.id, name: t.name} end),
      standings: Map.new(claimed, fn t -> {t.id, 0} end),
      max_rounds: Keyword.get(opts, :max_rounds, 7)
    }
  end

  # --- Transitions ---

  @doc """
  Start the quiz: lobby → topic_selection (round 1, host picks).
  """
  def start_quiz(%__MODULE__{status: :lobby} = state) do
    {:ok, %{state | status: :topic_selection, round_number: 0, current_chooser_team_id: nil}}
  end

  def start_quiz(%__MODULE__{}), do: {:error, :not_in_lobby}

  @doc """
  Choose a topic for the current round: topic_selection → question.
  `chooser_team_id` is nil when the host picks (round 1 or tie).
  """
  def choose_topic(%__MODULE__{status: :topic_selection} = state, topic_id, chooser_team_id) do
    case Enum.find(state.available_topics, fn t -> t.id == topic_id end) do
      nil ->
        {:error, :topic_not_available}

      _topic ->
        questions = PubQuizzer.Quiz.load_questions_for_engine(topic_id)

        if questions == [] do
          {:error, :topic_has_no_questions}
        else
          new_state = %{
            state
            | status: :question,
              current_topic_id: topic_id,
              current_questions: questions,
              current_chooser_team_id: chooser_team_id,
              question_index: 0,
              answers: %{}
          }

          {:ok, new_state}
        end
    end
  end

  def choose_topic(%__MODULE__{}, _topic_id, _chooser), do: {:error, :not_in_topic_selection}

  @doc """
  Submit or update an answer for the current question.
  Teams can change their answer until the host advances.
  """
  def submit_answer(%__MODULE__{status: :question} = state, team_id, selected_index) do
    if valid_team?(state, team_id) and valid_option?(state, selected_index) do
      question_answers = Map.get(state.answers, state.question_index, %{})
      updated = Map.put(question_answers, team_id, selected_index)

      {:ok, %{state | answers: Map.put(state.answers, state.question_index, updated)}}
    else
      {:error, :invalid_submission}
    end
  end

  def submit_answer(%__MODULE__{}, _team_id, _selected_index),
    do: {:error, :not_in_question_phase}

  @doc """
  Advance to the next question. Locks the current question (no more answer changes).
  If this was the last question, returns {:ok, state} with :end_of_round hint.
  """
  def next_question(%__MODULE__{status: :question} = state) do
    if state.question_index < length(state.current_questions) - 1 do
      {:ok, %{state | question_index: state.question_index + 1}}
    else
      {:error, :end_of_round}
    end
  end

  def next_question(%__MODULE__{}), do: {:error, :not_in_question_phase}

  @doc """
  End the current round: question → round_reveal.
  Computes scores, determines the winner.
  """
  def reveal_round(%__MODULE__{status: :question} = state) do
    scores = compute_round_scores(state)
    winner_team_id = determine_winner(scores)

    new_standings =
      Map.merge(state.standings, scores, fn _k, existing, round_score ->
        existing + round_score
      end)

    round_summary = %{
      round_number: state.round_number,
      topic_id: state.current_topic_id,
      winner_team_id: winner_team_id
    }

    new_state = %{
      state
      | status: :round_reveal,
        current_winner_team_id: winner_team_id,
        standings: new_standings,
        completed_rounds: state.completed_rounds ++ [round_summary],
        reveal_answer_index: 1,
        standings_revealed: false
    }

    {:ok, new_state}
  end

  def reveal_round(%__MODULE__{}), do: {:error, :not_in_question_phase}

  @doc """
  Reveal the next answer in round_reveal phase.
  Increments reveal_answer_index. Returns :all_revealed when done.
  """
  def reveal_next_answer(%__MODULE__{status: :round_reveal} = state) do
    total = length(state.current_questions)

    if state.reveal_answer_index < total do
      {:ok, %{state | reveal_answer_index: state.reveal_answer_index + 1}}
    else
      {:ok, state, :all_revealed}
    end
  end

  def reveal_next_answer(%__MODULE__{}), do: {:error, :not_in_round_reveal}

  @doc """
  Reveal team standings to all devices.
  """
  def reveal_standings(%__MODULE__{status: :round_reveal} = state) do
    {:ok, %{state | standings_revealed: true}}
  end

  def reveal_standings(%__MODULE__{}), do: {:error, :not_in_round_reveal}

  @doc """
  Start the next round: round_reveal → topic_selection (winner picks)
  or round_reveal → finished (if no more topics or max rounds reached).

  Returns {:ok, state} where state is either :topic_selection or :finished.
  """
  def next_round(%__MODULE__{status: :round_reveal} = state) do
    used_topic_ids = Enum.map(state.completed_rounds, & &1.topic_id) |> Enum.filter(& &1)
    remaining_topics = Enum.reject(state.available_topics, fn t -> t.id in used_topic_ids end)
    next_round_number = state.round_number + 1

    cond do
      remaining_topics == [] ->
        {:ok, %{state | status: :finished, current_round_id: nil}}

      next_round_number >= state.max_rounds ->
        {:ok, %{state | status: :finished, current_round_id: nil}}

      state.current_winner_team_id == nil ->
        # No winner (e.g. no correct answers) — host picks
        {:ok,
         %{
           state
           | status: :topic_selection,
             round_number: next_round_number,
             current_chooser_team_id: nil,
             question_index: 0,
             answers: %{},
             current_questions: [],
             current_topic_id: nil,
             current_winner_team_id: nil,
             current_round_id: nil
         }}

      true ->
        {:ok,
         %{
           state
           | status: :topic_selection,
             round_number: next_round_number,
             current_chooser_team_id: state.current_winner_team_id,
             question_index: 0,
             answers: %{},
             current_questions: [],
             current_topic_id: nil,
             current_winner_team_id: nil,
             current_round_id: nil
         }}
    end
  end

  def next_round(%__MODULE__{}), do: {:error, :not_in_round_reveal}

  @doc """
  Manually finish the quiz (host can end early).
  """
  def finish_quiz(%__MODULE__{status: status} = state)
      when status in [:topic_selection, :question, :round_reveal] do
    {:ok, %{state | status: :finished}}
  end

  def finish_quiz(%__MODULE__{status: :finished}), do: {:error, :already_finished}
  def finish_quiz(%__MODULE__{status: :lobby}), do: {:error, :not_started}

  @doc """
  Reveal the final results on the finished screen (host trigger).
  Sets final_results_revealed so all lobbies show the winner/podium.
  """
  def reveal_final_results(%__MODULE__{status: :finished} = state) do
    {:ok, Map.put(state, :final_results_revealed, true)}
  end

  def reveal_final_results(%__MODULE__{}), do: {:error, :not_finished}

  # --- Queries ---

  def current_question(%__MODULE__{
        status: :question,
        current_questions: questions,
        question_index: idx
      }) do
    Enum.at(questions, idx)
  end

  def current_question(_), do: nil

  def answered_teams(%__MODULE__{status: :question, answers: answers, question_index: idx}) do
    answers
    |> Map.get(idx, %{})
    |> Map.keys()
    |> MapSet.new()
  end

  def answered_teams(_), do: MapSet.new()

  def standings_sorted(%__MODULE__{standings: standings, teams: teams}) do
    teams
    |> Enum.map(fn t -> {t.id, t.name, Map.get(standings, t.id, 0)} end)
    |> Enum.sort_by(fn {_, _, score} -> score end, :desc)
  end

  @doc """
  Returns the list of topics that haven't been used in a completed round yet.
  """
  def available_topics(%__MODULE__{available_topics: topics, completed_rounds: rounds}) do
    used_ids = Enum.map(rounds, & &1.topic_id) |> Enum.filter(& &1)
    Enum.reject(topics, fn t -> t.id in used_ids end)
  end

  @doc """
  Returns the name of the currently selected topic, or nil.
  """
  def current_topic_name(%__MODULE__{current_topic_id: nil}), do: nil

  def current_topic_name(%__MODULE__{current_topic_id: id, available_topics: topics}) do
    Enum.find_value(topics, fn t -> if t.id == id, do: t.name end)
  end

  @doc """
  Register a newly joined team in the engine state.
  """
  def register_team(%__MODULE__{} = state, team_id, name, slot_index) do
    if Enum.any?(state.teams, &(&1.id == team_id)) do
      {:ok, state}
    else
      team = %{id: team_id, name: name, slot_index: slot_index}

      {:ok,
       %{
         state
         | teams: state.teams ++ [team],
           standings: Map.put(state.standings, team_id, 0)
       }}
    end
  end

  # --- Private helpers ---

  defp valid_team?(state, team_id) do
    Enum.any?(state.teams, fn t -> t.id == team_id end)
  end

  defp valid_option?(state, selected_index) do
    question = current_question(state)
    question != nil and selected_index >= 0 and selected_index < length(question.options)
  end

  defp compute_round_scores(state) do
    # For each question in the round, check if each team's answer is correct.
    # 1 point per correct answer (0 otherwise).
    Enum.reduce(state.current_questions, %{}, fn question, acc ->
      question_answers = Map.get(state.answers, question.position, %{})

      Enum.reduce(question_answers, acc, fn {team_id, selected_index}, acc2 ->
        if selected_index == question.correct_index do
          Map.update(acc2, team_id, 1, &(&1 + 1))
        else
          acc2
        end
      end)
    end)
  end

  defp determine_winner(scores) when scores == %{}, do: nil

  defp determine_winner(scores) do
    max_score = scores |> Map.values() |> Enum.max()

    winners =
      scores
      |> Enum.filter(fn {_, score} -> score == max_score end)
      |> Enum.map(fn {team_id, _} -> team_id end)

    case winners do
      [single] -> single
      # tie — host picks next round
      _ -> nil
    end
  end
end
