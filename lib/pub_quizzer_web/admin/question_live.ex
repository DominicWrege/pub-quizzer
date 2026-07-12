defmodule PubQuizzerWeb.Admin.QuestionLive do
  use PubQuizzerWeb, :live_view

  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.Question
  embed_templates "question_live/*"

  @upload_dir "priv/static/uploads"

  @impl true
  def render(assigns) do
    index(assigns)
  end

  @impl true
  def mount(%{"topic_id" => topic_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:topic, Quiz.get_topic!(topic_id))
     |> assign(:confirm_action, nil)
     |> assign(:pending_delete_id, nil)
     |> assign(:editing_question_id, nil)
     |> assign(:image_preview_url, nil)
     |> assign(:search, "")
     |> allow_upload(:image,
       accept: ~w(.jpg .jpeg .png .gif .webp),
       max_entries: 1,
       max_file_size: 5_000_000
     )}
  end

  @impl true
  def handle_params(%{"search" => search}, _url, socket) when search != "" do
    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:page_title, "Fragen")
     |> stream(:questions, Quiz.search_questions_for_topic(socket.assigns.topic.id, search))}
  end

  def handle_params(_params, _url, socket) do
    {:noreply,
     socket
     |> assign(:search, "")
     |> assign(:page_title, "Fragen")
     |> stream(:questions, Quiz.list_questions_for_topic(socket.assigns.topic.id))}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/topics/#{socket.assigns.topic.id}/questions?search=#{search}")}
  end

  @impl true
  def handle_event("start_new", _params, socket) do
    changeset =
      Question.changeset(%Question{options: ["", "", "", ""]}, %{})

    {:noreply,
     socket
     |> assign(:editing_question_id, :new)
     |> assign(:form, to_form(changeset))
     |> assign(:image_preview_url, nil)}
  end

  def handle_event("start_edit", %{"id" => id}, socket) do
    question = Quiz.get_question!(String.to_integer(id))
    changeset = Question.changeset(question, %{})

    {:noreply,
     socket
     |> assign(:editing_question_id, question.id)
     |> assign(:form, to_form(changeset))
     |> assign(:question, question)
     |> assign(:image_preview_url, nil)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_question_id, nil)
     |> assign(:image_preview_url, nil)}
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

    save_question(socket, socket.assigns.editing_question_id, question_params)
  end

  def handle_event("validate", params, socket) do
    question_params = normalize_params(params)

    changeset =
      case socket.assigns.editing_question_id do
        :new -> Question.changeset(%Question{options: ["", "", "", ""]}, question_params)
        _id -> Question.changeset(socket.assigns.question, question_params)
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

  defp save_question(socket, :new, question_params) do
    question_params = Map.put(question_params, "topic_id", socket.assigns.topic.id)

    case Quiz.create_question(question_params) do
      {:ok, _question} ->
        {:noreply,
         socket
         |> assign(:editing_question_id, nil)
         |> assign(:image_preview_url, nil)
         |> restream_questions()
         |> put_flash(:info, "Frage erstellt.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}
    end
  end

  defp save_question(socket, id, question_params) when is_integer(id) do
    case Quiz.update_question(socket.assigns.question, question_params) do
      {:ok, _question} ->
        {:noreply,
         socket
         |> assign(:editing_question_id, nil)
         |> assign(:image_preview_url, nil)
         |> restream_questions()
         |> put_flash(:info, "Frage aktualisiert.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}
    end
  end
end
