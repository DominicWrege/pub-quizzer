defmodule PubQuizzerWeb.Admin.EventLiveTest do
  use PubQuizzerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias PubQuizzer.Quiz

  defp auth_conn(conn) do
    Plug.Test.init_test_session(conn, admin: true)
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
    test "renders form", %{conn: conn} do
      {:ok, _view, html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/events/new")

      assert html =~ "Neues Quiz"
      assert html =~ "event-form"
    end

    test "submit creates event and redirects to show", %{conn: conn} do
      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/events/new")

      view
      |> element("#event-form")
      |> render_submit(%{"team_count" => "4"})

      {path, _flash} = assert_redirect(view)
      assert String.starts_with?(path, "/admin/events/")
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

    test "remove slot button removes the last team", %{conn: conn} do
      {:ok, event} = Quiz.create_event(%{team_count: 3})

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/events/#{event.id}")

      view |> element("button", "Team entfernen") |> render_click()
      html = render(view)
      refute html =~ "slot_index=\"3\""
    end
  end
end
