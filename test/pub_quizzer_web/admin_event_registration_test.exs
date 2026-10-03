defmodule PubQuizzerWeb.Admin.EventRegistrationTest do
  use PubQuizzerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.Engine

  setup do
    {:ok, event} = Quiz.create_event(%{team_count: 3})
    start_supervised!({Engine, event.id})
    {:ok, event: event}
  end

  test "an old registration allows starting with offline phones and unused cards", %{
    conn: conn,
    event: event
  } do
    {:ok, team} = Quiz.claim_team_slot(event, 0)

    team
    |> Ecto.Changeset.change(claimed_at: ~U[2020-01-01 12:00:00Z])
    |> PubQuizzer.Repo.update!()

    {:ok, view, _} = conn |> log_in_user() |> live(~p"/admin/events/#{event.id}")

    assert has_element?(view, "#team-card-#{team.id} .badge-success", "Angemeldet")
    assert has_element?(view, "#team-#{team.id} .badge-success", "Angemeldet")
    assert has_element?(view, "#start-quiz:not([disabled])")

    view |> element("#start-quiz") |> render_click()
    assert_redirect(view, ~p"/quiz/#{event.code}/host")

    {:ok, state} = Engine.get_state(event.id)
    assert state.status == :topic_selection
    assert Enum.map(state.teams, & &1.id) == [team.id]
  end

  test "disconnecting a phone keeps its team registered and the start button enabled", %{
    conn: conn,
    event: event
  } do
    {:ok, team} = Quiz.claim_team_slot(event, 0)
    {:ok, view, _} = conn |> log_in_user() |> live(~p"/admin/events/#{event.id}")

    send(view.pid, {:team_connected, team.id})
    assert has_element?(view, "#start-quiz:not([disabled])")
    send(view.pid, {:team_disconnected, team.id})

    assert has_element?(view, "#team-card-#{team.id} .badge-success", "Angemeldet")
    assert has_element?(view, "#start-quiz:not([disabled])")
  end

  test "two phones scanning the same team card register just one team", %{
    conn: conn,
    event: event
  } do
    {:ok, view, _} = conn |> log_in_user() |> live(~p"/admin/events/#{event.id}")
    team = hd(event.teams)
    first = get(build_conn(), ~p"/quiz/join/#{event.code}/#{team.link_code}")
    second = get(build_conn(), ~p"/quiz/join/#{event.code}/#{team.link_code}")

    assert get_session(first, :team_id) == team.id
    assert get_session(second, :team_id) == team.id
    assert has_element?(view, "#event-registration-summary", "1 von 3 Teams angemeldet")
    assert has_element?(view, "#start-quiz:not([disabled])")

    view |> element("#start-quiz") |> render_click()
    assert_redirect(view, ~p"/quiz/#{event.code}/host")
    {:ok, state} = Engine.get_state(event.id)
    assert Enum.map(state.teams, & &1.id) == [team.id]
  end

  test "releasing a registered slot resets readiness and a new scan registers it again", %{
    conn: conn,
    event: event
  } do
    {:ok, team} = Quiz.claim_team_slot(event, 0)
    {:ok, view, _} = conn |> log_in_user() |> live(~p"/admin/events/#{event.id}")

    view
    |> element("#release-team-#{team.id}")
    |> render_click()

    assert has_element?(view, "#team-card-#{team.id} .badge-neutral", "Noch nicht gescannt")
    assert has_element?(view, "#start-quiz[disabled]")
    assert is_nil(Quiz.get_team!(team.id).claimed_at)

    get(build_conn(), ~p"/quiz/join/#{event.code}/#{team.link_code}")
    assert has_element?(view, "#team-card-#{team.id} .badge-success", "Angemeldet")
    assert has_element?(view, "#start-quiz:not([disabled])")
  end

  test "start refuses an event without registered teams even for a direct event", %{
    conn: conn,
    event: event
  } do
    {:ok, view, _} = conn |> log_in_user() |> live(~p"/admin/events/#{event.id}")
    render_click(view, "do_start")

    assert Quiz.get_event!(event.id).status == "lobby"
    assert has_element?(view, "#start-quiz[disabled]")
  end

  test "a released team is not included when starting an already loaded engine", %{
    conn: conn,
    event: event
  } do
    {:ok, first} = Quiz.claim_team_slot(event, 0)
    {:ok, second} = Quiz.claim_team_slot(event, 1)
    {:ok, _state} = Engine.get_state(event.id)
    {:ok, _} = Quiz.unclaim_team(second.id)

    {:ok, view, _} = conn |> log_in_user() |> live(~p"/admin/events/#{event.id}")
    render_click(view, "do_start")
    assert_redirect(view, ~p"/quiz/#{event.code}/host")

    {:ok, state} = Engine.get_state(event.id)
    assert state.status == :topic_selection
    assert Enum.map(state.teams, & &1.id) == [first.id]
    assert state.standings == %{first.id => 0}
  end
end
