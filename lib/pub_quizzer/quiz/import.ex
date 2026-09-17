defmodule PubQuizzer.Quiz.Import do
  @moduledoc """
  Imports a JSON question catalog (a quiz set) into topics and questions.

  The expected JSON shape is a map with a `"quizzes"` array. Every entry maps to
  one topic (`"topic"`) and carries a `"questions"` array:

      %{
        "quizzes" => [
          %{
            "topic" => "Energie",
            "questions" => [
              %{
                "number" => 1,
                "question" => "...",
                "answers" => %{"A" => "...", "B" => "...", "C" => "...", "D" => "..."},
                "correct_answer" => "C"
              }
            ]
          }
        ]
      }

  `parse_and_validate/2` validates the whole file without touching the database
  (existing topic names are passed in) and partitions the entries into
  importable topics plus skipped topics with reasons. It never writes partially:
  if any question in a topic is invalid, that whole topic is skipped so the
  others can still import.

  All imported questions are created as drafts. A question whose
  `"correct_answer"` is `null` is imported with option A preselected and
  reported as a warning to review manually. The `"title"`, `"source_file"`,
  `"number"` and `"slide"` fields are ignored; question order follows the array
  order.

  `import/1` persists an already-validated importable list inside a single
  transaction.
  """

  alias PubQuizzer.Repo
  alias PubQuizzer.Quiz

  @min_options 2
  @max_options 6
  @max_prompt_length 2000
  @draft_status "draft"

  @type importable :: %{name: String.t(), questions: [map()]}
  @type skipped :: %{name: String.t(), reason: String.t()}
  @type warning :: %{topic: String.t(), question: String.t(), message: String.t()}

  @type result :: %{
          importable: [importable],
          skipped: [skipped],
          warnings: [warning]
        }

  @doc """
  Parses and validates a JSON catalog.

  `existing_names` is the list of topic names already present in the database;
  entries colliding with one of them are skipped (the whole topic).

  Returns `{:ok, result}` with `:importable`, `:skipped` and `:warnings`, or
  `{:error, [message]}` when the file itself is not valid JSON or does not have
  the expected top-level shape.
  """
  @spec parse_and_validate(binary(), [String.t()]) :: {:ok, result()} | {:error, [String.t()]}
  def parse_and_validate(json, existing_names \\ []) when is_binary(json) do
    with {:ok, decoded} <- decode(json),
         {:ok, quizzes} <- fetch_quizzes(decoded) do
      existing = MapSet.new(existing_names)

      result =
        Enum.reduce(quizzes, empty_acc(), fn quiz, acc ->
          build_topic(quiz, existing, acc)
        end)

      {:ok,
       %{
         importable: Enum.reverse(result.importable),
         skipped: result.skipped,
         warnings: result.warnings
       }}
    end
  end

  @doc """
  Persists a validated importable list. Runs in a single transaction: either all
  topics and questions are written or none are. Returns `{:ok, summary}` where
  summary lists `%{name: name, count: n}` per topic.
  """
  @spec import([importable]) ::
          {:ok, [%{name: String.t(), count: non_neg_integer()}]} | {:error, term()}
  def import(importable) when is_list(importable) do
    Repo.transaction(fn -> Enum.map(importable, &insert_topic/1) end)
  end

  defp insert_topic(%{name: name, questions: questions}) do
    case Quiz.create_topic(%{name: name}) do
      {:ok, topic} ->
        Enum.each(questions, fn attrs ->
          case Quiz.create_question(Map.put(attrs, "topic_id", topic.id)) do
            {:ok, _question} -> :ok
            {:error, changeset} -> Repo.rollback({:question_failed, name, changeset})
          end
        end)

        %{name: name, count: length(questions)}

      {:error, changeset} ->
        Repo.rollback({:topic_failed, name, changeset})
    end
  end

  defp empty_acc do
    %{importable: [], skipped: [], warnings: [], seen: MapSet.new()}
  end

  defp decode(json) do
    case Jason.decode(json) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, error} ->
        {:error, ["Kein gültiges JSON: #{Exception.message(error)}"]}
    end
  end

  defp fetch_quizzes(%{"quizzes" => quizzes}) when is_list(quizzes) and quizzes != [] do
    {:ok, quizzes}
  end

  defp fetch_quizzes(_decoded) do
    {:error, [~s(Der JSON muss ein Objekt mit einem nicht-leeren Array "quizzes" sein.)]}
  end

  defp build_topic(quiz, existing, acc) when is_map(quiz) do
    name = quiz |> Map.get("topic") |> clean_string()

    cond do
      is_nil(name) ->
        add_skip(acc, "—", "Themenname fehlt oder ist leer.")

      MapSet.member?(acc.seen, name) ->
        add_skip(acc, name, "Thema kommt mehrfach in dieser Datei vor.")

      MapSet.member?(existing, name) ->
        add_skip(acc, name, "Thema existiert bereits – nicht überschrieben.")

      true ->
        build_questions(acc, name, Map.get(quiz, "questions"))
    end
  end

  defp build_topic(_quiz, _existing, acc) do
    add_skip(acc, "—", "Eintrag ist kein Objekt.")
  end

  defp build_questions(acc, name, questions) when is_list(questions) and questions != [] do
    scanned =
      questions
      |> Enum.with_index(1)
      |> Enum.reduce(%{questions: [], errors: [], warnings: []}, fn {question, index}, tmp ->
        case normalize_question(question, index) do
          {:ok, attrs, warnings} ->
            %{
              tmp
              | questions: [attrs | tmp.questions],
                warnings: tmp.warnings ++ warnings
            }

          {:error, errors} ->
            %{tmp | errors: tmp.errors ++ errors}
        end
      end)

    cond do
      scanned.errors != [] ->
        reason = "Ungültige Fragen: " <> Enum.join(scanned.errors, " ")
        add_skip(acc, name, reason)

      scanned.questions == [] ->
        add_skip(acc, name, "Keine Fragen gefunden.")

      true ->
        topic = %{name: name, questions: Enum.reverse(scanned.questions)}

        warnings =
          Enum.map(scanned.warnings, fn warning ->
            Map.merge(%{topic: name}, warning)
          end)

        %{
          acc
          | importable: [topic | acc.importable],
            warnings: acc.warnings ++ warnings,
            seen: MapSet.put(acc.seen, name)
        }
    end
  end

  defp build_questions(acc, name, _questions) do
    add_skip(acc, name, "Feld \"questions\" fehlt oder ist leer.")
  end

  defp normalize_question(question, index) when is_map(question) do
    number = question |> Map.get("number") |> clean_string() || index
    label = "Frage #{number}"

    with {:ok, prompt} <- normalize_prompt(question, label),
         {:ok, letters} <- normalize_answers(question, label),
         {:ok, correct_index, warnings} <- normalize_correct_answer(question, letters, label) do
      options =
        letters
        |> Enum.map(fn letter ->
          %{
            "text" =>
              question |> Map.get("answers") |> Map.get(letter) |> to_string() |> String.trim()
          }
        end)

      attrs = %{
        "prompt" => prompt,
        "options" => options,
        "correct_index" => correct_index,
        "status" => @draft_status
      }

      {:ok, attrs, warnings}
    else
      {:error, errors} -> {:error, errors}
    end
  end

  defp normalize_question(_question, index) do
    {:error, ["Frage #{index} ist kein Objekt."]}
  end

  defp normalize_prompt(question, label) do
    case question |> Map.get("question") |> clean_string() do
      nil ->
        {:error, ["#{label}: Fragetext fehlt oder ist leer."]}

      prompt when byte_size(prompt) > @max_prompt_length ->
        {:error, ["#{label}: Fragetext ist länger als #{@max_prompt_length} Zeichen."]}

      prompt ->
        {:ok, prompt}
    end
  end

  defp normalize_answers(question, label) do
    case Map.get(question, "answers") do
      answers when is_map(answers) and map_size(answers) > 0 ->
        letters =
          answers
          |> Map.keys()
          |> Enum.sort()

        texts = Enum.map(letters, fn letter -> answers |> Map.get(letter) |> clean_string() end)

        cond do
          length(letters) < @min_options ->
            {:error, ["#{label}: Es müssen mindestens #{@min_options} Antworten vorhanden sein."]}

          length(letters) > @max_options ->
            {:error, ["#{label}: Es dürfen höchstens #{@max_options} Antworten vorhanden sein."]}

          Enum.any?(texts, &is_nil/1) ->
            {:error, ["#{label}: Jede Antwort muss einen Text haben."]}

          true ->
            {:ok, letters}
        end

      _ ->
        {:error, ["#{label}: Feld \"answers\" fehlt oder ist leer."]}
    end
  end

  defp normalize_correct_answer(question, letters, label) do
    case Map.get(question, "correct_answer") do
      nil ->
        {:ok, 0,
         [
           %{
             question: label,
             message:
               "Richtige Antwort fehlt – als Entwurf mit Antwort A vorausgewählt importiert."
           }
         ]}

      answer when is_binary(answer) ->
        answer = String.trim(answer)

        case Enum.find_index(letters, &(&1 == answer)) do
          nil ->
            {:error, ["#{label}: correct_answer \"#{answer}\" ist keine der Antworten."]}

          index ->
            {:ok, index, []}
        end

      _ ->
        {:error, ["#{label}: correct_answer ist ungültig."]}
    end
  end

  defp add_skip(acc, name, reason) do
    seen = if name == "—", do: acc.seen, else: MapSet.put(acc.seen, name)
    %{acc | skipped: acc.skipped ++ [%{name: name, reason: reason}], seen: seen}
  end

  defp clean_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp clean_string(_value), do: nil
end
