defmodule PubQuizzerWeb.Admin.QuestionLive do
  use PubQuizzerWeb, :live_view

  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.Question
  embed_templates "question_live/*"

  @upload_dir "priv/static/uploads"

  @impl true
  def render(assigns) do
    case assigns.live_action do
      :index -> index(assigns)
      :new -> new(assigns)
      :edit -> edit(assigns)
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:confirm_action, nil)
     |> assign(:pending_delete_id, nil)
     |> assign(:search, "")
     |> allow_upload(:image,
       accept: ~w(.jpg .jpeg .png .gif .webp),
       max_entries: 1,
       max_file_size: 5_000_000
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, %{"topic_id" => topic_id}) do
    topic = Quiz.get_topic!(topic_id)

    socket
    |> assign(:topic, topic)
    |> assign(:page_title, "Fragen")
    |> stream(:questions, Quiz.list_questions_for_topic(topic.id))
  end

  defp apply_action(socket, :new, %{"topic_id" => topic_id}) do
    topic = Quiz.get_topic!(topic_id)
    changeset = Question.changeset(%Question{options: ["", "", "", ""]}, %{})

    socket
    |> assign(:topic, topic)
    |> assign(:page_title, "Neue Frage")
    |> assign(:form, to_form(changeset))
    |> assign(:image_preview_url, nil)
  end

  defp apply_action(socket, :edit, %{"topic_id" => topic_id, "id" => id}) do
    topic = Quiz.get_topic!(topic_id)
    question = Quiz.get_question!(id)
    changeset = Question.changeset(question, %{})

    socket
    |> assign(:topic, topic)
    |> assign(:question, question)
    |> assign(:page_title, "Frage bearbeiten")
    |> assign(:form, to_form(changeset))
    |> assign(:image_preview_url, nil)
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    questions =
      if search == "" do
        Quiz.list_questions_for_topic(socket.assigns.topic.id)
      else
        Quiz.search_questions_for_topic(socket.assigns.topic.id, search)
      end

    {:noreply,
     socket
     |> assign(:search, search)
     |> stream(:questions, questions, reset: true)}
  end

  def handle_event("ask_delete", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:confirm_action, :delete_question)
     |> assign(:pending_delete_id, String.to_integer(id))}
  end

  def handle_event("confirm_delete", _params, socket) do
    question = Quiz.get_question!(socket.assigns.pending_delete_id)
    {:ok, _} = Quiz.delete_question(question)

    {:noreply,
     socket
     |> assign(:confirm_action, nil)
     |> assign(:pending_delete_id, nil)
     |> restream_questions()
     |> put_flash(:info, "Frage gelöscht.")}
  end

  def handle_event("cancel_confirm", _params, socket) do
    {:noreply, socket |> assign(:confirm_action, nil) |> assign(:pending_delete_id, nil)}
  end

  def handle_event("save", params, socket) do
    question_params = normalize_params(params)

    image_path =
      consume_uploaded_entries(socket, :image, fn %{path: tmp_path}, entry ->
        ext = extname(entry.client_name)
        filename = "#{System.unique_integer([:positive, :monotonic])}#{ext}"
        dest = Path.join(@upload_dir, filename)

        File.mkdir_p!(@upload_dir)
        File.cp!(tmp_path, dest)

        {:ok, "/uploads/#{filename}"}
      end)
      |> List.first()

    question_params =
      if image_path do
        Map.put(question_params, "image", image_path)
      else
        question_params
      end

    save_question(socket, question_params)
  end

  def handle_event("validate", params, socket) do
    question_params = normalize_params(params)
    question = Map.get(socket.assigns, :question)

    changeset =
      case question do
        nil -> Question.changeset(%Question{options: ["", "", "", ""]}, question_params)
        _ -> Question.changeset(question, question_params)
      end

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply,
     socket
     |> cancel_upload(:image, ref)
     |> assign(:image_preview_url, nil)}
  end

  def handle_event("image_preview", %{"data_url" => data_url}, socket) do
    {:noreply, assign(socket, :image_preview_url, data_url)}
  end

  defp normalize_params(%{"question" => q}) do
    q
    |> Map.update("options", [], fn opts ->
      normalize_options(opts)
    end)
    |> Map.update("correct_index", nil, fn
      nil -> nil
      v -> String.to_integer(v)
    end)
  end

  defp normalize_params(%{"prompt" => _, "options" => _} = params) do
    params
  end

  defp normalize_options(opts) when is_list(opts) do
    opts
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  defp normalize_options(opts) when is_map(opts) do
    opts
    |> Map.values()
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  defp extname(filename) do
    filename |> Path.extname() |> String.downcase()
  end

  defp restream_questions(socket) do
    questions =
      if socket.assigns.search == "" do
        Quiz.list_questions_for_topic(socket.assigns.topic.id)
      else
        Quiz.search_questions_for_topic(socket.assigns.topic.id, socket.assigns.search)
      end

    stream(socket, :questions, questions, reset: true)
  end

  defp save_question(socket, question_params) do
    question = Map.get(socket.assigns, :question)
    topic_id = socket.assigns.topic.id

    {result, action} =
      case question do
        nil ->
          {Quiz.create_question(Map.put(question_params, "topic_id", topic_id)), :insert}

        q ->
          {Quiz.update_question(q, question_params), :insert}
      end

    case result do
      {:ok, _question} ->
        flash = if question, do: "Frage aktualisiert.", else: "Frage erstellt."

        {:noreply,
         socket
         |> assign(:image_preview_url, nil)
         |> put_flash(:info, flash)
         |> push_navigate(to: ~p"/admin/topics/#{topic_id}/questions")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: action))}
    end
  end
end
