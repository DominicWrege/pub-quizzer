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

    test "creates question with default correct_index=0 without clicking an option", %{
      conn: conn
    } do
      topic = create_topic()

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions/new")

      view
      |> form("#question-form", %{
        "question" => %{
          "prompt" => "Default answer?",
          "options" => %{"0" => "A", "1" => "B", "2" => "C", "3" => "D"}
        }
      })
      |> render_submit()

      questions = Quiz.list_questions_for_topic(topic.id)
      assert length(questions) == 1
      assert hd(questions).correct_index == 0
    end

    test "shows validation errors when submitting empty form", %{conn: conn} do
      topic = create_topic()

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions/new")

      html =
        view
        |> form("#question-form", %{"question" => %{"prompt" => ""}})
        |> render_submit()

      assert html =~ "can&#39;t be blank" || html =~ "kann nicht leer"
    end

    test "does not show errors before form submission", %{conn: conn} do
      topic = create_topic()

      {:ok, _view, html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions/new")

      refute html =~ "alert alert-error"
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

    test "changing correct answer via select_correct then saving new values", %{conn: conn} do
      topic = create_topic()

      {:ok, question} =
        Quiz.create_question(%{
          prompt: "Original",
          options: ["One", "Two", "Three", "Four"],
          correct_index: 0,
          topic_id: topic.id
        })

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions/#{question}/edit")

      # Click option D (index 3)
      view
      |> element("[phx-click='select_correct'][phx-value-index='3']")
      |> render_click()

      view
      |> form("#question-form", %{
        "question" => %{
          "prompt" => "Changed",
          "options" => %{"0" => "Uno", "1" => "Dos", "2" => "Tres", "3" => "Cuatro"}
        }
      })
      |> render_submit()

      updated = Quiz.get_question!(question.id)
      assert updated.prompt == "Changed"

      assert updated.options == [
               %{"text" => "Uno"},
               %{"text" => "Dos"},
               %{"text" => "Tres"},
               %{"text" => "Cuatro"}
             ]

      assert updated.correct_index == 3
    end

    test "preview does not crash on edit page", %{conn: conn} do
      topic = create_topic()

      {:ok, question} =
        Quiz.create_question(%{
          prompt: "Preview test",
          options: ["A", "B", "C", "D"],
          correct_index: 0,
          topic_id: topic.id
        })

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions/#{question}/edit")

      html = render_click(view, "toggle_preview", %{})
      assert html =~ "Vorschau"
      refute html =~ "UndefinedFunctionError"
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

      assert has_element?(view, "#questions-#{question.id}")

      view
      |> element("#questions-#{question.id} button[phx-click='ask_delete']")
      |> render_click()

      view |> element("button[phx-click='confirm_delete']") |> render_click()
      refute has_element?(view, "#questions-#{question.id}")
    end
  end

  describe "form status toggle" do
    test "creates a published question when the toggle is on", %{conn: conn} do
      topic = create_topic()

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions/new")

      view
      |> form("#question-form", %{
        "question" => %{
          "prompt" => "Published via form?",
          "options" => %{"0" => "A", "1" => "B", "2" => "C", "3" => "D"},
          "correct_index" => "0",
          "published" => "true"
        }
      })
      |> render_submit()

      assert [q] = Quiz.list_questions_for_topic(topic.id)
      assert q.status == "published"
    end

    test "creates a draft question when the toggle is off", %{conn: conn} do
      topic = create_topic()

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions/new")

      view
      |> form("#question-form", %{
        "question" => %{
          "prompt" => "Draft via form?",
          "options" => %{"0" => "A", "1" => "B", "2" => "C", "3" => "D"},
          "correct_index" => "0",
          "published" => "false"
        }
      })
      |> render_submit()

      assert [q] = Quiz.list_questions_for_topic(topic.id)
      assert q.status == "draft"
    end

    test "updates status via the edit form toggle", %{conn: conn} do
      topic = create_topic()

      {:ok, question} =
        Quiz.create_question(%{
          prompt: "Edit status",
          options: ["A", "B", "C", "D"],
          correct_index: 0,
          topic_id: topic.id,
          status: "published"
        })

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions/#{question}/edit")

      view
      |> form("#question-form", %{
        "question" => %{
          "prompt" => "Edit status",
          "options" => %{"0" => "A", "1" => "B", "2" => "C", "3" => "D"},
          "correct_index" => "0",
          "published" => "false"
        }
      })
      |> render_submit()

      assert Quiz.get_question!(question.id).status == "draft"
    end
  end

  describe "edit topic from question list" do
    test "opens the topic form via the header pencil button", %{conn: conn} do
      topic = create_topic()

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions")

      refute has_element?(view, "#topic-form")

      view |> element("button[phx-click='start_edit_topic']") |> render_click()

      assert has_element?(view, "#topic-form")
    end

    test "updates topic name and description", %{conn: conn} do
      topic = create_topic()

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions")

      view |> element("button[phx-click='start_edit_topic']") |> render_click()

      view
      |> form("#topic-form", topic: %{name: "Renamed", description: "New desc"})
      |> render_submit()

      updated = Quiz.get_topic!(topic.id)
      assert updated.name == "Renamed"
      assert updated.description == "New desc"
      refute has_element?(view, "#topic-form")
    end

    test "disables the topic", %{conn: conn} do
      topic = create_topic()

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions")

      view |> element("button[phx-click='start_edit_topic']") |> render_click()

      view
      |> form("#topic-form", topic: %{enabled: false})
      |> render_submit()

      assert Quiz.get_topic!(topic.id).enabled == false
    end

    test "enables the topic", %{conn: conn} do
      {:ok, topic} = Quiz.create_topic(%{name: "Off", enabled: false})

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions")

      view |> element("button[phx-click='start_edit_topic']") |> render_click()

      view
      |> form("#topic-form", topic: %{enabled: true})
      |> render_submit()

      assert Quiz.get_topic!(topic.id).enabled == true
    end

    test "deletes the topic and redirects to the overview", %{conn: conn} do
      topic = create_topic()

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions")

      view |> element("button[phx-click='start_edit_topic']") |> render_click()
      view |> element("button[phx-click='ask_delete_topic']") |> render_click()
      view |> element("button[phx-click='confirm_delete_topic']") |> render_click()

      assert_redirect(view, ~p"/admin/topics")
    end
  end
end
