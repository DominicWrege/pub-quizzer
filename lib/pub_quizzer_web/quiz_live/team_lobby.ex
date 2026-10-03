defmodule PubQuizzerWeb.QuizLive.TeamLobby do
  use PubQuizzerWeb, :live_view

  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.{Engine, EngineState}

  @impl true
  def mount(%{"code" => code} = params, session, socket) do
    team_id = Map.get(session, "team_id")

    case load_event_and_team(code, team_id, params["team_code"]) do
      {:ok, event, team} ->
        {:ok, _engine_pid} = Engine.ensure_started(event.id)

        if connected?(socket) do
          Phoenix.PubSub.subscribe(PubQuizzer.PubSub, Engine.topic(event.id))

          # Track presence so disconnect debounce works on flaky 4G.
          # Registry auto-removes entry when this LV process dies.
          Registry.register(PubQuizzer.TeamPresence, team.id, nil)

          Phoenix.PubSub.broadcast(
            PubQuizzer.PubSub,
            "quiz:event:#{event.id}",
            {:team_connected, team.id}
          )
        end

        case Engine.get_state(event.id) do
          {:ok, state} ->
            team_state = EngineState.strip_for_team(state, team.id)

            socket =
              socket
              |> assign(:event, event)
              |> assign(:team, team)
              |> assign(:engine_state, team_state)
              |> assign(:page_title, "Quiz — #{code}")
              |> assign(:standings, [])
              |> assign(:available_topics, [])
              |> assign_standings(state)
              |> assign_available_topics(state)
              |> assign(:current_topic_name, EngineState.current_topic_name(state))

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

      {:error, :missing_session} ->
        {:ok, redirect(socket, to: ~p"/quiz/#{code}/rejoin")}

      {:error, reason} ->
        {:ok,
         socket
         |> put_flash(:error, reason)
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_info({:engine_state, state}, socket) do
    team_state = EngineState.strip_for_team(state, socket.assigns.team.id)

    {:noreply,
     socket
     |> assign(:engine_state, team_state)
     |> assign_standings(state)
     |> assign_available_topics(state)
     |> assign(:current_topic_name, EngineState.current_topic_name(state))}
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
  def handle_event(
        "select_answer",
        %{"index" => index_str, "question_id" => question_id_str},
        socket
      ) do
    with {index, ""} <- Integer.parse(index_str),
         {question_id, ""} <- Integer.parse(question_id_str) do
      event_id = socket.assigns.event.id
      team_id = socket.assigns.team.id

      case Engine.submit_answer(event_id, team_id, index, question_id) do
        {:ok, state} ->
          {:noreply, assign(socket, :engine_state, EngineState.strip_for_team(state, team_id))}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, "Antwort konnte nicht abgegeben werden: #{reason}")}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("choose_topic", %{"topic_id" => topic_id}, socket) do
    with {topic_id, ""} <- Integer.parse(topic_id) do
      event_id = socket.assigns.event.id
      team_id = socket.assigns.team.id

      case Engine.choose_topic(event_id, topic_id, team_id) do
        {:ok, _state} ->
          {:noreply, socket}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Thema konnte nicht gewählt werden: #{reason}")}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    event_id = socket.assigns.event.id
    team_id = socket.assigns.team.id

    # Debounce the disconnect broadcast: on flaky 4G the WS drops briefly and
    # the LV remounts within seconds. Wait 3s, then check presence — if the
    # team is still gone, broadcast; otherwise they reconnected, do nothing.
    # Run under the TaskSupervisor so the process is supervised (a bare spawn
    # here would be unlinked and unsupervised) and survives the LV's death.
    Task.Supervisor.start_child(PubQuizzer.TaskSupervisor, fn ->
      Process.sleep(3_000)

      if Registry.lookup(PubQuizzer.TeamPresence, team_id) == [] do
        Phoenix.PubSub.broadcast(
          PubQuizzer.PubSub,
          "quiz:event:#{event_id}",
          {:team_disconnected, team_id}
        )
      end
    end)

    :ok
  end

  defp load_event_and_team(code, team_id, team_code) do
    case Quiz.get_event_by_code(code) do
      nil ->
        {:error, "Quiz nicht gefunden."}

      event ->
        team =
          Enum.find(event.teams, fn team ->
            identity_matches? =
              if team_code, do: team.link_code == team_code, else: team.id == team_id

            identity_matches? && team.claimed_at
          end)

        cond do
          team ->
            {:ok, event, team}

          is_nil(team_code) and is_nil(team_id) ->
            {:error, :missing_session}

          true ->
            {:error, "Du bist nicht Teil dieses Quiz."}
        end
    end
  end

  # Only compute standings when teams need them (reveal phases).
  defp assign_standings(socket, state) do
    if state.status in [:round_reveal, :finished] do
      assign(socket, :standings, EngineState.standings_sorted(state))
    else
      socket
    end
  end

  # Only hit the DB for available topics when teams need them (topic selection).
  defp assign_available_topics(socket, state) do
    if state.status == :topic_selection do
      assign(
        socket,
        :available_topics,
        Quiz.filter_topics_with_questions(EngineState.available_topics(state))
      )
    else
      socket
    end
  end
end
