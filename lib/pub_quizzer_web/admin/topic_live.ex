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
    {:ok,
     socket
     |> assign(:topics, Quiz.list_topics())
     |> assign(:editing_topic_id, nil)
     |> assign(:form, nil)
     |> assign(:topic, nil)
     |> assign(:confirm_action, nil)
     |> assign(:pending_delete_id, nil)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply,
     socket
     |> assign(:page_title, "Themen")
     |> assign(:topics, Quiz.list_topics())}
  end

  @impl true
  def handle_event("start_edit", %{"id" => id}, socket) do
    topic = Quiz.get_topic!(id)

    {:noreply,
     socket
     |> assign(:editing_topic_id, topic.id)
     |> assign(:topic, topic)
     |> assign(:form, to_form(Topic.changeset(topic, %{})))}
  end

  def handle_event("start_new", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_topic_id, :new)
     |> assign(:topic, nil)
     |> assign(:form, to_form(Topic.changeset(%Topic{}, %{})))}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_topic_id, nil)
     |> assign(:topic, nil)
     |> assign(:form, nil)}
  end

  def handle_event("ask_delete", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:confirm_action, :delete_topic)
     |> assign(:pending_delete_id, String.to_integer(id))}
  end

  def handle_event("confirm_delete", _params, socket) do
    topic = Quiz.get_topic!(socket.assigns.pending_delete_id)
    {:ok, _} = Quiz.delete_topic(topic)

    {:noreply,
     socket
     |> assign(:confirm_action, nil)
     |> assign(:pending_delete_id, nil)
     |> assign(:editing_topic_id, nil)
     |> assign(:topic, nil)
     |> assign(:form, nil)
     |> assign(:topics, Quiz.list_topics())
     |> put_flash(:info, "Thema gelöscht.")}
  end

  def handle_event("cancel_confirm", _params, socket) do
    {:noreply, socket |> assign(:confirm_action, nil) |> assign(:pending_delete_id, nil)}
  end

  def handle_event("save", %{"topic" => topic_params}, socket) do
    save_topic(socket, socket.assigns.editing_topic_id, topic_params)
  end

  def handle_event("validate", %{"topic" => topic_params}, socket) do
    changeset =
      case socket.assigns.editing_topic_id do
        :new -> Topic.changeset(%Topic{}, topic_params)
        id when is_integer(id) -> Topic.changeset(socket.assigns.topic, topic_params)
        _ -> Topic.changeset(%Topic{}, topic_params)
      end

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    topic = Quiz.get_topic!(id)

    case Quiz.toggle_topic_enabled(topic) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:topics, Quiz.list_topics())
         |> put_flash(
           :info,
           if(!topic.enabled, do: "Thema aktiviert.", else: "Thema deaktiviert.")
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Status konnte nicht geändert werden.")}
    end
  end

  defp save_topic(socket, :new, topic_params) do
    case Quiz.create_topic(topic_params) do
      {:ok, _topic} ->
        {:noreply,
         socket
         |> assign(:editing_topic_id, nil)
         |> assign(:topic, nil)
         |> assign(:form, nil)
         |> assign(:topics, Quiz.list_topics())
         |> put_flash(:info, "Thema erstellt.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}
    end
  end

  defp save_topic(socket, id, topic_params) when is_integer(id) do
    case Quiz.update_topic(socket.assigns.topic, topic_params) do
      {:ok, _topic} ->
        {:noreply,
         socket
         |> assign(:editing_topic_id, nil)
         |> assign(:topic, nil)
         |> assign(:form, nil)
         |> assign(:topics, Quiz.list_topics())
         |> put_flash(:info, "Thema aktualisiert.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}
    end
  end
end
