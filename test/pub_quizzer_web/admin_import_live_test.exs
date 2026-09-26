defmodule PubQuizzerWeb.Admin.ImportLiveTest do
  use PubQuizzerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PubQuizzer.Quiz

  defp catalog_json do
    Jason.encode!(%{
      "quizzes" => [
        %{
          "title" => "Quiz For a better life",
          "source_file" => "x.pptx",
          "topic" => "Energie",
          "questions" => [
            %{
              "number" => 1,
              "question" => "Welche Antwort ist richtig?",
              "answers" => %{"A" => "eins", "B" => "zwei", "C" => "drei", "D" => "vier"},
              "correct_answer" => "C"
            },
            %{
              "number" => 2,
              "question" => "Ohne richtige Antwort",
              "answers" => %{"A" => "eins", "B" => "zwei", "C" => "drei", "D" => "vier"},
              "correct_answer" => nil
            }
          ]
        }
      ]
    })
  end

  defp upload_catalog(view, content, name \\ "catalog.json") do
    view
    |> file_input("#import-form", :catalog, [
      %{name: name, content: content, type: "application/json"}
    ])
    |> render_upload(name)
  end

  describe "authorization" do
    test "moderators are redirected to topics", %{conn: conn} do
      conn = log_in_user(conn)

      assert {:error, {:redirect, %{to: "/admin/topics"}}} = live(conn, ~p"/admin/import")
    end

    test "superadmins see the import form", %{conn: conn} do
      conn = log_in_superadmin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/import")

      assert has_element?(view, "#import-form")
      assert has_element?(view, "#import-form input[type='file']")
    end
  end

  describe "preview" do
    test "shows importable topics and warnings", %{conn: conn} do
      conn = log_in_superadmin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/import")

      upload_catalog(view, catalog_json())
      html = view |> form("#import-form") |> render_submit()

      assert html =~ "Energie"
      assert html =~ "2 Frage(n)"
      assert html =~ "importierbar"
      assert html =~ "Richtige Antwort fehlt"
      assert has_element?(view, "button[phx-click='confirm_import']")
    end

    test "shows an error for invalid JSON", %{conn: conn} do
      conn = log_in_superadmin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/import")

      upload_catalog(view, "{not json")
      html = view |> form("#import-form") |> render_submit()

      assert html =~ "Kein gültiges JSON"
      refute has_element?(view, "button[phx-click='confirm_import']")
    end

    test "skips an existing topic", %{conn: conn} do
      {:ok, _} = Quiz.create_topic(%{name: "Energie"})
      conn = log_in_superadmin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/import")

      upload_catalog(view, catalog_json())
      html = view |> form("#import-form") |> render_submit()

      assert html =~ "existiert bereits"
      refute has_element?(view, "button[phx-click='confirm_import']")
    end
  end

  describe "confirm_import" do
    test "publishes selected questions and imports the rest as drafts", %{conn: conn} do
      conn = log_in_superadmin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/import")

      upload_catalog(view, catalog_json())
      view |> form("#import-form") |> render_submit()

      assert has_element?(
               view,
               "#import-question-publish-0-0[type='checkbox'].toggle.toggle-success"
             )

      view |> element("#import-question-publish-0-0") |> render_click()
      view |> element("button[phx-click='confirm_import']") |> render_click()

      topic = Enum.find(Quiz.list_topics(), &(&1.name == "Energie"))
      questions = Quiz.list_questions_for_topic(topic.id)

      assert Enum.map(questions, & &1.status) == ["published", "draft"]
    end

    test "publishes every question when publish all is selected", %{conn: conn} do
      conn = log_in_superadmin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/import")

      upload_catalog(view, catalog_json())
      view |> form("#import-form") |> render_submit()

      view |> element("button[phx-click='publish_all']") |> render_click()
      view |> element("button[phx-click='confirm_import']") |> render_click()

      topic = Enum.find(Quiz.list_topics(), &(&1.name == "Energie"))
      questions = Quiz.list_questions_for_topic(topic.id)

      assert Enum.map(questions, & &1.status) == ["published", "published"]
    end

    test "creates topics and draft questions", %{conn: conn} do
      conn = log_in_superadmin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/import")

      upload_catalog(view, catalog_json())
      view |> form("#import-form") |> render_submit()

      html = view |> element("button[phx-click='confirm_import']") |> render_click()
      assert html =~ "Import abgeschlossen"
      assert html =~ "Energie: 2 Frage(n)"

      topic = Enum.find(Quiz.list_topics(), &(&1.name == "Energie"))
      assert topic

      questions = Quiz.list_questions_for_topic(topic.id)
      assert length(questions) == 2
      assert Enum.all?(questions, &(&1.status == "draft"))
      assert Enum.map(questions, & &1.correct_index) == [2, 0]

      assert has_element?(view, "#restart-import-button.btn.btn-primary")

      view |> element("#restart-import-button") |> render_click()

      assert has_element?(view, "#import-form")
      refute has_element?(view, "#restart-import-button")
    end
  end
end
