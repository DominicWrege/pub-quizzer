defmodule PubQuizzerWeb.Admin.QuestionReportLive do
  use PubQuizzerWeb, :live_view

  alias PubQuizzer.Quiz

  @impl true
  def mount(_params, _session, socket) do
    entries = Quiz.get_question_report()

    topics =
      entries
      |> Enum.map(&{&1.topic_id, &1.topic_name})
      |> Enum.uniq()
      |> Enum.sort_by(&elem(&1, 1))

    {:ok,
     socket
     |> assign(:page_title, "Fragen-Bericht")
     |> assign(:entries, entries)
     |> assign(:topics, topics)
     |> assign(:topic_filter, "")
     |> assign(:sort_key, "right")
     |> assign(:sort_dir, :asc)
     |> assign_rows(entries, "", "right", :asc)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    topic_filter = Map.get(params, "topic_id", "")

    {:noreply,
     socket
     |> assign(:topic_filter, topic_filter)
     |> assign_rows(
       socket.assigns.entries,
       topic_filter,
       socket.assigns.sort_key,
       socket.assigns.sort_dir
     )}
  end

  @impl true
  def handle_event("sort", %{"key" => key}, socket) do
    {key, dir} =
      if socket.assigns.sort_key == key do
        {key, if(socket.assigns.sort_dir == :asc, do: :desc, else: :asc)}
      else
        {key, default_dir(key)}
      end

    {:noreply,
     socket
     |> assign(:sort_key, key)
     |> assign(:sort_dir, dir)
     |> assign_rows(socket.assigns.entries, socket.assigns.topic_filter, key, dir)}
  end

  defp default_dir("right"), do: :asc
  defp default_dir("name"), do: :asc
  defp default_dir(_key), do: :desc

  defp assign_rows(socket, entries, topic_filter, sort_key, sort_dir) do
    rows =
      entries
      |> Enum.filter(fn entry ->
        topic_filter == "" or to_string(entry.topic_id) == topic_filter
      end)
      |> sort_entries(sort_key, sort_dir)

    assign(socket, :rows, rows)
  end

  defp sort_entries(entries, key, dir) do
    key_fun =
      case key do
        "name" -> fn e -> String.downcase(e.question.prompt) end
        "asked" -> fn e -> e.asked_in end
        "answers" -> fn e -> e.answers end
        "wrong" -> fn e -> e.answers - e.correct end
        "right" -> fn e -> e.pct end
      end

    sorted = Enum.sort_by(entries, key_fun)
    if dir == :desc, do: Enum.reverse(sorted), else: sorted
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      max_width="max-w-7xl"
    >
      <.header>
        <div class="flex items-baseline gap-2 sm:gap-3 flex-wrap">
          <span>Fragen-Bericht</span>
          <span class="text-sm text-base-content/70 whitespace-nowrap">
            {length(@entries)} Fragen aus allen abgeschlossenen Quiz
          </span>
        </div>
        <:back>
          <.link navigate={~p"/admin/events"} class="btn btn-sm btn-soft">
            <.icon name="hero-chevron-left" class="size-4" /> Zurück
          </.link>
        </:back>
      </.header>

      <div id="question-report-filters" class="mb-4">
        <form phx-change="filter" id="question-report-filter-form" class="flex flex-wrap gap-2">
          <select name="topic_id" class="select select-sm select-bordered">
            <option value="" selected={@topic_filter == ""}>Alle Themen</option>
            <option
              :for={{id, name} <- @topics}
              value={id}
              selected={@topic_filter == to_string(id)}
            >
              {name}
            </option>
          </select>
        </form>
      </div>

      <div class="overflow-x-auto rounded-lg border-2 border-base-300">
        <table class="table table-sm">
          <thead>
            <tr class="border-b-2 border-base-300 bg-base-300">
              <th class="px-4 py-3">
                <.sort_button label="Frage" key="name" sort_key={@sort_key} sort_dir={@sort_dir} />
              </th>
              <th class="px-4 py-3 text-center">
                <.sort_button label="Gefragt" key="asked" sort_key={@sort_key} sort_dir={@sort_dir} />
              </th>
              <th class="px-4 py-3 text-center">
                <.sort_button
                  label="Antworten"
                  key="answers"
                  sort_key={@sort_key}
                  sort_dir={@sort_dir}
                />
              </th>
              <th class="px-4 py-3 text-center">
                <.sort_button label="Falsch" key="wrong" sort_key={@sort_key} sort_dir={@sort_dir} />
              </th>
              <th class="px-4 py-3 text-center">
                <.sort_button label="Richtig" key="right" sort_key={@sort_key} sort_dir={@sort_dir} />
              </th>
              <th class="px-4 py-3 min-w-[200px]">Verteilung</th>
              <th class="px-4 py-3">Falle</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-base-300">
            <tr :if={@rows == []} id="question-report-empty" class="bg-base-200">
              <td colspan="7" class="px-4 py-6 text-center text-base-content/70">
                Keine Fragen aus abgeschlossenen Quiz gefunden.
              </td>
            </tr>
            <tr
              :for={entry <- @rows}
              id={"question-report-#{entry.question.id}"}
              class="bg-base-200 hover:bg-base-300/60"
            >
              <td class="px-4 py-3">
                <div class="font-medium">{entry.question.prompt}</div>
                <div class="text-xs text-base-content/60">{entry.topic_name}</div>
              </td>
              <td class="px-4 py-3 text-center font-mono">{entry.asked_in}×</td>
              <td class="px-4 py-3 text-center font-mono">{entry.answers}</td>
              <td class="px-4 py-3 text-center font-mono text-base-content/70">
                {entry.answers - entry.correct}
              </td>
              <td class="px-4 py-3 text-center">
                <span class={[
                  "font-mono font-bold",
                  entry.pct < 40 && "text-error",
                  (entry.pct >= 40 and entry.pct < 70) && "text-base-content/70",
                  entry.pct >= 70 && "text-success"
                ]}>
                  {entry.pct} %
                </span>
              </td>
              <td class="px-4 py-3">
                <div class="flex h-6 w-full overflow-hidden rounded-md border border-base-300 bg-base-200">
                  <%= for {idx, count} <- Enum.sort(entry.picks), count > 0 do %>
                    <div
                      data-correct={to_string(idx == entry.question.correct_index)}
                      class={[
                        "flex items-center justify-center overflow-hidden whitespace-nowrap text-xs font-semibold",
                        idx == entry.question.correct_index && "bg-success text-success-content",
                        idx != entry.question.correct_index && "bg-base-300 text-base-content/80"
                      ]}
                      style={"width: #{segment_pct(count, entry.answers)}%"}
                      title={"#{letter_for_index(idx)}: #{count}×"}
                    >
                      {letter_for_index(idx)} · {count}
                    </div>
                  <% end %>
                </div>
              </td>
              <td class="px-4 py-3 text-sm">
                <%= if entry.trap do %>
                  <% {idx, count} = entry.trap %>
                  <span class="font-mono font-bold">{letter_for_index(idx)}</span>
                  <span class="text-base-content/60">· {count}×</span>
                <% else %>
                  <span class="text-base-content/50">—</span>
                <% end %>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :key, :string, required: true
  attr :sort_key, :string, required: true
  attr :sort_dir, :atom, required: true

  defp sort_button(assigns) do
    ~H"""
    <button
      type="button"
      id={"sort-#{@key}"}
      phx-click="sort"
      phx-value-key={@key}
      class={[
        "inline-flex items-center gap-1 transition-colors",
        @sort_key == @key && "text-base-content underline underline-offset-4",
        @sort_key != @key && "hover:text-base-content/90"
      ]}
      aria-sort={if @sort_key == @key, do: to_string(@sort_dir), else: "none"}
    >
      {@label}
      <span class="text-xs w-3">
        <%= cond do %>
          <% @sort_key == @key and @sort_dir == :asc -> %>
            ↑
          <% @sort_key == @key and @sort_dir == :desc -> %>
            ↓
          <% true -> %>
        <% end %>
      </span>
    </button>
    """
  end

  defp segment_pct(_count, 0), do: 0

  defp segment_pct(count, total) do
    Float.round(count / total * 100, 2)
  end
end
