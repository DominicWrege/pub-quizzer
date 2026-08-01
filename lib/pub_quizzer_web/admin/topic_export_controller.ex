defmodule PubQuizzerWeb.Admin.TopicExportController do
  use PubQuizzerWeb, :controller

  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.TopicPdf

  def export(conn, %{"id" => id}) do
    topic = Quiz.get_topic!(id)
    questions = Quiz.list_questions_for_topic(topic.id)
    pdf = TopicPdf.render(topic, questions)

    conn
    |> put_resp_content_type("application/pdf")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename(topic)}"))
    |> send_resp(200, pdf)
  end

  defp filename(topic) do
    slug =
      topic.name
      |> String.downcase()
      |> String.replace(~r/[äöüß]/u, fn
        "ä" -> "ae"
        "ö" -> "oe"
        "ü" -> "ue"
        "ß" -> "ss"
      end)
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")

    slug = if slug == "", do: Integer.to_string(topic.id), else: slug
    "thema-#{slug}.pdf"
  end
end
