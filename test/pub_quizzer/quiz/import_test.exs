defmodule PubQuizzer.Quiz.ImportTest do
  use PubQuizzer.DataCase, async: true

  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.Import

  defp catalog(quizzes), do: Jason.encode!(%{"quizzes" => quizzes})

  defp quiz(attrs \\ %{}) do
    Map.merge(%{"topic" => "Energie", "questions" => [question()]}, attrs)
  end

  defp question(attrs \\ %{}) do
    Map.merge(
      %{
        "number" => 1,
        "slide" => 2,
        "question" => "Welche Antwort ist richtig?",
        "answers" => %{"A" => "eins", "B" => "zwei", "C" => "drei", "D" => "vier"},
        "correct_answer" => "C"
      },
      attrs
    )
  end

  defp parse(json, existing \\ []), do: Import.parse_and_validate(json, existing)

  describe "parse_and_validate/2 structure" do
    test "rejects invalid JSON" do
      assert {:error, [message]} = parse("{not json")
      assert message =~ "Kein gültiges JSON"
    end

    test "rejects a root without a quizzes array" do
      assert {:error, [message]} = parse(Jason.encode!(%{"foo" => 1}))
      assert message =~ "quizzes"
    end

    test "rejects an empty quizzes array" do
      assert {:error, [_message]} = parse(catalog([]))
    end
  end

  describe "parse_and_validate/2 questions" do
    test "maps a valid topic and question to draft attrs" do
      assert {:ok, result} = parse(catalog([quiz()]))
      assert result.skipped == []
      assert result.warnings == []

      assert [%{name: "Energie", questions: [attrs]}] = result.importable
      assert attrs["prompt"] == "Welche Antwort ist richtig?"
      assert attrs["correct_index"] == 2
      assert attrs["status"] == "draft"

      assert attrs["options"] == [
               %{"text" => "eins"},
               %{"text" => "zwei"},
               %{"text" => "drei"},
               %{"text" => "vier"}
             ]
    end

    test "ignores title, source_file, number and slide" do
      json =
        catalog([
          quiz(%{"title" => "Quiz", "source_file" => "x.pptx", "questions" => [question()]})
        ])

      assert {:ok, %{importable: [%{questions: [attrs]}]}} = parse(json)
      refute Map.has_key?(attrs, "title")
      refute Map.has_key?(attrs, "slide")
      refute Map.has_key?(attrs, "number")
    end

    test "flags a missing correct answer and preselects the first option" do
      json = catalog([quiz(%{"questions" => [question(%{"correct_answer" => nil})]})])

      assert {:ok, result} = parse(json)
      assert [%{questions: [attrs]}] = result.importable
      assert attrs["correct_index"] == 0
      assert [warning] = result.warnings
      assert warning.topic == "Energie"
      assert warning.message =~ "Richtige Antwort fehlt"
    end

    test "skips a topic whose question has an unknown correct_answer" do
      json = catalog([quiz(%{"questions" => [question(%{"correct_answer" => "Z"})]})])

      assert {:ok, result} = parse(json)
      assert result.importable == []
      assert [%{name: "Energie", reason: reason}] = result.skipped
      assert reason =~ "keine der Antworten"
    end

    test "skips a topic with too few answers" do
      json = catalog([quiz(%{"questions" => [question(%{"answers" => %{"A" => "eins"}})]})])

      assert {:ok, %{importable: [], skipped: [%{reason: reason}]}} = parse(json)
      assert reason =~ "mindestens"
    end

    test "skips a topic with too many answers" do
      answers = Map.new(~w(A B C D E F G), &{&1, &1})

      json = catalog([quiz(%{"questions" => [question(%{"answers" => answers})]})])

      assert {:ok, %{importable: [], skipped: [%{reason: reason}]}} = parse(json)
      assert reason =~ "höchstens"
    end

    test "skips a topic when a question prompt is blank" do
      json = catalog([quiz(%{"questions" => [question(%{"question" => "  "})]})])

      assert {:ok, %{importable: [], skipped: [%{reason: reason}]}} = parse(json)
      assert reason =~ "Fragetext"
    end

    test "accepts a prompt up to 2000 chars and rejects longer ones" do
      ok_json =
        catalog([
          quiz(%{"questions" => [question(%{"question" => String.duplicate("a", 2000)})]})
        ])

      assert {:ok, %{importable: [_]}} = parse(ok_json)

      too_long =
        catalog([
          quiz(%{"questions" => [question(%{"question" => String.duplicate("a", 2001)})]})
        ])

      assert {:ok, %{importable: [], skipped: [%{reason: reason}]}} = parse(too_long)
      assert reason =~ "2000"
    end

    test "skips a topic when the questions field is missing or empty" do
      assert {:ok, %{skipped: [%{reason: reason}]}} = parse(catalog([%{"topic" => "Leer"}]))
      assert reason =~ "questions"
    end

    test "skips an entry without a topic name" do
      json = catalog([%{"topic" => "", "questions" => [question()]}])
      assert {:ok, %{importable: [], skipped: [%{name: "—"}]}} = parse(json)
    end
  end

  describe "parse_and_validate/2 topic collisions" do
    test "skips a topic that already exists in the database" do
      json = catalog([quiz()])

      assert {:ok, %{importable: [], skipped: [%{name: "Energie", reason: reason}]}} =
               parse(json, ["Energie"])

      assert reason =~ "existiert bereits"
    end

    test "skips a topic repeated within the same file" do
      json = catalog([quiz(%{"topic" => "Energie"}), quiz(%{"topic" => "Energie"})])

      assert {:ok, result} = parse(json)
      assert [%{name: "Energie"}] = result.importable
      assert [%{name: "Energie", reason: reason}] = result.skipped
      assert reason =~ "mehrfach"
    end

    test "keeps valid topics when others are skipped" do
      json =
        catalog([
          quiz(%{"topic" => "Neu"}),
          quiz(%{"topic" => "Alt"}),
          quiz(%{"topic" => "Kaputt", "questions" => [question(%{"correct_answer" => "Z"})]})
        ])

      assert {:ok, result} = parse(json, ["Alt"])
      assert [%{name: "Neu"}] = result.importable
      assert Enum.map(result.skipped, & &1.name) == ["Alt", "Kaputt"]
    end
  end

  describe "import/1" do
    test "persists topics and draft questions in order" do
      json =
        catalog([
          quiz(%{
            "topic" => "Energie",
            "questions" => [
              question(%{"question" => "Frage 1"}),
              question(%{"question" => "Frage 2", "correct_answer" => "A"})
            ]
          })
        ])

      assert {:ok, %{importable: importable}} = parse(json)
      assert {:ok, [%{name: "Energie", count: 2}]} = Import.import(importable)

      topic = Enum.find(Quiz.list_topics(), &(&1.name == "Energie"))
      assert topic

      questions = Quiz.list_questions_for_topic(topic.id)
      assert Enum.map(questions, & &1.prompt) == ["Frage 1", "Frage 2"]
      assert Enum.map(questions, & &1.position) == [0, 1]
      assert Enum.all?(questions, &(&1.status == "draft"))
      assert Enum.map(questions, & &1.correct_index) == [2, 0]
    end

    test "rolls back everything when a later topic fails" do
      {:ok, _} = Quiz.create_topic(%{name: "Alt"})

      question = %{
        "prompt" => "x",
        "options" => [%{"text" => "a"}, %{"text" => "b"}],
        "correct_index" => 0,
        "status" => "draft"
      }

      importable = [
        %{name: "Neu", questions: [question]},
        %{name: "Alt", questions: [question]}
      ]

      assert {:error, {:topic_failed, "Alt", _changeset}} = Import.import(importable)
      refute Enum.any?(Quiz.list_topics(), &(&1.name == "Neu"))
    end
  end
end
