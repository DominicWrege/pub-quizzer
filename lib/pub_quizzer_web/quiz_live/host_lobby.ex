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
    event_id = socket.assigns.event.id

    case Engine.reveal_round(event_id) do
      {:ok, _state} ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Fehler: #{reason}")}
    end
  end

  def handle_event("reveal_next_answer", _params, socket) do
    event_id = socket.assigns.event.id

    case Engine.reveal_next_answer(event_id) do
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
    topic_id = String.to_integer(topic_id)
    event_id = socket.assigns.event.id

    case Engine.choose_topic(event_id, topic_id, nil) do
      {:ok, _state} ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Thema konnte nicht gewählt werden: #{reason}")}
    end
  end

  def handle_event("next_question", _params, socket) do
    event_id = socket.assigns.event.id

    case Engine.next_question(event_id) do
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
    event_id = socket.assigns.event.id

    case Engine.reveal_standings(event_id) do
      {:ok, _state} ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Fehler: #{reason}")}
    end
  end

  def handle_event("reveal_final_results", _params, socket) do
    case Engine.reveal_final_results(socket.assigns.event.id) do
      {:ok, _state} ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Fehler: #{reason}")}
    end
  end

  def handle_event("next_round", _params, socket) do
    event_id = socket.assigns.event.id

    case Engine.next_round(event_id) do
      {:ok, _state} ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Fehler: #{reason}")}
    end
  end

  def handle_event("refresh", _params, socket) do
    {:ok, _pid} = Engine.ensure_started(socket.assigns.event.id)

    case Engine.get_state(socket.assigns.event.id) do
      {:ok, state} ->
        {:noreply,
         socket
         |> assign(:engine_state, state)
         |> assign(:available_topics, EngineState.available_topics(state))
         |> assign(:standings, EngineState.standings_sorted(state))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Quiz-Engine nicht verfügbar.")}
    end
  end

  defp apply_engine_state(socket, state) do
    socket
    |> assign(:engine_state, state)
    |> assign(
      :available_topics,
      Quiz.filter_topics_with_questions(EngineState.available_topics(state))
    )
    |> assign(:standings, EngineState.standings_sorted(state))
    |> assign(:current_topic_name, EngineState.current_topic_name(state, state))
  end
end
