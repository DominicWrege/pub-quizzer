defmodule PubQuizzer.Quiz.Engine do
  @moduledoc """
  GenServer wrapping EngineState. Handles persistence and PubSub broadcasting.

  One engine per active quiz event, started via DynamicSupervisor.
  """

  use GenServer

  import Ecto.Query

  alias PubQuizzer.Quiz.{EngineState, Round, Answer}
  alias PubQuizzer.Repo

  @registry PubQuizzer.Quiz.EngineRegistry
  @supervisor PubQuizzer.Quiz.EngineSupervisor
  @pubsub PubQuizzer.PubSub

  # --- Client API ---

  def topic(event_id), do: "quiz:event:#{event_id}"

  def start_link(event_id) do
    GenServer.start_link(__MODULE__, event_id, name: via_tuple(event_id))
  end

  def child_spec(event_id) do
    %{
      id: {__MODULE__, event_id},
      start: {__MODULE__, :start_link, [event_id]},
      restart: :transient
    }
  end

  def via_tuple(event_id) do
    {:via, Registry, {@registry, event_id}}
  end

  @doc """
  Start an engine for an event. Idempotent — if already running, returns :ignore.
  """
  def ensure_started(event_id) do
    case DynamicSupervisor.start_child(@supervisor, {__MODULE__, event_id}) do
      {:ok, pid} ->
        maybe_allow_sandbox(pid)
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      error ->
        error
    end
  end

  defp maybe_allow_sandbox(pid) do
    try do
      Ecto.Adapters.SQL.Sandbox.allow(PubQuizzer.Repo, self(), pid)
    rescue
      RuntimeError -> :ok
    end
  end

  @doc """
  Get the current state snapshot.
  """
  def get_state(event_id) do
    GenServer.call(via_tuple(event_id), :get_state)
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Register a newly joined team with the engine.
  """
  def register_team(event_id, team_id, name, slot_index) do
    GenServer.call(via_tuple(event_id), {:register_team, team_id, name, slot_index})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Start the quiz (lobby → topic_selection).
  """
  def start_quiz(event_id) do
    GenServer.call(via_tuple(event_id), :start_quiz)
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Choose a topic for the current round.
  """
  def choose_topic(event_id, topic_id, chooser_team_id \\ nil) do
    GenServer.call(via_tuple(event_id), {:choose_topic, topic_id, chooser_team_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Submit or update an answer for the current question.
  """
  def submit_answer(event_id, team_id, selected_index) do
    GenServer.call(via_tuple(event_id), {:submit_answer, team_id, selected_index})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Advance to the next question.
  """
  def next_question(event_id) do
    GenServer.call(via_tuple(event_id), :next_question)
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  End the current round and reveal scores.
  """
  def reveal_round(event_id) do
    GenServer.call(via_tuple(event_id), :reveal_round)
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Reveal the next answer during round reveal.
  """
  def reveal_next_answer(event_id) do
    GenServer.call(via_tuple(event_id), :reveal_next_answer)
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Reveal team standings to all devices.
  """
  def reveal_standings(event_id) do
    GenServer.call(via_tuple(event_id), :reveal_standings)
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Start the next round (or finish if no more rounds).
  """
  def next_round(event_id) do
    GenServer.call(via_tuple(event_id), :next_round)
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Finish the quiz early.
  """
  def finish_quiz(event_id) do
    GenServer.call(via_tuple(event_id), :finish_quiz)
  catch
    :exit, _ -> {:error, :not_found}
  end

  # --- Server callbacks ---

  @impl true
  def init(event_id) do
    # Don't load from DB here — the GenServer process may not have DB access yet.
    # State is loaded lazily on the first call.
    {:ok, %{event_id: event_id, engine_state: nil}}
  end

  defp ensure_loaded(%{engine_state: nil, event_id: event_id} = state) do
    engine_state = load_state_from_db(event_id)
    {:ok, %{state | engine_state: engine_state}}
  end

  defp ensure_loaded(%{engine_state: engine_state} = state) do
    {:ok, %{state | engine_state: engine_state}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:ok, state} = ensure_loaded(state)
    {:reply, {:ok, state.engine_state}, state}
  end

  def handle_call({:register_team, team_id, name, slot_index}, _from, state) do
    {:ok, state} = ensure_loaded(state)

    {:ok, new_es} = EngineState.register_team(state.engine_state, team_id, name, slot_index)
    broadcast(new_es)

    {:reply, {:ok, new_es}, %{state | engine_state: new_es}}
  end

  def handle_call(:start_quiz, _from, state) do
    {:ok, state} = ensure_loaded(state)

    case EngineState.start_quiz(state.engine_state) do
      {:ok, new_es} ->
        persist_event_status(new_es)
        broadcast(new_es)
        {:reply, {:ok, new_es}, %{state | engine_state: new_es}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:choose_topic, topic_id, chooser_team_id}, _from, state) do
    {:ok, state} = ensure_loaded(state)

    case EngineState.choose_topic(state.engine_state, topic_id, chooser_team_id) do
      {:ok, new_es} ->
        persist_round(new_es)
        persist_event_status(new_es)
        broadcast(new_es)
        {:reply, {:ok, new_es}, %{state | engine_state: new_es}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:submit_answer, team_id, selected_index}, _from, state) do
    {:ok, state} = ensure_loaded(state)

    case EngineState.submit_answer(state.engine_state, team_id, selected_index) do
      {:ok, new_es} ->
        persist_answer(new_es, team_id, selected_index)
        broadcast(new_es)
        {:reply, {:ok, new_es}, %{state | engine_state: new_es}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:next_question, _from, state) do
    {:ok, state} = ensure_loaded(state)

    case EngineState.next_question(state.engine_state) do
      {:ok, new_es} ->
        persist_event_status(new_es)
        broadcast(new_es)
        {:reply, {:ok, new_es}, %{state | engine_state: new_es}}

      {:error, :end_of_round} ->
        {:reply, {:error, :end_of_round}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:reveal_round, _from, state) do
    {:ok, state} = ensure_loaded(state)

    case EngineState.reveal_round(state.engine_state) do
      {:ok, new_es} ->
        persist_round_winner(new_es)
        persist_event_status(new_es)
        broadcast(new_es)
        {:reply, {:ok, new_es}, %{state | engine_state: new_es}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:reveal_next_answer, _from, state) do
    {:ok, state} = ensure_loaded(state)

    case EngineState.reveal_next_answer(state.engine_state) do
      {:ok, new_es} ->
        broadcast(new_es)
        {:reply, {:ok, new_es}, %{state | engine_state: new_es}}

      {:ok, new_es, :all_revealed} ->
        broadcast(new_es)
        {:reply, {:ok, new_es}, %{state | engine_state: new_es}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:reveal_standings, _from, state) do
    {:ok, state} = ensure_loaded(state)

    case EngineState.reveal_standings(state.engine_state) do
      {:ok, new_es} ->
        broadcast(new_es)
        {:reply, {:ok, new_es}, %{state | engine_state: new_es}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:next_round, _from, state) do
    {:ok, state} = ensure_loaded(state)

    case EngineState.next_round(state.engine_state) do
      {:ok, new_es} ->
        persist_event_status(new_es)
        broadcast(new_es)
        {:reply, {:ok, new_es}, %{state | engine_state: new_es}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:finish_quiz, _from, state) do
    {:ok, state} = ensure_loaded(state)

    case EngineState.finish_quiz(state.engine_state) do
      {:ok, new_es} ->
        persist_event_status(new_es)
        broadcast(new_es)
        {:reply, {:ok, new_es}, %{state | engine_state: new_es}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # --- Persistence helpers ---

  defp load_state_from_db(event_id) do
    alias PubQuizzer.Quiz

    event = Quiz.get_event_with_teams!(event_id)
    topics = Quiz.list_topic_names()

    case event.status do
      "lobby" ->
        EngineState.new(event, event.teams, topics, max_rounds: 7)

      status ->
        rebuild_state(event, topics, String.to_atom(status))
    end
  end

  defp rebuild_state(event, topics, status) do
    alias PubQuizzer.Quiz

    rounds = Quiz.list_rounds_for_event(event.id)

    teams =
      event.teams
      |> Enum.filter(& &1.claimed_at)
      |> Enum.map(&%{id: &1.id, name: &1.name, slot_index: &1.slot_index})

    available_topics = Enum.map(topics, &%{id: &1.id, name: &1.name})

    # In :question status, the last DB round is the in-progress one (no winner yet)
    # In other statuses, all DB rounds are completed
    {completed_rounds, current_round} =
      case status do
        :question -> {Enum.drop(rounds, -1), List.last(rounds)}
        :round_reveal -> {rounds, List.last(rounds)}
        _ -> {rounds, nil}
      end

    completed_summaries =
      Enum.map(completed_rounds, fn r ->
        %{round_number: r.round_number, topic_id: r.topic_id, winner_team_id: r.winner_team_id}
      end)

    # Compute standings from all completed rounds' answers
    raw_scores = compute_standings_from_answers(completed_rounds)
    standings = init_standings(teams, raw_scores)

    base = %EngineState{
      event_id: event.id,
      code: event.code,
      status: status,
      round_number: event.current_round,
      question_index: event.current_question_index,
      teams: teams,
      available_topics: available_topics,
      standings: standings,
      completed_rounds: completed_summaries,
      max_rounds: 7
    }

    case status do
      :topic_selection ->
        chooser =
          case List.last(completed_rounds) do
            nil -> nil
            round -> round.winner_team_id
          end

        %{base | current_chooser_team_id: chooser}

      :question ->
        round = current_round
        questions = load_questions_for_topic(round.topic_id)
        answers = load_answers_map(round.id, questions)

        %{
          base
          | current_topic_id: round.topic_id,
            current_questions: questions,
            current_chooser_team_id: round.chosen_by_team_id,
            answers: answers
        }

      :round_reveal ->
        round = current_round
        questions = load_questions_for_topic(round.topic_id)
        answers = load_answers_map(round.id, questions)

        %{
          base
          | current_topic_id: round.topic_id,
            current_questions: questions,
            current_chooser_team_id: round.chosen_by_team_id,
            current_winner_team_id: round.winner_team_id,
            answers: answers
        }

      :finished ->
        base
    end
  end

  defp compute_standings_from_answers(rounds) do
    alias PubQuizzer.Quiz

    # Load all answers for these rounds and compute scores
    rounds
    |> Enum.reduce(%{}, fn round, acc ->
      answers = Quiz.list_answers_for_round(round.id)

      Enum.reduce(answers, acc, fn answer, acc2 ->
        if answer.selected_index == answer.question.correct_index do
          Map.update(acc2, answer.team_id, 1, &(&1 + 1))
        else
          Map.put_new(acc2, answer.team_id, 0)
        end
      end)
    end)
  end

  defp init_standings(teams, scores) do
    base = Map.new(teams, fn t -> {t.id, 0} end)
    Map.merge(base, scores)
  end

  defp load_answers_map(round_id, questions) do
    alias PubQuizzer.Quiz

    answers = Quiz.list_answers_for_round(round_id)

    # Build %{question_position => %{team_id => selected_index}}
    question_id_to_position = Map.new(questions, fn q -> {q.id, q.position} end)

    Enum.reduce(answers, %{}, fn answer, acc ->
      position = Map.get(question_id_to_position, answer.question_id)

      if position do
        question_answers = Map.get(acc, position, %{})
        Map.put(acc, position, Map.put(question_answers, answer.team_id, answer.selected_index))
      else
        acc
      end
    end)
  end

  defp load_questions_for_topic(topic_id) do
    alias PubQuizzer.Quiz

    Quiz.list_questions_for_topic(topic_id)
    |> Enum.with_index()
    |> Enum.map(fn {q, idx} ->
      %{
        id: q.id,
        prompt: q.prompt,
        options: q.options,
        correct_index: q.correct_index,
        position: idx,
        image: q.image
      }
    end)
  end

  defp persist_event_status(state) do
    event = PubQuizzer.Repo.get(PubQuizzer.Quiz.QuizEvent, state.event_id)

    attrs = %{
      status: Atom.to_string(state.status),
      current_round: state.round_number,
      current_question_index: state.question_index
    }

    extra =
      cond do
        state.status == :topic_selection and event.started_at == nil ->
          %{started_at: DateTime.utc_now()}

        state.status == :finished and event.finished_at == nil ->
          %{finished_at: DateTime.utc_now()}

        true ->
          %{}
      end

    event
    |> Ecto.Changeset.cast(Map.merge(attrs, extra), [
      :status,
      :current_round,
      :current_question_index,
      :started_at,
      :finished_at
    ])
    |> Repo.update()
    |> case do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        require Logger
        Logger.error("Failed to persist event status: #{inspect(changeset.errors)}")
        :ok
    end
  end

  defp persist_round(state) do
    %Round{}
    |> Round.changeset(%{
      round_number: state.round_number,
      topic_id: state.current_topic_id,
      quiz_event_id: state.event_id,
      chosen_by_team_id: state.current_chooser_team_id
    })
    |> Repo.insert!()
  end

  defp persist_round_winner(state) do
    round =
      Repo.one(
        from r in Round,
          where: r.quiz_event_id == ^state.event_id and r.round_number == ^state.round_number
      )

    if round do
      round
      |> Round.changeset(%{winner_team_id: state.current_winner_team_id})
      |> Repo.update!()
    end
  end

  defp persist_answer(state, team_id, selected_index) do
    question = EngineState.current_question(state)

    if question do
      round =
        Repo.one(
          from r in Round,
            where: r.quiz_event_id == ^state.event_id and r.round_number == ^state.round_number
        )

      if round do
        %Answer{}
        |> Answer.changeset(%{
          selected_index: selected_index,
          question_id: question.id,
          round_id: round.id,
          team_id: team_id
        })
        |> Repo.insert(
          on_conflict: {:replace, [:selected_index]},
          conflict_target: [:round_id, :question_id, :team_id]
        )
      end
    end
  end

  # --- Broadcasting ---

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(@pubsub, topic(state.event_id), {:engine_state, state})
  end
end
