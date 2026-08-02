defmodule PubQuizzerWeb.Admin.TopicLiveTest do
  use PubQuizzerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias PubQuizzer.Quiz

  defp auth_conn(conn) do
    log_in_user(conn)
  end

  describe "index" do
    test "lists topics", %{conn: conn} do
      {:ok, _topic} = Quiz.create_topic(%{name: "Geography", description: "World facts"})

      {:ok, _view, html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics")

      assert html =~ "Themen"
      assert html =~ "Geography"
      assert html =~ "World facts"
    end

    test "shows question count per topic", %{conn: conn} do
      {:ok, topic} = Quiz.create_topic(%{name: "Science"})

      {:ok, _q} =
        Quiz.create_question(%{
          prompt: "What is H2O?",
          options: ["Water", "Salt", "Sugar", "Acid"],
          correct_index: 0,
          topic_id: topic.id
        })

      {:ok, _view, html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics")

      assert html =~ "1"
    end

    test "shows a PDF export link per topic", %{conn: conn} do
      {:ok, topic} = Quiz.create_topic(%{name: "Geography"})

      {:ok, _view, html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics")

      assert html =~ "/admin/topics/#{topic.id}/export"
    end
  end

  describe "new topic" do
    test "shows form dialog after clicking new", %{conn: conn} do
      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics")

      refute has_element?(view, "#topic-form")

      view |> element("button", "Neues Thema") |> render_click()

      assert has_element?(view, "#topic-form")
    end

    test "creates topic inline", %{conn: conn} do
      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics")

      view |> element("button", "Neues Thema") |> render_click()

      view
      |> form("#topic-form", topic: %{name: "History", description: "Past events"})
      |> render_submit()

      assert Quiz.list_topics() |> Enum.any?(&(&1.name == "History"))
    end

    test "shows validation errors", %{conn: conn} do
      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics")

      view |> element("button", "Neues Thema") |> render_click()

      html =
        view
        |> form("#topic-form", topic: %{name: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end
  end

  describe "toggle enabled" do
    test "shows active badge", %{conn: conn} do
      {:ok, topic} = Quiz.create_topic(%{name: "Active"})

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics")

      assert has_element?(view, "div#topics-#{topic.id} .badge-success", "Aktiv")
    end
  end
end
