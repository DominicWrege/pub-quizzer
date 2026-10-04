defmodule PubQuizzerWeb.Admin.QuestionReportLive do
  use PubQuizzerWeb, :live_view

  alias PubQuizzer.Quiz

  @impl true
  def mount(_params, _session, socket) do
    entries = Quiz.get_question_report()
    events = Enum.filter(Quiz.list_events(), &(&1.status == "finished"))

    topics =
      entries
      |> Enum.map(&{&1.topic_id, &1.topic_name})
      |> Enum.uniq()
      |> Enum.sort_by(&elem(&1, 1))

    {:ok,
     socket
     |> assign(:page_title, "Fragen-Bericht")
     |> assign(:entries, entries)
     |> assign(:events, events)
     |> assign(:event_filter, "")
     |> assign(:quiz_form, to_form(%{"event_id" => ""}))
     |> assign(:topic_form, to_form(%{"topic_id" => ""}))
     |> assign(:topics, topics)
     |> assign(:topic_filter, "")
     |> assign(:sort_key, "right")
     |> assign(:sort_dir, :asc)
     |> assign(:question_details, nil)
     |> stream_configure(:rows, dom_id: &"question-report-#{&1.question.id}")
     |> assign_rows(entries, "", "right", :asc)}
  end

  @impl true
  def handle_event("select_quiz", %{"event_id" => event_id}, socket) do
    event_filter =
      if Enum.any?(socket.assigns.events, &(to_string(&1.id) == event_id)),
        do: event_id,
        else: ""

    entries = Quiz.get_question_report(if event_filter != "", do: event_filter)

    {:noreply,
     socket
     |> assign(:event_filter, event_filter)
     |> assign(:quiz_form, to_form(%{"event_id" => event_filter}))
     |> assign(:entries, entries)
     |> assign(:question_details, nil)
     |> assign_rows(
       entries,
       socket.assigns.topic_filter,
       socket.assigns.sort_key,
       socket.assigns.sort_dir
     )}
  end

  def handle_event("filter", params, socket) do
    topic_filter = Map.get(params, "topic_id", "")

    {sort_key, sort_dir} =
      cond do
        topic_filter != "" -> {"question", :asc}
        socket.assigns.sort_key == "question" -> {"right", :asc}
        true -> {socket.assigns.sort_key, socket.assigns.sort_dir}
      end

    {:noreply,
     socket
     |> assign(:topic_filter, topic_filter)
     |> assign(:sort_key, sort_key)
     |> assign(:sort_dir, sort_dir)
     |> assign(:question_details, nil)
     |> assign(:topic_form, to_form(%{"topic_id" => topic_filter}))
     |> assign_rows(
       socket.assigns.entries,
       topic_filter,
       sort_key,
       sort_dir
     )}
  end

  @impl true
  def handle_event("show_question", %{"id" => id}, socket) do
    entry = Enum.find(socket.assigns.entries, &(to_string(&1.question.id) == id))
    {:noreply, assign(socket, :question_details, entry)}
  end

  def handle_event("close_question", _params, socket) do
    {:noreply, assign(socket, :question_details, nil)}
  end

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
  defp default_dir("question"), do: :asc
  defp default_dir(_key), do: :desc

  defp assign_rows(socket, entries, topic_filter, sort_key, sort_dir) do
    rows =
      entries
      |> Enum.filter(fn entry ->
        topic_filter == "" or to_string(entry.topic_id) == topic_filter
      end)
      |> sort_entries(sort_key, sort_dir)

    socket
    |> assign(:rows_empty?, rows == [])
    |> assign(:highlights, question_highlights(rows))
    |> stream(:rows, rows, reset: true)
  end

  defp question_highlights(rows) do
    rated = Enum.filter(rows, &(&1.answers > 0))

    %{
      hardest: Enum.min_by(rated, &{&1.pct, &1.question.id}, &<=/2, fn -> nil end),
      easiest: Enum.min_by(rated, &{-&1.pct, &1.question.id}, &<=/2, fn -> nil end),
      trap:
        rated
        |> Enum.filter(&(&1.trap != nil))
        |> Enum.min_by(&{-elem(&1.trap, 1), &1.question.id}, &<=/2, fn -> nil end)
    }
  end

  defp sort_entries(entries, key, dir) do
    key_fun =
      case key do
        "question" -> fn e -> {e.question.position, e.question.id} end
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
      <div id="question-report-toolbar" class="space-y-1">
        <.header inline_actions>
          Fragen-Bericht
        </.header>

        <div
          id="question-report-filters"
          class="mb-4 flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-center"
        >
          <.form
            for={@quiz_form}
            phx-change="select_quiz"
            id="question-report-quiz-form"
            class="w-full sm:w-auto"
          >
            <.input
              field={@quiz_form[:event_id]}
              id="question-report-quiz"
              type="select"
              aria-label="Quiz auswählen"
              options={[
                {"Alle abgeschlossenen Quiz", ""} | Enum.map(@events, &{event_label(&1), &1.id})
              ]}
              class="select min-h-11 w-full sm:w-80"
            />
          </.form>
          <.form
            for={@topic_form}
            phx-change="filter"
            id="question-report-filter-form"
            class="w-full sm:w-auto"
          >
            <.input
              field={@topic_form[:topic_id]}
              id="question-report-topic"
              type="select"
              aria-label="Thema filtern"
              options={[{"Alle Themen", ""} | Enum.map(@topics, fn {id, name} -> {name, id} end)]}
              class="select min-h-11 w-full sm:w-64"
            />
          </.form>
          <div class="flex items-center gap-2 lg:hidden">
            <form id="question-report-mobile-sort" phx-change="sort" class="min-w-0 flex-1">
              <select
                name="key"
                aria-label="Sortieren nach"
                class="select min-h-11 w-full"
              >
                <option :if={@topic_filter != ""} value="question" selected={@sort_key == "question"}>
                  Fragenummer
                </option>
                <option value="asked" selected={@sort_key == "asked"}>Gefragt</option>
                <option value="answers" selected={@sort_key == "answers"}>Antworten</option>
                <option value="wrong" selected={@sort_key == "wrong"}>Falsch</option>
                <option value="right" selected={@sort_key == "right"}>Richtig</option>
              </select>
            </form>
            <button
              type="button"
              id="question-report-sort-direction"
              class="btn min-h-11"
              phx-click="sort"
              phx-value-key={@sort_key}
              aria-label="Sortierreihenfolge umkehren"
            >
              <span aria-hidden="true">{if @sort_dir == :asc, do: "↑", else: "↓"}</span>
              {if @sort_dir == :asc, do: "Aufsteigend", else: "Absteigend"}
            </button>
          </div>
        </div>
      </div>

      <section
        :if={!@rows_empty?}
        id="question-report-highlights"
        aria-label="Zusammenfassung"
        class="grid gap-3 sm:grid-cols-3"
      >
        <.highlight_card
          id="question-report-hardest"
          label="Schwerste Frage"
          entry={@highlights.hardest}
          value={if @highlights.hardest, do: "#{@highlights.hardest.pct} % richtig"}
        />
        <.highlight_card
          id="question-report-easiest"
          label="Leichteste Frage"
          entry={@highlights.easiest}
          value={if @highlights.easiest, do: "#{@highlights.easiest.pct} % richtig"}
        />
        <.highlight_card
          id="question-report-trap"
          label="Beliebteste Falle"
          entry={@highlights.trap}
          value={trap_label(@highlights.trap)}
          empty_label="Keine falschen Antworten"
        />
      </section>

      <p id="question-report-distribution-help" class="text-base text-base-content/80">
        A–D: Anzahl der Teams je Antwort. Grün = richtige Antwort.
        Bei mehreren Quiz werden die Antworten zusammengezählt.
      </p>

      <div class="w-full lg:overflow-x-auto lg:rounded-lg lg:border-2 lg:border-base-300">
        <table class="table block! w-full text-[0.95rem] lg:[display:table]! lg:table-fixed">
          <colgroup class="hidden lg:table-column-group">
            <col class="w-[14%] xl:w-[11%]" />
            <col class="w-[11%] xl:w-[9.5%]" />
            <col class="w-[14%] xl:w-[11.5%]" />
            <col class="w-[10%] xl:w-[8.75%]" />
            <col class="w-[14%] xl:w-[14.25%]" />
            <col class="w-[25%] xl:w-[32.5%]" />
            <col class="w-[12%] xl:w-[12.5%]" />
          </colgroup>
          <thead class="hidden lg:table-header-group">
            <tr class="border-b-2 border-base-300 bg-base-200 text-base-content">
              <th class="pl-4 pr-1 py-3 whitespace-normal">
                <%= if @topic_filter != "" do %>
                  <.sort_button
                    label="Frage"
                    key="question"
                    sort_key={@sort_key}
                    sort_dir={@sort_dir}
                  />
                <% else %>
                  Thema / Frage
                <% end %>
              </th>
              <th class="px-2 py-3 text-center">
                <.sort_button label="Gefragt" key="asked" sort_key={@sort_key} sort_dir={@sort_dir} />
              </th>
              <th class="px-2 py-3 text-center">
                <.sort_button
                  label="Antworten"
                  key="answers"
                  sort_key={@sort_key}
                  sort_dir={@sort_dir}
                />
              </th>
              <th class="px-2 py-3 text-center">
                <.sort_button label="Falsch" key="wrong" sort_key={@sort_key} sort_dir={@sort_dir} />
              </th>
              <th class="px-2 py-3 text-center">
                <.sort_button label="Richtig" key="right" sort_key={@sort_key} sort_dir={@sort_dir} />
              </th>
              <th class="px-3 py-3 min-w-[280px]">Team-Antworten</th>
              <th class="px-3 py-3">Falle</th>
            </tr>
          </thead>
          <tbody
            id="question-report-rows"
            phx-update="stream"
            class="block space-y-3 lg:table-row-group lg:space-y-0 lg:divide-y lg:divide-base-300"
          >
            <tr
              :if={@rows_empty?}
              id="question-report-empty"
              class="block rounded-lg border border-base-300 bg-base-200 lg:table-row lg:rounded-none lg:border-0"
            >
              <td colspan="7" class="block px-4 py-6 text-center text-base-content/70 lg:table-cell">
                Keine Fragen aus abgeschlossenen Quiz gefunden.
              </td>
            </tr>
            <tr
              :for={{id, entry} <- @streams.rows}
              id={id}
              class="grid grid-cols-2 overflow-hidden rounded-lg border border-base-300 bg-base-200 hover:bg-base-300/60 lg:table-row lg:rounded-none lg:border-0"
            >
              <td class="col-span-2 block min-w-0 border-b border-base-300 px-4 py-3 lg:pl-4 lg:pr-1 lg:table-cell lg:border-0">
                <div class="text-[1.0625rem] font-semibold break-words">{entry.topic_name}</div>
                <div class="flex items-center gap-1 mt-1">
                  <span data-test="question-label" class="text-[1.0625rem] whitespace-nowrap">
                    Frage {entry.question.position + 1}
                  </span>
                  <button
                    id={"view-question-#{entry.question.id}"}
                    type="button"
                    class="btn btn-xs btn-square size-7 min-h-7 border-base-content/30 bg-base-100 hover:bg-base-300 shadow-none shrink-0"
                    phx-click="show_question"
                    phx-value-id={entry.question.id}
                    aria-haspopup="dialog"
                    aria-label={"Frage #{entry.question.position + 1} ansehen"}
                    title="Frage ansehen"
                  >
                    <.icon name="hero-eye" class="size-4" />
                  </button>
                </div>
              </td>
              <td class="block px-4 py-2 font-mono lg:px-2 lg:table-cell lg:py-3 lg:text-center">
                <span class="block font-sans lg:hidden">Gefragt</span><span class="text-[1.4375rem] font-semibold tabular-nums">{entry.asked_in}×</span>
              </td>
              <td class="block px-4 py-2 font-mono lg:px-2 lg:table-cell lg:py-3 lg:text-center">
                <span class="block font-sans lg:hidden">Antworten</span><span class="text-[1.4375rem] font-semibold tabular-nums">{entry.answers}</span>
              </td>
              <td class="block px-4 py-2 font-mono text-base-content/70 lg:px-2 lg:table-cell lg:py-3 lg:text-center">
                <span class="block font-sans lg:hidden">Falsch</span>
                <span class="text-[1.4375rem] font-semibold tabular-nums">{entry.answers -
                  entry.correct}</span>
              </td>
              <td class="block px-4 py-2 lg:px-3 lg:table-cell lg:py-3 lg:text-center">
                <span class="block lg:hidden">Richtig</span>
                <span
                  data-test="correct-percent"
                  class="text-xl tabular-nums font-semibold whitespace-nowrap text-base-content"
                >
                  {entry.pct} %
                </span>
                <div
                  class="mt-2 h-3 w-full min-w-20 overflow-hidden rounded-full bg-base-300"
                  aria-hidden="true"
                >
                  <div class="h-full bg-success" style={"width: #{entry.pct}%"}></div>
                </div>
              </td>
              <td class="col-span-2 block min-w-0 px-4 py-3 lg:px-3 lg:table-cell">
                <span class="mb-2 block font-medium lg:hidden">Team-Antworten</span>
                <div class="grid grid-cols-4 gap-2">
                  <%= for {_option, idx} <- Enum.with_index(entry.question.options) do %>
                    <% count = Map.get(entry.picks, idx, 0) %>
                    <div
                      data-answer-index={idx}
                      data-correct={to_string(idx in entry.correct_options)}
                      class={[
                        "min-w-0 rounded-md border px-2 py-1.5 text-center",
                        idx in entry.correct_options && "bg-success text-success-content",
                        idx in entry.correct_options && "border-success",
                        idx not in entry.correct_options &&
                          "border-base-300 bg-base-100 text-base-content"
                      ]}
                      aria-label={"#{letter_for_index(idx)}: #{count} Antworten#{if idx in entry.correct_options, do: ", richtig", else: ""}"}
                    >
                      <div class="font-semibold whitespace-nowrap">
                        {letter_for_index(idx)}
                      </div>
                      <div
                        data-test="answer-count"
                        class="text-[1.4375rem] leading-tight font-bold tabular-nums"
                      >
                        {count}
                      </div>
                      <div
                        class={[
                          "mt-1 h-1.5 overflow-hidden rounded-full",
                          if(idx in entry.correct_options,
                            do: "bg-success-content/20",
                            else: "bg-base-300"
                          )
                        ]}
                        aria-hidden="true"
                      >
                        <div
                          class={[
                            "h-full",
                            if(idx in entry.correct_options,
                              do: "bg-success-content",
                              else: "bg-base-content/70"
                            )
                          ]}
                          style={"width: #{segment_pct(count, entry.answers)}%"}
                        >
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              </td>
              <td class="col-span-2 block border-t border-base-300 px-4 py-2 text-sm lg:px-3 lg:table-cell lg:border-0 lg:py-3">
                <span class="mr-2 lg:hidden">Falle</span>
                <%= if entry.trap do %>
                  <% {idx, count} = entry.trap %>
                  <span class="text-[1.1875rem] font-bold whitespace-nowrap">{letter_for_index(idx)} · {count}×</span>
                <% else %>
                  <span class="text-base-content/50">—</span>
                <% end %>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <dialog
        :if={@question_details}
        id="question-report-details"
        phx-hook="Dialog"
        phx-update="ignore"
        data-cancel-event="close_question"
        aria-labelledby="question-report-details-title"
        class="m-auto w-[calc(100%-2rem)] max-w-2xl max-h-[85vh] overflow-hidden rounded-box border border-base-300 bg-base-100 p-0 text-base-content shadow-xl"
      >
        <div class="flex max-h-[85vh] flex-col">
          <div class="flex shrink-0 items-center justify-between gap-4 border-b border-base-300 px-5 py-4 sm:px-6">
            <h2 id="question-report-details-title" class="text-lg font-semibold leading-snug">
              {@question_details.topic_name} · Frage {@question_details.question.position + 1}
            </h2>
            <button
              id="question-report-details-close"
              type="button"
              class="btn min-h-11 shrink-0"
              phx-click="close_question"
              aria-label="Schließen"
            >
              <.icon name="hero-x-mark" class="size-5" />
              <span class="hidden sm:inline">Schließen</span>
            </button>
          </div>
          <div class="min-h-0 overflow-y-auto px-5 py-5 sm:px-6 sm:py-6">
            <p class="text-lg leading-relaxed">{@question_details.question.prompt}</p>
            <ol class="mt-5 space-y-3">
              <li
                :for={{option, idx} <- Enum.with_index(@question_details.question.options)}
                data-option={idx}
                class={[
                  "grid grid-cols-[2.5rem_minmax(0,1fr)] items-start gap-3 rounded-lg border p-4 text-lg",
                  if(idx in @question_details.correct_options,
                    do: "border-success bg-success/10",
                    else: "border-base-300 bg-base-200"
                  )
                ]}
              >
                <span class={[
                  "flex size-10 items-center justify-center rounded-md border font-semibold",
                  if(idx in @question_details.correct_options,
                    do: "border-success bg-success text-success-content",
                    else: "border-base-300 bg-base-100"
                  )
                ]}>{letter_for_index(idx)}</span>
                <div class="min-w-0 pt-1 leading-relaxed">
                  <div data-test="answer-text">{option["text"]}</div>
                </div>
              </li>
            </ol>
          </div>
        </div>
      </dialog>
    </Layouts.app>
    """
  end

  defp event_label(event), do: "#{event.name || "Quiz"} · #{event.code}"

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :entry, :map, default: nil
  attr :value, :string, default: nil
  attr :empty_label, :string, default: "Keine Antworten"

  defp highlight_card(assigns) do
    ~H"""
    <div id={@id} class="rounded-lg border border-base-300 bg-base-200 p-4 text-base-content">
      <h2 class="text-sm font-medium text-base-content/80">{@label}</h2>
      <%= if @entry do %>
        <div data-test="highlight-question" class="mt-2 text-base font-semibold break-words">
          {@entry.topic_name} · Frage {@entry.question.position + 1}
        </div>
        <div data-test="highlight-value" class="mt-1 text-xl font-semibold tabular-nums">
          {@value}
        </div>
      <% else %>
        <div class="mt-2 text-base-content/70">{@empty_label}</div>
      <% end %>
    </div>
    """
  end

  defp trap_label(nil), do: nil

  defp trap_label(%{trap: {index, count}}),
    do: "#{letter_for_index(index)} · #{count}× gewählt"

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
      class="btn btn-sm btn-soft border-0 shadow-none min-h-11 px-2 text-[0.95rem] inline-flex items-center gap-1"
      aria-sort={if @sort_key == @key, do: to_string(@sort_dir), else: "none"}
    >
      {@label}
      <span :if={@sort_key == @key} class="text-xs leading-none shrink-0">
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
