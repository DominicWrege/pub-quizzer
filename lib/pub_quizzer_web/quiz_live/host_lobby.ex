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

        cond do
          state.question_index == length(state.current_questions) - 1 and
              EngineState.pending_paper_teams(state) != [] ->
            [team | _] = EngineState.pending_paper_teams(state)
            {:noreply, open_paper_entry(socket, state, team.id)}

          EngineState.pending_digital_teams(state) == [] ->
            {:noreply, advance_question(socket)}

          true ->
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

  def handle_event(
        "set_paper_mode",
        %{"team_id" => team_id, "round_id" => round_id, "enabled" => enabled},
        socket
      ) do
    with {team_id, ""} <- Integer.parse(team_id),
         {round_id, ""} <- Integer.parse(round_id),
         true <- enabled in ["true", "false"],
         {:ok, state} <-
           Engine.set_paper_mode(socket.assigns.event.id, round_id, team_id, enabled == "true") do
      {:noreply, apply_engine_state(socket, state)}
    else
      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Papiermodus konnte nicht geändert werden. Bitte aktualisieren."
         )}
    end
  end

  def handle_event("open_paper_answers", %{"team_id" => team_id}, socket) do
    with {team_id, ""} <- Integer.parse(team_id),
         {:ok, state} <- Engine.get_state(socket.assigns.event.id) do
      {:noreply, open_paper_entry(apply_engine_state(socket, state), state, team_id)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("close_paper_answers", _params, socket) do
    {:noreply, assign(socket, :paper_entry, nil)}
  end

  def handle_event("pick_paper_answer", %{"question_id" => id, "choice" => value}, socket) do
    case socket.assigns.paper_entry do
      %{picks: picks} = entry when is_map_key(picks, id) ->
        {:noreply, put_paper_draft(socket, entry, Map.put(picks, id, value))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("save_paper_answers", %{"paper" => picks}, socket) do
    case socket.assigns.paper_entry do
      nil -> {:noreply, socket}
      entry -> {:noreply, socket |> put_paper_draft(entry, picks) |> save_paper_entry(false)}
    end
  end

  def handle_event("confirm_paper_overwrite", _params, socket) do
    case socket.assigns.paper_entry do
      %{overwrite?: true} -> {:noreply, save_paper_entry(socket, true)}
      _ -> {:noreply, socket}
    end
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
    |> assign_new(:paper_entry, fn -> nil end)
    |> sync_paper_entry(state)
    |> sync_question_controls(state)
    |> assign(:engine_state, state)
    |> assign(:answered_team_ids, EngineState.answered_teams(state))
    |> assign(:pending_digital_teams, EngineState.pending_digital_teams(state))
    |> assign(:digital_teams, Enum.reject(state.teams, &(&1.id in state.paper_team_ids)))
    |> assign(:paper_teams, Enum.filter(state.teams, &(&1.id in state.paper_team_ids)))
    |> assign(:pending_paper_teams, EngineState.pending_paper_teams(state))
    |> stream(:teams, state.teams, reset: true)
    |> assign_available_topics(state)
    |> assign(:standings, EngineState.standings_sorted(state))
    |> assign(:current_topic_name, EngineState.current_topic_name(state))
    |> assign(:answer_distribution, EngineState.answer_distribution(state))
    |> assign(:round_distributions, round_distributions(state))
    |> assign(:standings_with_deltas, EngineState.standings_with_deltas(state))
  end

  defp sync_paper_entry(socket, state) do
    case socket.assigns.paper_entry do
      %{round_id: round_id, team: team} ->
        if state.status == :question and state.current_round_id == round_id and
             team.id in state.paper_team_ids do
          socket
        else
          assign(socket, :paper_entry, nil)
        end

      _ ->
        socket
    end
  end

  defp open_paper_entry(socket, state, team_id) do
    team = Enum.find(state.teams, &(&1.id == team_id))

    if team && state.status == :question && team_id in state.paper_team_ids &&
         state.question_index == length(state.current_questions) - 1 do
      original = EngineState.paper_answers(state, team_id)
      blank = if team_id in state.paper_submitted_team_ids, do: "-", else: "unselected"

      picks =
        Map.new(original, fn {id, value} ->
          {to_string(id), if(is_nil(value), do: blank, else: to_string(value))}
        end)

      sources =
        state.current_round_id
        |> Quiz.list_answers_for_round()
        |> Enum.filter(&(&1.team_id == team_id))
        |> Map.new(&{&1.question_id, &1.source})

      entry = %{
        round_id: state.current_round_id,
        team: team,
        original: original,
        picks: picks,
        sources: sources,
        overwrite?: false,
        error: nil
      }

      socket |> assign(:confirm_action, nil) |> put_paper_draft(entry, picks)
    else
      socket
    end
  end

  defp put_paper_draft(socket, entry, picks) do
    socket
    |> assign(:paper_entry, %{entry | picks: picks, overwrite?: false, error: nil})
    |> assign(:paper_form, to_form(picks, as: :paper))
  end

  defp save_paper_entry(socket, replace?) do
    entry = socket.assigns.paper_entry

    with {:ok, picks} <- parse_paper_picks(entry.picks),
         {:ok, state} <-
           Engine.submit_paper_answers(
             socket.assigns.event.id,
             entry.round_id,
             entry.team.id,
             picks,
             socket.assigns.current_scope.user.id,
             replace_existing?: replace?,
             expected_answers: entry.original
           ) do
      socket
      |> assign(:paper_entry, nil)
      |> apply_engine_state(state)
    else
      {:error, :overwrite_required} ->
        assign(socket, :paper_entry, %{entry | overwrite?: true})

      {:error, reason} ->
        assign(socket, :paper_entry, %{entry | error: paper_error(reason), overwrite?: false})
    end
  end

  defp parse_paper_picks(picks) when is_map(picks) do
    Enum.reduce_while(picks, {:ok, %{}}, fn {id, value}, {:ok, acc} ->
      with true <- is_binary(id) and is_binary(value),
           {id, ""} <- Integer.parse(id),
           {:ok, selected} <- parse_paper_pick(value) do
        {:cont, {:ok, Map.put(acc, id, selected)}}
      else
        _ -> {:halt, {:error, :invalid_submission}}
      end
    end)
  end

  defp parse_paper_picks(_), do: {:error, :invalid_submission}
  defp parse_paper_pick("-"), do: {:ok, nil}

  defp parse_paper_pick(value) do
    case Integer.parse(value) do
      {index, ""} when index in 0..3 -> {:ok, index}
      _ -> {:error, :invalid_submission}
    end
  end

  defp paper_error(:answers_changed),
    do: "Die Antworten wurden inzwischen geändert. Bitte schließen und erneut öffnen."

  defp paper_error(:invalid_submission),
    do: "Bitte für jede Frage eine Antwort oder ‚Keine Antwort‘ auswählen."

  defp paper_error(:unauthorized), do: "Keine Berechtigung. Bitte erneut anmelden."
  defp paper_error(_), do: "Diese Runde kann nicht mehr bearbeitet werden. Bitte aktualisieren."

  defp advance_question(socket) do
    event_id = socket.assigns.event.id

    case Engine.next_question(event_id) do
      {:ok, state} ->
        apply_engine_state(socket, state)

      {:error, :end_of_round} ->
        case Engine.reveal_round(event_id) do
          {:ok, state} ->
            apply_engine_state(socket, state)

          {:error, :paper_answers_pending} ->
            case Engine.get_state(event_id) do
              {:ok, state} ->
                socket = apply_engine_state(socket, state)

                case EngineState.pending_paper_teams(state) do
                  [team | _] -> open_paper_entry(socket, state, team.id)
                  [] -> socket
                end

              _ ->
                put_flash(socket, :error, "Quiz-Engine nicht verfügbar.")
            end

          {:error, reason} ->
            put_flash(socket, :error, "Fehler: #{reason}")
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
