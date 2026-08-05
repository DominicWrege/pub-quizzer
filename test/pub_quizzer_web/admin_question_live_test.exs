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

  describe "slide layout" do
    test "new question defaults to classic layout", %{conn: conn} do
      topic = create_topic()

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions/new")

      assert has_element?(view, "input[name='question[layout]'][value='classic'][checked]")
      refute has_element?(view, "input[name='question[layout]'][value='answer_cards'][checked]")
      refute has_element?(view, "input[name='question[layout]'][value='image_side'][checked]")
    end

    test "layout picker renders all three options", %{conn: conn} do
      topic = create_topic()

      {:ok, _view, html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions/new")

      assert html =~ "Text"
      assert html =~ "Bild + Text"
      assert html =~ "Antwort-Bilder"
      assert html =~ "Bild oben"
    end

    test "image position sub-toggle only appears for image_side layout", %{conn: conn} do
      topic = create_topic()

      {:ok, q_classic} =
        Quiz.create_question(%{
          prompt: "Classic",
          options: ["A", "B", "C", "D"],
          correct_index: 0,
          topic_id: topic.id,
          layout: "classic"
        })

      {:ok, q_side} =
        Quiz.create_question(%{
          prompt: "Side",
          options: ["A", "B", "C", "D"],
          correct_index: 0,
          topic_id: topic.id,
          layout: "image_side"
        })

      {:ok, q_cards} =
        Quiz.create_question(%{
          prompt: "Cards",
          options: ["A", "B", "C", "D"],
          correct_index: 0,
          topic_id: topic.id,
          layout: "answer_cards"
        })

      {:ok, view_classic, _html} =
        conn |> auth_conn() |> live(~p"/admin/topics/#{topic}/questions/#{q_classic}/edit")

      refute has_element?(view_classic, "input[name='question[image_position]']")

      {:ok, view_side, _html} =
        conn |> auth_conn() |> live(~p"/admin/topics/#{topic}/questions/#{q_side}/edit")

      assert has_element?(view_side, "input[name='question[image_position]']")

      {:ok, view_cards, _html} =
        conn |> auth_conn() |> live(~p"/admin/topics/#{topic}/questions/#{q_cards}/edit")

      refute has_element?(view_cards, "input[name='question[image_position]']")
    end

    test "creates a question with answer_cards layout", %{conn: conn} do
      topic = create_topic()

      {:ok, view, _html} =
        conn |> auth_conn() |> live(~p"/admin/topics/#{topic}/questions/new")

      view
      |> form("#question-form", %{
        "question" => %{
          "prompt" => "Which flag?",
          "options" => %{"0" => "A", "1" => "B", "2" => "C", "3" => "D"},
          "correct_index" => "0",
          "layout" => "answer_cards"
        }
      })
      |> render_submit()

      assert [q] = Quiz.list_questions_for_topic(topic.id)
      assert q.layout == "answer_cards"
    end

    test "switching to image_side via validate reveals the position sub-toggle", %{
      conn: conn
    } do
      topic = create_topic()

      {:ok, view, _html} =
        conn |> auth_conn() |> live(~p"/admin/topics/#{topic}/questions/new")

      html =
        render_change(view, "validate", %{
          "_target" => "question[layout]",
          "question" => %{
            "prompt" => "X",
            "options" => %{"0" => "A", "1" => "B", "2" => "C", "3" => "D"},
            "correct_index" => "0",
            "layout" => "image_side"
          }
        })

      assert html =~ "Bildposition"
      assert has_element?(view, "input[name='question[image_position]']")
    end

    test "preview renders answer_cards layout without crashing", %{conn: conn} do
      topic = create_topic()

      {:ok, question} =
        Quiz.create_question(%{
          prompt: "Which one?",
          options: ["A", "B", "C", "D"],
          correct_index: 0,
          topic_id: topic.id,
          layout: "answer_cards"
        })

      {:ok, view, _html} =
        conn |> auth_conn() |> live(~p"/admin/topics/#{topic}/questions/#{question}/edit")

      html = render_click(view, "toggle_preview", %{})
      assert html =~ "Vorschau"
      assert html =~ "grid-cols-2"
      refute html =~ "UndefinedFunctionError"
    end

    test "image_side layout without an image falls back to classic in preview", %{
      conn: conn
    } do
      topic = create_topic()

      {:ok, question} =
        Quiz.create_question(%{
          prompt: "No image side",
          options: ["A", "B", "C", "D"],
          correct_index: 0,
          topic_id: topic.id,
          layout: "image_side"
        })

      {:ok, view, _html} =
        conn |> auth_conn() |> live(~p"/admin/topics/#{topic}/questions/#{question}/edit")

      html = render_click(view, "toggle_preview", %{})
      # classic fallback: single-column, no image_side grid
      refute html =~ ~s(grid-cols-1 sm:grid-cols-3)
    end

    test "creates a question with multiple images", %{conn: conn} do
      topic = create_topic()

      {:ok, view, _html} =
        conn |> auth_conn() |> live(~p"/admin/topics/#{topic}/questions/new")

      view
      |> form("#question-form", %{
        "question" => %{
          "prompt" => "Two logos",
          "options" => %{"0" => "A", "1" => "B", "2" => "C", "3" => "D"},
          "correct_index" => "0",
          "layout" => "image_side"
        }
      })
      |> render_submit()

      assert [q] = Quiz.list_questions_for_topic(topic.id)

      {:ok, q} = Quiz.update_question(q, %{images: ["/uploads/a.jpg", "/uploads/b.jpg"]})
      assert q.images == ["/uploads/a.jpg", "/uploads/b.jpg"]
    end

    test "remove_image drops one image and keeps the rest", %{conn: conn} do
      topic = create_topic()

      {:ok, question} =
        Quiz.create_question(%{
          prompt: "Multi",
          options: ["A", "B", "C", "D"],
          correct_index: 0,
          topic_id: topic.id,
          images: ["/uploads/a.jpg", "/uploads/b.jpg"]
        })

      {:ok, view, _html} =
        conn |> auth_conn() |> live(~p"/admin/topics/#{topic}/questions/#{question}/edit")

      view
      |> element("button[phx-click='remove_image'][phx-value-index='0']")
      |> render_click()

      view
      |> form("#question-form", %{
        "question" => %{
          "prompt" => "Multi",
          "options" => %{"0" => "A", "1" => "B", "2" => "C", "3" => "D"},
          "correct_index" => "0"
        }
      })
      |> render_submit()

      assert Quiz.get_question!(question.id).images == ["/uploads/b.jpg"]
    end

    test "image_side preview stacks multiple images", %{conn: conn} do
      topic = create_topic()

      {:ok, question} =
        Quiz.create_question(%{
          prompt: "Stacked",
          options: ["A", "B", "C", "D"],
          correct_index: 0,
          topic_id: topic.id,
          layout: "image_side",
          images: ["/uploads/a.jpg", "/uploads/b.jpg"]
        })

      {:ok, view, _html} =
        conn |> auth_conn() |> live(~p"/admin/topics/#{topic}/questions/#{question}/edit")

      html = render_click(view, "toggle_preview", %{})
      assert html =~ "/uploads/a.jpg"
      assert html =~ "/uploads/b.jpg"
    end

    test "image_top preview renders image next to prompt with options below", %{
      conn: conn
    } do
      topic = create_topic()

      {:ok, question} =
        Quiz.create_question(%{
          prompt: "Flood app",
          options: ["A", "B", "C", "D"],
          correct_index: 0,
          topic_id: topic.id,
          layout: "image_top",
          images: ["/uploads/flood.jpg"]
        })

      {:ok, view, _html} =
        conn |> auth_conn() |> live(~p"/admin/topics/#{topic}/questions/#{question}/edit")

      html = render_click(view, "toggle_preview", %{})
      assert html =~ "/uploads/flood.jpg"
      assert html =~ "Flood app"
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

  describe "reorder questions" do
    defp create_three_questions(topic) do
      {:ok, q1} = create_question(topic, "Q1")
      {:ok, q2} = create_question(topic, "Q2")
      {:ok, q3} = create_question(topic, "Q3")
      {q1, q2, q3}
    end

    defp create_question(topic, prompt) do
      Quiz.create_question(%{
        prompt: prompt,
        options: ["A", "B", "C", "D"],
        correct_index: 0,
        topic_id: topic.id
      })
    end

    defp prompts_in_order(topic_id) do
      Quiz.list_questions_for_topic(topic_id) |> Enum.map(& &1.prompt)
    end

    test "move_down swaps a question with its neighbor", %{conn: conn} do
      topic = create_topic()
      {q1, _q2, _q3} = create_three_questions(topic)

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions")

      view
      |> element("#questions-#{q1.id} button[phx-click='move_down']")
      |> render_click()

      assert prompts_in_order(topic.id) == ["Q2", "Q1", "Q3"]
    end

    test "move_up moves a question up", %{conn: conn} do
      topic = create_topic()
      {_q1, _q2, q3} = create_three_questions(topic)

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions")

      view
      |> element("#questions-#{q3.id} button[phx-click='move_up']")
      |> render_click()

      assert prompts_in_order(topic.id) == ["Q1", "Q3", "Q2"]
    end

    test "up button is disabled on the first question, down on the last", %{conn: conn} do
      topic = create_topic()
      {q1, _q2, q3} = create_three_questions(topic)

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions")

      assert has_element?(view, "#questions-#{q1.id} button[phx-click='move_up'][disabled]")
      assert has_element?(view, "#questions-#{q3.id} button[phx-click='move_down'][disabled]")
      refute has_element?(view, "#questions-#{q1.id} button[phx-click='move_down'][disabled]")
      refute has_element?(view, "#questions-#{q3.id} button[phx-click='move_up'][disabled]")
    end

    test "reorder event applies the full given order", %{conn: conn} do
      topic = create_topic()
      {q1, q2, q3} = create_three_questions(topic)

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions")

      render_hook(view, "reorder", %{"ids" => ["#{q3.id}", "#{q1.id}", "#{q2.id}"]})

      assert prompts_in_order(topic.id) == ["Q3", "Q1", "Q2"]
    end

    test "reorder event with mismatched ids keeps the current order", %{conn: conn} do
      topic = create_topic()
      {_q1, _q2, _q3} = create_three_questions(topic)

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions")

      render_hook(view, "reorder", %{"ids" => ["999999"]})

      assert prompts_in_order(topic.id) == ["Q1", "Q2", "Q3"]
    end

    test "reorder controls are hidden while searching", %{conn: conn} do
      topic = create_topic()
      {_q1, _q2, _q3} = create_three_questions(topic)

      {:ok, view, _html} =
        conn
        |> auth_conn()
        |> live(~p"/admin/topics/#{topic}/questions")

      html = render_change(view, "search", %{"search" => "Q1"})

      refute html =~ "move_up"
      refute html =~ "drag-handle"
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
