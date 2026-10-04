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
    standings_revealed: false,
    final_results_revealed: false,
    # answers: %{question_index => %{team_id => selected_index}}
    answers: %{},
    # Paper participation and collected sheets apply to the current round only.
    paper_team_ids: [],
    paper_submitted_team_ids: [],
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

  During the `:question` phase, teams see the current prompt and its options,
  but never `correct_index` or future questions. During reveal and after the
  quiz ends, team clients have no need for the question set at all.

  `team_id` is the viewing team's id — that team's own `selected_index` is
  preserved so its UI can render the "answered" state and highlight its pick
  after a reconnect. Every other team's selection is replaced with `nil`
  (keys preserved for `answered_teams/1`) so the live distribution can't be
  inferred from the LV state.
  """
  def strip_for_team(%__MODULE__{status: :question} = state, team_id) do
    slim_questions =
      Enum.map(state.current_questions, fn q ->
        if q.position == state.question_index do
          Map.drop(q, [:correct_index])
        else
          %{id: q.id, position: q.position, options: Enum.map(q.options, fn _ -> %{} end)}
        end
      end)

    %{state | current_questions: slim_questions, answers: redact_answers(state.answers, team_id)}
  end

  def strip_for_team(%__MODULE__{} = state, team_id) do
    %{state | current_questions: [], answers: redact_answers(state.answers, team_id)}
  end

  defp redact_answers(answers, team_id) when is_map(answers) do
    Map.new(answers, fn {qidx, picks} ->
      {qidx, Map.new(picks, fn {tid, selected} -> {tid, tid == team_id && selected} end)}
    end)
  end

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
    if is_nil(chooser_team_id) or valid_team?(state, chooser_team_id) do
      choose_available_topic(state, topic_id, chooser_team_id)
    else
      {:error, :invalid_chooser}
    end
  end

  def choose_topic(%__MODULE__{}, _topic_id, _chooser), do: {:error, :not_in_topic_selection}

  defp choose_available_topic(state, topic_id, chooser_team_id) do
    case Enum.find(available_topics(state), fn t -> t.id == topic_id end) do
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
              answers: %{},
              paper_team_ids: [],
              paper_submitted_team_ids: []
          }

          {:ok, new_state}
        end
    end
  end

  @doc """
  Submit or update an answer for the current question.
  Teams can change their answer until the host advances.
  """
  def submit_answer(%__MODULE__{status: :question} = state, team_id, selected_index) do
    cond do
      team_id in state.paper_team_ids ->
        {:error, :paper_mode}

      valid_team?(state, team_id) and valid_option?(state, selected_index) ->
        question_answers = Map.get(state.answers, state.question_index, %{})
        updated = Map.put(question_answers, team_id, selected_index)

        {:ok, %{state | answers: Map.put(state.answers, state.question_index, updated)}}

      true ->
        {:error, :invalid_submission}
    end
  end

  def submit_answer(%__MODULE__{}, _team_id, _selected_index),
    do: {:error, :not_in_question_phase}

  def set_paper_mode(%__MODULE__{status: :question} = state, team_id, enabled)
      when is_boolean(enabled) do
    if valid_team?(state, team_id) do
      ids =
        if enabled,
          do: Enum.uniq(state.paper_team_ids ++ [team_id]),
          else: List.delete(state.paper_team_ids, team_id)

      submitted =
        if enabled,
          do: state.paper_submitted_team_ids,
          else: List.delete(state.paper_submitted_team_ids, team_id)

      {:ok, %{state | paper_team_ids: ids, paper_submitted_team_ids: submitted}}
    else
      {:error, :invalid_team}
    end
  end

  def set_paper_mode(%__MODULE__{}, _team_id, _enabled), do: {:error, :not_in_question_phase}

  @doc "Records a complete paper sheet at the end of the round; nil preserves existing answers."
  def submit_paper_answers(state, team_id, picks, opts \\ [])

  def submit_paper_answers(%__MODULE__{status: :question} = state, team_id, picks, opts) do
    existing = paper_answers(state, team_id)

    cond do
      not valid_team?(state, team_id) ->
        {:error, :invalid_team}

      team_id not in state.paper_team_ids ->
        {:error, :not_in_paper_mode}

      state.question_index != length(state.current_questions) - 1 ->
        {:error, :round_not_complete}

      not valid_paper_picks?(state, picks) ->
        {:error, :invalid_submission}

      Keyword.has_key?(opts, :expected_answers) and opts[:expected_answers] != existing ->
        {:error, :answers_changed}

      not Keyword.get(opts, :replace_existing?, false) and
          Enum.any?(picks, fn {id, pick} ->
            pick != nil and existing[id] != nil and pick != existing[id]
          end) ->
        {:error, :overwrite_required}

      true ->
        answers =
          Enum.reduce(state.current_questions, state.answers, fn question, answers ->
            case picks[question.id] do
              nil ->
                answers

              pick ->
                Map.update(
                  answers,
                  question.position,
                  %{team_id => pick},
                  &Map.put(&1, team_id, pick)
                )
            end
          end)

        {:ok,
         %{
           state
           | answers: answers,
             paper_submitted_team_ids: Enum.uniq(state.paper_submitted_team_ids ++ [team_id])
         }}
    end
  end

  def submit_paper_answers(%__MODULE__{}, _team_id, _picks, _opts),
    do: {:error, :not_in_question_phase}

  def paper_answers(state, team_id) do
    Map.new(state.current_questions, fn q ->
      {q.id, Map.get(Map.get(state.answers, q.position, %{}), team_id)}
    end)
  end

  defp valid_paper_picks?(state, picks) when is_map(picks) do
    MapSet.new(Map.keys(picks)) == MapSet.new(state.current_questions, & &1.id) and
      Enum.all?(state.current_questions, fn q ->
        pick = picks[q.id]
        is_nil(pick) or (is_integer(pick) and pick >= 0 and pick < length(q.options))
      end)
  end

  defp valid_paper_picks?(_state, _picks), do: false

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
    if pending_paper_teams(state) == [] do
      score_round(state)
    else
      {:error, :paper_answers_pending}
    end
  end

  def reveal_round(%__MODULE__{}), do: {:error, :not_in_question_phase}

  defp score_round(state) do
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
        standings_revealed: false
    }

    {:ok, new_state}
  end

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
             current_round_id: nil,
             paper_team_ids: [],
             paper_submitted_team_ids: []
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
             current_round_id: nil,
             paper_team_ids: [],
             paper_submitted_team_ids: []
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

  def pending_digital_teams(state) do
    answered = answered_teams(state)
    Enum.reject(state.teams, &(&1.id in state.paper_team_ids or MapSet.member?(answered, &1.id)))
  end

  def pending_paper_teams(state) do
    Enum.filter(
      state.teams,
      &(&1.id in state.paper_team_ids and &1.id not in state.paper_submitted_team_ids)
    )
  end

  def standings_sorted(%__MODULE__{standings: standings, teams: teams}) do
    teams
    |> Enum.map(fn t -> {t.id, t.name, Map.get(standings, t.id, 0)} end)
    |> Enum.sort_by(fn {_, _, score} -> score end, :desc)
  end

  @doc """
  Live answer distribution for a single question — how many teams picked each
  option. Returns `%{option_index => count}` including zero-count options so
  the host UI can render full-width bars. Defaults to the current question.
  """
  def answer_distribution(%__MODULE__{} = state) do
    answer_distribution(state, state.question_index)
  end

  def answer_distribution(
        %__MODULE__{answers: answers, current_questions: questions},
        question_idx
      ) do
    case Enum.at(questions, question_idx) do
      nil ->
        %{}

      question ->
        option_count = length(question.options)
        question_answers = Map.get(answers, question_idx, %{})
        initial = Map.new(0..(option_count - 1), fn i -> {i, 0} end)

        Enum.reduce(question_answers, initial, fn {_team_id, selected}, acc ->
          Map.update(acc, selected, 1, &(&1 + 1))
        end)
    end
  end

  @doc """
  Standings with per-round deltas — `[{team_id, name, total_score, delta}]`
  sorted by total descending. The delta reflects points scored in the round
  that was just played (meaningful during `:round_reveal` and `:finished`,
  zero otherwise). `delta` is safe to render as a `+N` badge.
  """
  def standings_with_deltas(%__MODULE__{status: status} = state)
      when status in [:round_reveal, :finished] do
    round_scores = compute_round_scores(state)

    state.teams
    |> Enum.map(fn t ->
      total = Map.get(state.standings, t.id, 0)
      delta = Map.get(round_scores, t.id, 0)
      {t.id, t.name, total, delta}
    end)
    |> Enum.sort_by(fn {_, _, total, _} -> total end, :desc)
  end

  def standings_with_deltas(%__MODULE__{} = state) do
    state.teams
    |> Enum.map(fn t ->
      {t.id, t.name, Map.get(state.standings, t.id, 0), 0}
    end)
    |> Enum.sort_by(fn {_, _, total, _} -> total end, :desc)
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
    cond do
      valid_team?(state, team_id) ->
        {:ok, state}

      state.status != :lobby ->
        {:error, :quiz_started}

      true ->
        team = %{id: team_id, name: name, slot_index: slot_index}

        {:ok,
         %{
           state
           | teams: state.teams ++ [team],
             standings: Map.put(state.standings, team_id, 0)
         }}
    end
  end

  @doc "Removes a participating team and its answers, scores, and topic-choice priority."
  def remove_team(%__MODULE__{status: status} = state, team_id)
      when status in [:topic_selection, :question, :round_reveal] do
    cond do
      not valid_team?(state, team_id) ->
        {:error, :not_found}

      length(state.teams) <= 1 ->
        {:error, :last_team}

      true ->
        {:ok,
         %{
           state
           | teams: Enum.reject(state.teams, &(&1.id == team_id)),
             answers:
               Map.new(state.answers, fn {index, answers} ->
                 {index, Map.delete(answers, team_id)}
               end),
             standings: Map.delete(state.standings, team_id),
             paper_team_ids: List.delete(state.paper_team_ids, team_id),
             paper_submitted_team_ids: List.delete(state.paper_submitted_team_ids, team_id),
             current_chooser_team_id: clear_removed_team(state.current_chooser_team_id, team_id),
             current_winner_team_id: clear_removed_team(state.current_winner_team_id, team_id),
             completed_rounds:
               Enum.map(state.completed_rounds, fn round ->
                 %{round | winner_team_id: clear_removed_team(round.winner_team_id, team_id)}
               end)
         }}
    end
  end

  def remove_team(%__MODULE__{}, _team_id), do: {:error, :not_in_active_quiz}

  # --- Private helpers ---

  defp clear_removed_team(team_id, team_id), do: nil
  defp clear_removed_team(team_id, _removed_id), do: team_id

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
