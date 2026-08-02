defmodule PubQuizzerWeb.Admin.TopicLive do
  use PubQuizzerWeb, :live_view

  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.Topic

  embed_templates "topic_live/*"

  @impl true
  def render(assigns) do
    index(assigns)
  end

  @impl true
  def mount(_params, _session, socket) do
    topics = Quiz.list_topics()

    {:ok,
     socket
     |> assign(:topics, topics)
     |> assign(:search_query, "")
     |> assign(:filtered_topics, topics)
     |> assign(:editing_topic_id, nil)
     |> assign(:form, nil)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :page_title, "Themen")}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    topics = socket.assigns.topics
    query = String.trim(query)

    filtered =
      if query == "" do
        topics
      else
        Enum.filter(topics, fn t ->
          String.contains?(String.downcase(t.name), String.downcase(query)) or
            (t.description &&
               String.contains?(String.downcase(t.description), String.downcase(query)))
        end)
      end

    {:noreply, socket |> assign(:filtered_topics, filtered) |> assign(:search_query, query)}
  end

  def handle_event("start_new", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_topic_id, :new)
     |> assign(:form, to_form(Topic.changeset(%Topic{}, %{})))}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_topic_id, nil)
     |> assign(:form, nil)}
  end

  def handle_event("save", %{"topic" => topic_params}, socket) do
    save_topic(socket, socket.assigns.editing_topic_id, topic_params)
  end

  defp save_topic(socket, :new, topic_params) do
    case Quiz.create_topic(topic_params) do
      {:ok, _topic} ->
        {:noreply,
         socket
         |> assign(:editing_topic_id, nil)
         |> assign(:form, nil)
         |> assign_topics()
         |> put_flash(:info, "Thema erstellt.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}
    end
  end

  defp assign_topics(socket) do
    topics = Quiz.list_topics()

    socket
    |> assign(:topics, topics)
    |> assign(:filtered_topics, topics)
    |> assign(:search_query, "")
  end
end
