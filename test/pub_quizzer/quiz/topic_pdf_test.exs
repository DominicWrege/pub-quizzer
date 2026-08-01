defmodule PubQuizzer.Quiz.TopicPdfTest do
  use ExUnit.Case, async: true

  alias PubQuizzer.Quiz.{Question, Topic, TopicPdf}

  defp topic(attrs \\ %{}) do
    struct(
      Topic,
      Map.merge(%{id: 1, name: "Erdkunde", description: "Rund um die Welt"}, attrs)
    )
  end

  defp question(attrs \\ %{}) do
    struct(
      Question,
      Map.merge(
        %{
          id: 1,
          position: 0,
          prompt: "Was ist die Hauptstadt von Deutschland?",
          options: [%{"text" => "Berlin"}, %{"text" => "München"}, %{"text" => "Hamburg"}],
          correct_index: 0,
          status: "published",
          image: nil
        },
        attrs
      )
    )
  end

  test "renders a valid PDF binary" do
    pdf = TopicPdf.render(topic(), [question()])

    assert is_binary(pdf)
    assert binary_part(pdf, 0, 5) == "%PDF-"
    assert :binary.match(pdf, "%%EOF") != :nomatch
  end

  test "renders umlauts and strips characters outside WinAnsi" do
    questions = [
      question(%{
        prompt: "Größe der Straße in € 🎉",
        options: [%{"text" => "füße"}, %{"text" => "x"}],
        correct_index: 0
      })
    ]

    pdf = TopicPdf.render(topic(%{name: "Spaß 🎉"}), questions)
    assert binary_part(pdf, 0, 5) == "%PDF-"
  end

  test "paginates across multiple pages for many questions" do
    questions =
      for i <- 1..60 do
        question(%{
          id: i,
          position: i,
          prompt: "Frage #{i} mit einem etwas längeren Text, der Platz verbraucht."
        })
      end

    pdf = TopicPdf.render(topic(), questions)

    pages = pdf |> then(&Regex.scan(~r{/Type /Page(?!s)}, &1)) |> length()
    assert pages > 1
  end

  test "renders a topic with no questions" do
    pdf = TopicPdf.render(topic(), [])
    assert binary_part(pdf, 0, 5) == "%PDF-"
  end

  test "accepts string options as well as option maps" do
    questions = [question(%{options: ["Berlin", "Bonn"], correct_index: 1})]
    pdf = TopicPdf.render(topic(), questions)
    assert binary_part(pdf, 0, 5) == "%PDF-"
  end
end
