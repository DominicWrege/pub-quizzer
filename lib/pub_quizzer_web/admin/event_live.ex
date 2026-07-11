defmodule PubQuizzerWeb.Admin.EventLive do
  use PubQuizzerWeb, :live_view

  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.{Engine, Team}
  alias PubQuizzer.Repo

  embed_templates "event_live/*"

  @impl true
  def render(assigns) do
    case assigns.live_action do
      :index -> index(assigns)
      :new -> new(assigns)
      :show -> event_show(assigns)
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:delete_event_id, nil) |> assign(:confirm_action, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    events = Quiz.list_events()

    socket
    |> assign(:page_title, "Events")
    |> assign(:events, events)
    |> assign(:search_query, "")
    |> assign(:filtered_events, events)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "Neues Quiz")
    |> assign(:form, to_form(%{"team_count" => "6"}))
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    event = Quiz.get_event_with_teams!(id)
    join_url = PubQuizzerWeb.Endpoint.url() <> ~p"/quiz/join/#{event.code}"
    qr_svg = EQRCode.encode(join_url) |> EQRCode.svg(color: "#1e40af", background: "#ffffff")

    claimed_ids =
      event.teams
      |> Enum.filter(& &1.claimed_at)
      |> Enum.map(& &1.id)
      |> MapSet.new()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(PubQuizzer.PubSub, "quiz:event:#{event.id}")
    end

    socket
    |> assign(:page_title, "Event #{event.code}")
    |> assign(:event, event)
    |> assign(:join_url, join_url)
    |> assign(:qr_svg, qr_svg)
    |> assign(:connected_team_ids, claimed_ids)
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    events = socket.assigns.events
    query = String.trim(query)

    filtered =
      if query == "" do
        events
      else
        Enum.filter(events, fn e ->
          String.contains?(String.downcase(e.code), String.downcase(query)) or
            (e.name && String.contains?(String.downcase(e.name), String.downcase(query)))
        end)
      end

    {:noreply, assign(socket, search_query: query, filtered_events: filtered)}
  end

  def handle_event("save", %{"team_count" => team_count} = params, socket) do
    team_count = String.to_integer(team_count)
    name = Map.get(params, "name", "")

    case Quiz.create_event(%{team_count: team_count, name: name}) do
      {:ok, event} ->
        {:noreply,
         socket
         |> put_flash(:info, "Event erstellt mit Code #{event.code}.")
         |> push_navigate(to: ~p"/admin/events/#{event.id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Event konnte nicht erstellt werden.")}
    end
  end

  def handle_event("rename_team", %{"team_id" => team_id, "name" => name}, socket) do
    team = Quiz.get_team!(team_id)

    case Quiz.update_team_name(team, name) do
      {:ok, _team} ->
        event = Quiz.get_event_with_teams!(socket.assigns.event.id)
        {:noreply, assign(socket, :event, event)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Team konnte nicht umbenannt werden.")}
    end
  end

  def handle_event("add_slot", _params, socket) do
    {:ok, event, _team} = Quiz.add_team_slot(socket.assigns.event)
    {:noreply, assign(socket, :event, event)}
  end

  def handle_event("remove_slot", _params, socket) do
    case Quiz.remove_team_slot(socket.assigns.event) do
      {:ok, event} ->
        {:noreply, assign(socket, :event, event)}

      {:error, :team_claimed} ->
        {:noreply, put_flash(socket, :error, "Belegter Team-Slot kann nicht entfernt werden.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Team-Slot konnte nicht entfernt werden.")}
    end
  end

  def handle_event("remove_team", %{"team_id" => team_id}, socket) do
    event_id = socket.assigns.event.id

    _team = Repo.get!(Team, String.to_integer(team_id)) |> Repo.delete!()

    Phoenix.PubSub.broadcast(
      PubQuizzer.PubSub,
      "quiz:event:#{event_id}",
      {:team_update, event_id}
    )

    event = Quiz.get_event_with_teams!(event_id)

    claimed_ids =
      event.teams
      |> Enum.filter(& &1.claimed_at)
      |> Enum.map(& &1.id)
      |> MapSet.new()

    {:noreply, socket |> assign(:event, event) |> assign(:connected_team_ids, claimed_ids)}
  end

  # Show page confirmations
  def handle_event("ask_delete_event", _params, socket) do
    {:noreply, assign(socket, :confirm_action, :delete)}
  end

  def handle_event("do_delete_event", _params, socket) do
    event = socket.assigns.event

    case Quiz.delete_event(event) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:confirm_action, nil)
         |> put_flash(:info, "Event gelöscht.")
         |> push_navigate(to: ~p"/admin/events")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Event konnte nicht gelöscht werden.")}
    end
  end

  def handle_event("ask_start", _params, socket) do
    {:noreply, assign(socket, :confirm_action, :start)}
  end

  def handle_event("do_start", _params, socket) do
    event = socket.assigns.event

    case Quiz.start_event(event) do
      {:ok, _event} ->
        {:ok, _pid} = Engine.ensure_started(event.id)
        code = event.code
        {:noreply, redirect(socket, to: ~p"/quiz/#{code}/host")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Event konnte nicht gestartet werden.")}
    end
  end

  def handle_event("cancel_action", _params, socket) do
    {:noreply, assign(socket, :confirm_action, nil)}
  end

  # Index page delete confirmation
  def handle_event("ask_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :delete_event_id, String.to_integer(id))}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :delete_event_id, nil)}
  end

  def handle_event("confirm_delete", _params, socket) do
    event = Quiz.get_event!(socket.assigns.delete_event_id)

    case Quiz.delete_event(event) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:delete_event_id, nil)
         |> put_flash(:info, "Event gelöscht.")
         |> push_navigate(to: ~p"/admin/events")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Event konnte nicht gelöscht werden.")}
    end
  end

  @impl true
  def handle_info({:team_update, _event_id}, socket) do
    event = Quiz.get_event_with_teams!(socket.assigns.event.id)

    claimed_ids =
      event.teams
      |> Enum.filter(& &1.claimed_at)
      |> Enum.map(& &1.id)
      |> MapSet.new()

    connected_ids =
      MapSet.new(socket.assigns.connected_team_ids)
      |> MapSet.intersection(claimed_ids)

    {:noreply,
     socket
     |> assign(:event, event)
     |> assign(:connected_team_ids, connected_ids)}
  end

  def handle_info({:team_connected, team_id}, socket) do
    {:noreply, update(socket, :connected_team_ids, &MapSet.put(&1, team_id))}
  end

  def handle_info({:team_disconnected, team_id}, socket) do
    {:noreply, update(socket, :connected_team_ids, &MapSet.delete(&1, team_id))}
  end

  def status_label("lobby"), do: "Bereit"
  def status_label("topic_selection"), do: "Gestartet"
  def status_label("question"), do: "Läuft"
  def status_label("round_reveal"), do: "Läuft"
  def status_label("finished"), do: "Beendet"
  def status_label(other), do: other
end
