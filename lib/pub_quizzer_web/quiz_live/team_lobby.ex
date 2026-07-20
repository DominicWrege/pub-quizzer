defmodule PubQuizzerWeb.QuizLive.TeamLobby do
  use PubQuizzerWeb, :live_view

  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.{Engine, EngineState}
  alias PubQuizzer.OptionShuffle

  @impl true
  def mount(%{"code" => code}, session, socket) do
    team_id = Map.get(session, "team_id")

    case load_event_and_team(code, team_id) do
      {:ok, event, team} ->
        {:ok, _engine_pid} = Engine.ensure_started(event.id)

        if connected?(socket) do
          Phoenix.PubSub.subscribe(PubQuizzer.PubSub, Engine.topic(event.id))

          Phoenix.PubSub.broadcast(
            PubQuizzer.PubSub,
            "quiz:event:#{event.id}",
            {:team_connected, team.id}
          )
        end

        case Engine.get_state(event.id) do
          {:ok, state} ->
            {shuffled_options, shuffle_map} = compute_shuffle(state, team)

            socket =
              socket
              |> assign(:event, event)
              |> assign(:team, team)
              |> assign(:engine_state, state)
              |> assign(:page_title, "Quiz — #{code}")
              |> assign(:standings, EngineState.standings_sorted(state))
              |> assign(
                :available_topics,
                Quiz.filter_topics_with_questions(EngineState.available_topics(state))
              )
              |> assign(:current_topic_name, EngineState.current_topic_name(state, state))
              |> assign(:shuffle_map, shuffle_map)
              |> assign(:shuffled_options, shuffled_options)
              |> assign(:selected_index, nil)

            {:ok, socket}

          {:error, :not_found} ->
            {:ok,
             socket
             |> put_flash(
               :error,
               "Quiz-Engine konnte nicht geladen werden. Bitte später erneut versuchen."
             )
             |> push_navigate(to: ~p"/")}
        end

      {:error, reason} ->
        {:ok,
         socket
         |> put_flash(:error, reason)
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_info({:engine_state, state}, socket) do
    current_q = EngineState.current_question(state)
    prev_q = EngineState.current_question(socket.assigns.engine_state)

    {shuffled_options, shuffle_map} = compute_shuffle(state, socket.assigns.team)

    selected_index =
      cond do
        state.status != :question ->
          nil

        current_q == nil ->
          nil

        prev_q != nil and current_q.id == prev_q.id ->
          socket.assigns.selected_index

        true ->
          nil
      end

    {:noreply,
     socket
     |> assign(:engine_state, state)
     |> assign(:standings, EngineState.standings_sorted(state))
     |> assign(
       :available_topics,
       Quiz.filter_topics_with_questions(EngineState.available_topics(state))
     )
     |> assign(:current_topic_name, EngineState.current_topic_name(state, state))
     |> assign(:shuffle_map, shuffle_map)
     |> assign(:shuffled_options, shuffled_options)
     |> assign(:selected_index, selected_index)}
  end

  def handle_info({:team_connected, _team_id}, socket) do
    {:noreply, socket}
  end

  def handle_info({:team_disconnected, _team_id}, socket) do
    {:noreply, socket}
  end

  def handle_info({:kick_team, team_id}, socket) do
    if team_id == socket.assigns.team.id do
      {:noreply,
       socket
       |> put_flash(:info, "Du wurdest vom Moderator aus dem Team entfernt.")
       |> push_navigate(to: ~p"/")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:team_update, _event_id}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_answer", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    original_index = OptionShuffle.to_original(socket.assigns.shuffle_map, index)
    event_id = socket.assigns.event.id
    team_id = socket.assigns.team.id

    case Engine.submit_answer(event_id, team_id, original_index) do
      {:ok, _state} ->
        {:noreply, assign(socket, :selected_index, index)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Antwort konnte nicht abgegeben werden: #{reason}")}
    end
  end

  def handle_event("choose_topic", %{"topic_id" => topic_id}, socket) do
    topic_id = String.to_integer(topic_id)
    event_id = socket.assigns.event.id
    team_id = socket.assigns.team.id

    case Engine.choose_topic(event_id, topic_id, team_id) do
      {:ok, _state} ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Thema konnte nicht gewählt werden: #{reason}")}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    event_id = socket.assigns.event.id
    team_id = socket.assigns.team.id

    Phoenix.PubSub.broadcast(
      PubQuizzer.PubSub,
      "quiz:event:#{event_id}",
      {:team_disconnected, team_id}
    )
  end

  defp load_event_and_team(code, team_id) do
    case Quiz.get_event_by_code(code) do
      nil ->
        {:error, "Quiz nicht gefunden."}

      event ->
        if team_id && Quiz.team_belongs_to_event?(team_id, event.id) do
          team = Quiz.get_team!(team_id)
          {:ok, event, team}
        else
          {:error, "Du bist nicht Teil dieses Quiz."}
        end
    end
  end

  defp compute_shuffle(state, team) do
    question = EngineState.current_question(state)

    if question do
      OptionShuffle.shuffle(
        question.options,
        team.id,
        question.id,
        state.round_number
      )
    else
      {[], %{}}
    end
  end
end
