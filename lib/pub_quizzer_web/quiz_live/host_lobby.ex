defmodule PubQuizzerWeb.QuizLive.HostLobby do
  use PubQuizzerWeb, :live_view

  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.{Engine, EngineState}

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    case Quiz.get_event_by_code(code) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Quiz nicht gefunden.")
         |> push_navigate(to: ~p"/admin/events")}

      event ->
        {:ok, _engine_pid} = Engine.ensure_started(event.id)

        if connected?(socket) do
          Phoenix.PubSub.subscribe(PubQuizzer.PubSub, Engine.topic(event.id))
        end

        case Engine.get_state(event.id) do
          {:ok, state} ->
            state =
              if state.status == :lobby do
                {:ok, new_state} = Engine.start_quiz(event.id)
                new_state
              else
                state
              end

            socket =
              socket
              |> assign(:connected_team_ids, connected_team_ids(state))
              |> apply_engine_state(state)
              |> assign(:event, event)
              |> assign(:page_title, "Moderator — #{code}")
              |> assign(:confirm_action, nil)

            {:ok, socket}

          {:error, :not_found} ->
            {:ok,
             socket
             |> put_flash(:error, "Quiz-Engine konnte nicht geladen werden.")
             |> push_navigate(to: ~p"/admin/events")}
        end
    end
  end

  @impl true
  def handle_info({:engine_state, state}, socket) do
    {:noreply, apply_engine_state(socket, state)}
  end

  def handle_info({:team_update, _event_id}, socket) do
    event = Quiz.get_event_with_teams!(socket.assigns.event.id)
    {:noreply, assign(socket, :event, event)}
  end

  def handle_info({:team_connected, team_id}, socket) do
    {:noreply,
     socket
     |> update(:connected_team_ids, &MapSet.put(&1, team_id))
     |> stream(:teams, socket.assigns.engine_state.teams, reset: true)}
  end

  def handle_info({:team_disconnected, team_id}, socket) do
    {:noreply,
     socket
     |> update(:connected_team_ids, &MapSet.delete(&1, team_id))
     |> stream(:teams, socket.assigns.engine_state.teams, reset: true)}
  end

  def handle_info({:kick_team, _team_id}, socket), do: {:noreply, socket}

  @impl true
  def handle_event("ask_finish_quiz", _params, socket) do
    {:noreply, assign(socket, :confirm_action, :finish_quiz)}
  end

  def handle_event("confirm_finish_quiz", _params, socket) do
    event_id = socket.assigns.event.id
    Engine.finish_quiz(event_id)
    {:noreply, assign(socket, :confirm_action, nil)}
  end

  def handle_event("cancel_confirm", _params, socket) do
    {:noreply, assign(socket, :confirm_action, nil)}
  end

  def handle_event("ask_remove_team", %{"team_id" => team_id}, socket) do
    with {id, ""} <- Integer.parse(team_id),
         team when not is_nil(team) <-
           Enum.find(socket.assigns.engine_state.teams, &(&1.id == id)),
         true <- socket.assigns.engine_state.status != :finished do
      {:noreply, assign(socket, :confirm_action, {:remove_team, team})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("confirm_remove_team", _params, socket) do
    case socket.assigns.confirm_action do
      {:remove_team, team} ->
        socket = assign(socket, :confirm_action, nil)

        case Engine.remove_team(socket.assigns.event.id, team.id) do
          {:ok, state} ->
            {:noreply, apply_engine_state(socket, state)}

          {:error, :last_team} ->
            {:noreply,
             put_flash(socket, :error, "Mindestens ein teilnehmendes Team muss bleiben.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Team konnte nicht entfernt werden.")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("choose_topic", %{"topic_id" => topic_id}, socket) do
    with {topic_id, ""} <- Integer.parse(topic_id) do
      case Engine.choose_topic(socket.assigns.event.id, topic_id, nil) do
        {:ok, _state} ->
          {:noreply, socket}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Thema konnte nicht gewählt werden: #{reason}")}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("next_question", _params, socket) do
    case Engine.get_state(socket.assigns.event.id) do
      {:ok, %{status: :question} = state} ->
        socket = apply_engine_state(socket, state)

        if MapSet.size(EngineState.answered_teams(state)) == length(state.teams) do
          {:noreply, advance_question(socket)}
        else
          {:noreply, assign(socket, :confirm_action, {:next_question, question_key(state)})}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("confirm_next_question", _params, socket) do
    with {:next_question, key} <- socket.assigns.confirm_action,
         {:ok, %{status: :question} = state} <- Engine.get_state(socket.assigns.event.id),
         true <- question_key(state) == key do
      socket = socket |> assign(:confirm_action, nil) |> apply_engine_state(state)
      {:noreply, advance_question(socket)}
    else
      _ -> {:noreply, assign(socket, :confirm_action, nil)}
    end
  end

  def handle_event("toggle_pending_teams", _params, socket) do
    {:noreply, update(socket, :pending_teams_visible?, &(!&1))}
  end

  def handle_event("show_standings", _params, socket) do
    {:noreply, engine_call(socket, &Engine.reveal_standings/1)}
  end

  def handle_event("reveal_final_results", _params, socket) do
    {:noreply, engine_call(socket, &Engine.reveal_final_results/1)}
  end

  def handle_event("next_round", _params, socket) do
    {:noreply, engine_call(socket, &Engine.next_round/1)}
  end

  def handle_event("refresh", _params, socket) do
    {:ok, _pid} = Engine.ensure_started(socket.assigns.event.id)

    case Engine.get_state(socket.assigns.event.id) do
      {:ok, state} ->
        {:noreply, apply_engine_state(socket, state)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Quiz-Engine nicht verfügbar.")}
    end
  end

  defp apply_engine_state(socket, state) do
    socket
    |> sync_question_controls(state)
    |> assign(:engine_state, state)
    |> assign(:answered_team_ids, EngineState.answered_teams(state))
    |> stream(:teams, state.teams, reset: true)
    |> assign_available_topics(state)
    |> assign(:standings, EngineState.standings_sorted(state))
    |> assign(:current_topic_name, EngineState.current_topic_name(state))
    |> assign(:answer_distribution, EngineState.answer_distribution(state))
    |> assign(:round_distributions, round_distributions(state))
    |> assign(:standings_with_deltas, EngineState.standings_with_deltas(state))
  end

  defp advance_question(socket) do
    event_id = socket.assigns.event.id

    case Engine.next_question(event_id) do
      {:ok, state} ->
        apply_engine_state(socket, state)

      {:error, :end_of_round} ->
        case Engine.reveal_round(event_id) do
          {:ok, state} -> apply_engine_state(socket, state)
          {:error, reason} -> put_flash(socket, :error, "Fehler: #{reason}")
        end

      {:error, reason} ->
        put_flash(socket, :error, "Fehler: #{reason}")
    end
  end

  defp question_key(%{status: :question} = state),
    do: {state.current_round_id, state.question_index}

  defp question_key(_), do: nil

  defp sync_question_controls(socket, state) do
    key = question_key(state)
    same_question? = key != nil and key == question_key(socket.assigns[:engine_state])

    socket =
      assign(
        socket,
        :pending_teams_visible?,
        same_question? and socket.assigns[:pending_teams_visible?] == true
      )

    case socket.assigns[:confirm_action] do
      {:next_question, ^key} -> socket
      {:next_question, _old_key} -> assign(socket, :confirm_action, nil)
      _ -> socket
    end
  end

  defp connected_team_ids(state) do
    state.teams
    |> Enum.filter(&(Registry.lookup(PubQuizzer.TeamPresence, &1.id) != []))
    |> MapSet.new(& &1.id)
  end

  # Per-question answer distributions for the round that was just played. Only
  # meaningful during :round_reveal (the round's answers are still in state);
  # returns [] elsewhere so the template can iterate safely.
  defp round_distributions(%{status: :round_reveal, current_questions: questions} = state) do
    Enum.map(questions, fn q -> {q, EngineState.answer_distribution(state, q.position)} end)
  end

  defp round_distributions(_state), do: []

  # Available topics only change during topic selection, so skip the DB query
  # (filter_topics_with_questions) in every other phase. The engine broadcasts
  # on every answer submission, and re-running that query per broadcast is wasteful.
  defp assign_available_topics(socket, %{status: :topic_selection} = state) do
    assign(
      socket,
      :available_topics,
      Quiz.filter_topics_with_questions(EngineState.available_topics(state))
    )
  end

  defp assign_available_topics(socket, _state), do: socket

  # Runs an engine call on the current event and flashes any error. Used by the
  # host event handlers that only need to fire-and-forget a transition.
  defp engine_call(socket, fun) do
    case fun.(socket.assigns.event.id) do
      {:ok, _state} ->
        socket

      {:error, reason} ->
        put_flash(socket, :error, "Fehler: #{reason}")
    end
  end
end
