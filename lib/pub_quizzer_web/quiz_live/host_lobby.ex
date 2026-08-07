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

  def handle_info({:team_connected, _team_id}, socket) do
    {:noreply, socket}
  end

  def handle_info({:team_disconnected, _team_id}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("reveal_round", _params, socket) do
    {:noreply, engine_call(socket, &Engine.reveal_round/1)}
  end

  def handle_event("reveal_next_answer", _params, socket) do
    case Engine.reveal_next_answer(socket.assigns.event.id) do
      {:ok, _state} ->
        {:noreply, push_event(socket, "scroll_to_bottom", %{})}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Fehler: #{reason}")}
    end
  end

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
    case Engine.next_question(socket.assigns.event.id) do
      {:ok, _state} ->
        {:noreply, socket}

      {:error, :end_of_round} ->
        {:noreply,
         socket
         |> put_flash(:info, "Runde beendet — klicke auf Auflösen, um die Punkte anzuzeigen.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Fehler: #{reason}")}
    end
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
    |> assign(:engine_state, state)
    |> assign_available_topics(state)
    |> assign(:standings, EngineState.standings_sorted(state))
    |> assign(:current_topic_name, EngineState.current_topic_name(state))
  end

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
