defmodule PubQuizzerWeb.Admin.TopicExportControllerTest do
  use PubQuizzerWeb.ConnCase, async: false

  alias PubQuizzer.Quiz

  setup do
    {:ok, topic} = Quiz.create_topic(%{name: "Erdkunde", description: "Welt"})

    {:ok, _question} =
      Quiz.create_question(%{
        prompt: "Hauptstadt von Deutschland?",
        options: ["Berlin", "Bonn"],
        correct_index: 0,
        topic_id: topic.id
      })

    %{topic: topic}
  end

  test "moderator downloads the topic as a PDF", %{conn: conn, topic: topic} do
    conn = conn |> log_in_user() |> get(~p"/admin/topics/#{topic}/export")

    assert body = response(conn, 200)
    assert binary_part(body, 0, 5) == "%PDF-"

    assert [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "application/pdf"

    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "attachment"
    assert disposition =~ "thema-erdkunde.pdf"
  end

  test "transliterates umlauts in the filename", %{conn: conn} do
    {:ok, topic} = Quiz.create_topic(%{name: "Spaß & Spiele"})

    conn = conn |> log_in_user() |> get(~p"/admin/topics/#{topic}/export")

    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "thema-spass-spiele.pdf"
  end

  test "unauthenticated request redirects to login", %{conn: conn, topic: topic} do
    conn = get(conn, ~p"/admin/topics/#{topic}/export")
    assert redirected_to(conn) == "/admin/login"
  end
end
