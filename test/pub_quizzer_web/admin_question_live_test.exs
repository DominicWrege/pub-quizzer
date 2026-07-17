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
    test "creates question with options and correct_index via select_correct", %{conn: conn} do
      topic = create_topic()

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions/new")

      # WYSIWYG: prompt + options are typed via validate, correct answer picked via click
      view
      |> form("#question-form", %{
        "question" => %{
          "prompt" => "Capital of Japan?",
          "options" => %{"0" => "Tokyo", "1" => "Osaka", "2" => "Kyoto", "3" => "Nagoya"}
        }
      })
      |> render_change()

      view
      |> element("[phx-click='select_correct'][phx-value-index='0']")
      |> render_click()

      view
      |> form("#question-form", %{
        "question" => %{
          "prompt" => "Capital of Japan?",
          "options" => %{"0" => "Tokyo", "1" => "Osaka", "2" => "Kyoto", "3" => "Nagoya"}
        }
      })
      |> render_submit()

      questions = Quiz.list_questions_for_topic(topic.id)
      assert length(questions) == 1
      q = hd(questions)
      assert q.prompt == "Capital of Japan?"

      assert q.options == [
               %{"text" => "Tokyo"},
               %{"text" => "Osaka"},
               %{"text" => "Kyoto"},
               %{"text" => "Nagoya"}
             ]

      assert q.correct_index == 0
    end
  end

  describe "edit question" do
    test "updates question text and options", %{conn: conn} do
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
          "options" => %{"0" => "W", "1" => "X", "2" => "Y", "3" => "Z"}
        }
      })
      |> render_submit()

      updated = Quiz.get_question!(question.id)
      assert updated.prompt == "New prompt"

      assert updated.options == [
               %{"text" => "W"},
               %{"text" => "X"},
               %{"text" => "Y"},
               %{"text" => "Z"}
             ]

      # correct_index preserved from the hidden input (was 1 at load)
      assert updated.correct_index == 1
    end

    test "clicking an option card updates the correct answer", %{conn: conn} do
      topic = create_topic()

      {:ok, question} =
        Quiz.create_question(%{
          prompt: "Which one?",
          options: ["Alpha", "Beta", "Gamma", "Delta"],
          correct_index: 0,
          topic_id: topic.id
        })

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions/#{question}/edit")

      # Click option C
      view
      |> element("[phx-click='select_correct'][phx-value-index='2']")
      |> render_click()

      # Hidden input should now carry correct_index=2 — verify via form submit
      view
      |> form("#question-form", %{
        "question" => %{
          "prompt" => "Which one?",
          "options" => %{"0" => "Alpha", "1" => "Beta", "2" => "Gamma", "3" => "Delta"}
        }
      })
      |> render_submit()

      updated = PubQuizzer.Quiz.get_question!(question.id)
      assert updated.correct_index == 2
    end

    test "validate does not crash when OptionSorter leaves _unused_N keys in options", %{
      conn: conn
    } do
      topic = create_topic()

      {:ok, question} =
        Quiz.create_question(%{
          prompt: "Which one?",
          options: ["Alpha", "Beta", "Gamma", "Delta"],
          correct_index: 0,
          topic_id: topic.id
        })

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions/#{question}/edit")

      html =
        render_change(view, "validate", %{
          "_target" => "question[correct_index]",
          "question" => %{
            "prompt" => "Which one?",
            "options" => %{
              "_unused_0" => "",
              "0" => "Alpha",
              "_unused_1" => "",
              "1" => "Beta",
              "_unused_2" => "",
              "2" => "Gamma",
              "_unused_3" => "",
              "3" => "Delta"
            },
            "correct_index" => "1"
          }
        })

      refute html =~ "ArgumentError"
      assert html =~ "Alpha"
      assert html =~ "Delta"
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
