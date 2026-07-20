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
  def handle_params(params, url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params, url)}
  end

  defp apply_action(socket, :index, _params, _url) do
    events = Quiz.list_events()

    socket
    |> assign(:page_title, "Events")
    |> assign(:events, events)
    |> assign(:search_query, "")
    |> assign(:filtered_events, events)
    |> assign_active_finished(events)
  end

  defp apply_action(socket, :new, _params, _url) do
    socket
    |> assign(:page_title, "Neues Quiz")
    |> assign(:form, to_form(%{"team_count" => "5"}))
  end

  defp apply_action(socket, :show, %{"id" => id}, url) do
    event = Quiz.get_event_with_teams!(id)
    base = URI.parse(url) |> then(&"#{&1.scheme}://#{&1.host}:#{&1.port}")
    join_url = base <> ~p"/quiz/join/#{event.code}"
    qr_svg = EQRCode.encode(join_url) |> EQRCode.svg(color: "#1e40af", background: "#ffffff")
    qr_svg_large =
      join_url
      |> EQRCode.encode()
      |> EQRCode.svg(color: "#1e40af", background: "#ffffff", width: 700)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(PubQuizzer.PubSub, "quiz:event:#{event.id}")
    end

    socket
    |> assign(:page_title, "Event #{event.code}")
    |> assign(:event, event)
    |> assign(:join_url, join_url)
    |> assign(:qr_svg, qr_svg)
    |> assign(:qr_svg_large, qr_svg_large)
    |> assign(:connected_team_ids, MapSet.new())
    |> assign(:all_teams_connected, false)
    |> assign(:show_large_qr, false)
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

    {:noreply, socket |> assign(:filtered_events, filtered) |> assign_active_finished(filtered)}
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

    {:noreply,
     socket
     |> assign(:event, event)
     |> assign(:connected_team_ids, claimed_ids)
     |> assign(:all_teams_connected, false)}
  end

  def handle_event("kick_team", %{"team_id" => team_id}, socket) do
    team_id = String.to_integer(team_id)
    event_id = socket.assigns.event.id

    # Broadcast kick to all team lobby clients for this team
    Phoenix.PubSub.broadcast(
      PubQuizzer.PubSub,
      "quiz:event:#{event_id}",
      {:kick_team, team_id}
    )

    # Unclaim the team slot so it becomes available again
    Quiz.unclaim_team(team_id)

    event = Quiz.get_event_with_teams!(event_id)

    claimed_ids =
      event.teams
      |> Enum.filter(& &1.claimed_at)
      |> Enum.map(& &1.id)
      |> MapSet.new()

    connected_ids = MapSet.intersection(socket.assigns.connected_team_ids, claimed_ids)

    {:noreply,
     socket
     |> assign(:event, event)
     |> assign(:connected_team_ids, connected_ids)
     |> assign(:all_teams_connected, all_claimed_connected?(claimed_ids, connected_ids))}
  end

  # Show page confirmations
  def handle_event("show_large_qr", _params, socket) do
    {:noreply, assign(socket, :show_large_qr, true)}
  end

  def handle_event("hide_large_qr", _params, socket) do
    {:noreply, assign(socket, :show_large_qr, false)}
  end

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
     |> assign(:connected_team_ids, connected_ids)
     |> assign(:all_teams_connected, all_claimed_connected?(claimed_ids, connected_ids))}
  end

  def handle_info({:team_connected, team_id}, socket) do
    connected_ids = MapSet.put(socket.assigns.connected_team_ids, team_id)
    claimed_ids = claimed_team_ids(socket.assigns.event.teams)

    {:noreply,
     socket
     |> assign(:connected_team_ids, connected_ids)
     |> assign(:all_teams_connected, all_claimed_connected?(claimed_ids, connected_ids))}
  end

  def handle_info({:team_disconnected, team_id}, socket) do
    connected_ids = MapSet.delete(socket.assigns.connected_team_ids, team_id)
    claimed_ids = claimed_team_ids(socket.assigns.event.teams)

    {:noreply,
     socket
     |> assign(:connected_team_ids, connected_ids)
     |> assign(:all_teams_connected, all_claimed_connected?(claimed_ids, connected_ids))}
  end

  defp claimed_team_ids(teams) do
    teams
    |> Enum.filter(& &1.claimed_at)
    |> Enum.map(& &1.id)
    |> MapSet.new()
  end

  defp all_claimed_connected?(claimed_ids, connected_ids) do
    MapSet.size(claimed_ids) > 0 and MapSet.subset?(claimed_ids, connected_ids)
  end

  defp assign_active_finished(socket, events) do
    {active, finished} = Enum.split_with(events, &(&1.status != "finished"))
    assign(socket, active_events: active, finished_events: finished)
  end

  attr :event, :any, required: true

  def event_card(assigns) do
    ~H"""
    <div id={"event-#{@event.id}"} class="card bg-base-200 shadow-sm">
      <div class="card-body gap-3">
        <div class="flex items-center justify-between">
          <%= if @event.name && @event.name != "" do %>
            <h3 class="card-title text-base">{@event.name}</h3>
          <% else %>
            <span class="text-sm text-base-content/60 font-mono">{@event.code}</span>
          <% end %>
          <span class="badge">{@event.team_count} Teams</span>
        </div>

        <div class="flex items-center gap-2">
          <%= if @event.name && @event.name != "" do %>
            <span class="text-sm text-base-content/60 font-mono">{@event.code}</span>
          <% end %>
          <span class={[
            "text-xs font-semibold",
            @event.status in ["topic_selection", "question", "round_reveal"] && "text-primary",
            @event.status == "finished" && "text-success",
            @event.status == "lobby" && "text-base-content/40"
          ]}>
            {status_label(@event.status)}
          </span>
        </div>

        <span class="text-3xl font-bold font-mono">{Calendar.strftime(
          @event.inserted_at,
          "%d.%m.%y"
        )}</span>

        <div class="card-actions justify-end mt-2">
          <%= cond do %>
            <% @event.status in ["topic_selection", "question", "round_reveal"] -> %>
              <.link navigate={~p"/quiz/#{@event.code}/host"} class="btn btn-primary btn-sm">Moderator</.link>
              <.link navigate={~p"/admin/events/#{@event}/results"} class="btn btn-sm btn-soft">Live-Ergebnisse</.link>
            <% @event.status == "lobby" -> %>
              <.link navigate={~p"/admin/events/#{@event}"} class="btn btn-sm btn-soft">Verwalten</.link>
            <% true -> %>
              <.link navigate={~p"/admin/events/#{@event}/results"} class="btn btn-sm btn-primary">Ergebnisse</.link>
          <% end %>
          <button
            phx-click="ask_delete"
            phx-value-id={@event.id}
            class="btn btn-sm btn-danger-soft"
          >
            Löschen
          </button>
        </div>
      </div>
    </div>
    """
  end

  def status_label("lobby"), do: "Bereit"
  def status_label("topic_selection"), do: "Gestartet"
  def status_label("question"), do: "Läuft"
  def status_label("round_reveal"), do: "Läuft"
  def status_label("finished"), do: "Beendet"
  def status_label(other), do: other
end
