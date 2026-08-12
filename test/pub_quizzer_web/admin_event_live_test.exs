defmodule PubQuizzerWeb.Admin.EventLiveTest do
  use PubQuizzerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias PubQuizzer.Quiz

  defp auth_conn(conn) do
    log_in_user(conn)
  end

  describe "index" do
    test "lists events", %{conn: conn} do
      {:ok, event} = Quiz.create_event(%{team_count: 4})

      {:ok, _view, html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/events")

      assert html =~ "Events"
      assert html =~ event.code
    end

    test "shows Verwalten link for lobby events", %{conn: conn} do
      {:ok, event} = Quiz.create_event(%{team_count: 4})

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/events")

      assert has_element?(view, "a[href='/admin/events/#{event.id}']")
    end

    test "shows Moderator link for started events", %{conn: conn} do
      {:ok, event} = Quiz.create_event(%{team_count: 4})
      {:ok, _} = Quiz.start_event(event)

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/events")

      assert has_element?(view, "a[href='/quiz/#{event.code}/host']", "Moderator")
    end
  end

  describe "new" do
    test "clicking Neues Quiz creates an event with 4 teams and redirects to show", %{conn: conn} do
      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/events")

      refute has_element?(view, "#event-form")

      view |> element("#new-event-btn") |> render_click()

      {path, _flash} = assert_redirect(view)
      assert String.starts_with?(path, "/admin/events/")

      id = String.trim_leading(path, "/admin/events/")
      event = Quiz.get_event!(id)
      assert event.team_count == 4
    end
  end

  describe "show" do
    test "shows event code and team list", %{conn: conn} do
      {:ok, event} = Quiz.create_event(%{team_count: 3})

      {:ok, _view, html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/events/#{event.id}")

      assert html =~ event.code

      for team <- event.teams do
        assert html =~ team.name
      end
    end

    test "add slot button adds a team", %{conn: conn} do
      {:ok, event} = Quiz.create_event(%{team_count: 3})

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/events/#{event.id}")

      view |> element("button", "Team hinzufügen") |> render_click()
      assert has_element?(view, "#event-teams tr", "4")
    end

    test "links to printable team cards", %{conn: conn} do
      {:ok, event} = Quiz.create_event(%{team_count: 3})

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/events/#{event.id}")

      assert has_element?(view, "a[href='/admin/events/#{event.id}/team-cards']")
    end

    test "renames event via dialog", %{conn: conn} do
      {:ok, event} = Quiz.create_event(%{team_count: 3})

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/events/#{event.id}")

      refute has_element?(view, "#event-name-dialog")

      view |> element("button[phx-click=open_edit_name]") |> render_click()
      assert has_element?(view, "#event-name-dialog")

      view
      |> element("#event-name-form")
      |> render_submit(%{"name" => "Staffelabend"})

      refute has_element?(view, "#event-name-dialog")
      assert has_element?(view, "h1", "Staffelabend")
    end
  end

  describe "team cards" do
    test "renders one printable card per team with QR code and slot number", %{conn: conn} do
      {:ok, event} = Quiz.create_event(%{team_count: 2})

      {:ok, _view, html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/events/#{event.id}/team-cards")

      assert html =~ "Team-Karten"
      assert html =~ event.code

      [team1, team2] = Enum.sort_by(event.teams, & &1.slot_index)

      assert html =~ "Team 1"
      assert html =~ "Team 2"
      assert html =~ "team-card-#{team1.id}"
      assert html =~ "team-card-#{team2.id}"
      assert html =~ "<svg"
      assert html =~ "QR-Code scannen oder Link im Browser eingeben"
      refute html =~ "Kamera auf QR-Code richten"
      refute html =~ "Oder Link im Browser eingeben"
    end
  end
end
