defmodule PubQuizzerWeb.Admin.QuestionLiveTest do
  use PubQuizzerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias PubQuizzer.Quiz

  defp auth_conn(conn) do
    log_in_user(conn)
  end

  defp create_topic do
    {:ok, topic} = Quiz.create_topic(%{name: "Geography"})
    topic
  end

  describe "index" do
    test "lists questions for a topic", %{conn: conn} do
      topic = create_topic()

      {:ok, _q} =
        Quiz.create_question(%{
          prompt: "Capital of France?",
          options: ["Paris", "Lyon", "Marseille", "Nice"],
          correct_index: 0,
          topic_id: topic.id
        })

      {:ok, _view, html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions")

      assert html =~ "Capital of France?"
      assert html =~ "Option 1"
    end

    test "shows new page with 4 option inputs", %{conn: conn} do
      topic = create_topic()

      {:ok, _view, html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions/new")

      assert html =~ "question_options_0"
      assert html =~ "question_options_1"
      assert html =~ "question_options_2"
      assert html =~ "question_options_3"
    end
  end

  describe "new question" do
    test "creates question with options and correct_index", %{conn: conn} do
      topic = create_topic()

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions/new")

      view
      |> form("#question-form", %{
        "question" => %{
          "prompt" => "Capital of Japan?",
          "options" => %{
            "0" => "Tokyo",
            "1" => "Osaka",
            "2" => "Kyoto",
            "3" => "Nagoya"
          },
          "correct_index" => "0"
        }
      })
      |> render_submit()

      questions = Quiz.list_questions_for_topic(topic.id)
      assert length(questions) == 1
      q = hd(questions)
      assert q.prompt == "Capital of Japan?"
      assert q.options == ["Tokyo", "Osaka", "Kyoto", "Nagoya"]
      assert q.correct_index == 0
    end
  end

  describe "edit question" do
    test "updates question", %{conn: conn} do
      topic = create_topic()

      {:ok, question} =
        Quiz.create_question(%{
          prompt: "Old prompt",
          options: ["A", "B", "C", "D"],
          correct_index: 1,
          topic_id: topic.id
        })

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions/#{question}/edit")

      view
      |> form("#question-form", %{
        "question" => %{
          "prompt" => "New prompt",
          "options" => %{
            "0" => "W",
            "1" => "X",
            "2" => "Y",
            "3" => "Z"
          },
          "correct_index" => "2"
        }
      })
      |> render_submit()

      updated = Quiz.get_question!(question.id)
      assert updated.prompt == "New prompt"
      assert updated.options == ["W", "X", "Y", "Z"]
      assert updated.correct_index == 2
    end
  end

  describe "delete question" do
    test "deletes question from index", %{conn: conn} do
      topic = create_topic()

      {:ok, question} =
        Quiz.create_question(%{
          prompt: "To delete",
          options: ["A", "B", "C", "D"],
          correct_index: 0,
          topic_id: topic.id
        })

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions")

      assert has_element?(view, "tr#questions-#{question.id}")

      view
      |> element("tr#questions-#{question.id} button[phx-click='ask_delete']")
      |> render_click()

      view |> element("button[phx-click='confirm_delete']") |> render_click()
      refute has_element?(view, "tr#questions-#{question.id}")
    end
  end
end
