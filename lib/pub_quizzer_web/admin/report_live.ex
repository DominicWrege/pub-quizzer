defmodule PubQuizzerWeb.Admin.ReportLive do
  use PubQuizzerWeb, :live_view

  alias PubQuizzer.Quiz

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    event = Quiz.get_event!(id)

    if event.status != "finished" do
      {:ok, redirect(socket, to: ~p"/admin/events/#{id}/results")}
    else
      {:ok,
       socket
       |> assign(:page_title, "Bericht")
       |> assign(:report, Quiz.get_event_report(id))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      print_chrome={false}
      max_width="max-w-5xl"
    >
      <.header>
        <div class="flex items-baseline gap-2 sm:gap-3 flex-wrap">
          <span>Bericht</span>
          <span class="text-sm text-base-content/70 whitespace-nowrap">
            {@report.event.name || "Quiz"} · {Calendar.strftime(
              @report.event.finished_at || @report.event.inserted_at,
              "%d.%m.%Y"
            )}
          </span>
        </div>
        <:actions>
          <.link
            navigate={~p"/admin/events/#{@report.event.id}/results"}
            class="btn btn-sm btn-soft print:hidden"
          >
            <.icon name="hero-chevron-left" class="size-4" /> Ergebnisse
          </.link>
        </:actions>
      </.header>

      <div id="report-timing" class="mb-8 text-sm text-base-content/70">
        <%= if @report.timing.total_seconds do %>
          Dauer gesamt {format_duration(@report.timing.total_seconds)} ·
        <% end %>
        Reine Antwortzeit {format_duration(@report.timing.answering_seconds)}
      </div>

      <div id="report-highlights" class="mb-8 grid gap-3 sm:grid-cols-3">
        <div class="rounded-lg border-2 border-base-300 bg-base-200 p-4 break-inside-avoid">
          <div class="text-xs font-semibold uppercase text-base-content/60">Schwerste Frage</div>
          <%= case @report.highlights.hardest do %>
            <% {question, pct} -> %>
              <div id="report-hardest" class="mt-1 font-medium">{question.prompt}</div>
              <div class="mt-1 text-sm font-semibold text-error">{pct} % richtig</div>
            <% nil -> %>
              <div class="mt-1 text-base-content/50">—</div>
          <% end %>
        </div>
        <div class="rounded-lg border-2 border-base-300 bg-base-200 p-4 break-inside-avoid">
          <div class="text-xs font-semibold uppercase text-base-content/60">Leichteste Frage</div>
          <%= case @report.highlights.easiest do %>
            <% {question, pct} -> %>
              <div id="report-easiest" class="mt-1 font-medium">{question.prompt}</div>
              <div class="mt-1 text-sm font-semibold text-success">{pct} % richtig</div>
            <% nil -> %>
              <div class="mt-1 text-base-content/50">—</div>
          <% end %>
        </div>
        <div class="rounded-lg border-2 border-base-300 bg-base-200 p-4 break-inside-avoid">
          <div class="text-xs font-semibold uppercase text-base-content/60">Beliebteste Falle</div>
          <%= case @report.highlights.trap do %>
            <% {question, idx, count} -> %>
              <div id="report-trap" class="contents">
                <div class="mt-1 font-medium">{question.prompt}</div>
                <div class="mt-1 text-sm text-base-content/70">
                  <span class="font-mono font-bold">{letter(idx)}</span>
                  · {option_text(question, idx)} — {count}× gewählt
                </div>
              </div>
            <% nil -> %>
              <div class="mt-1 text-base-content/50">—</div>
          <% end %>
        </div>
      </div>

      <%= for {round_data, r_idx} <- Enum.with_index(@report.rounds_data) do %>
        <div class="mb-8">
          <h3 class="text-lg font-semibold mb-3">
            Runde {r_idx + 1}: {round_data.round.topic.name}
          </h3>
          <div class="grid gap-4 md:grid-cols-2">
            <%= for {question, q_idx} <- Enum.with_index(round_data.questions) do %>
              <.question_card
                round={round_data.round}
                question={question}
                q_idx={q_idx}
                stats={
                  Map.get(@report.question_stats, {round_data.round.id, question.id}, %{
                    picks: %{},
                    no_answer: 0
                  })
                }
                team_count={@report.team_count}
              />
            <% end %>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  attr :round, :map, required: true
  attr :question, :map, required: true
  attr :q_idx, :integer, required: true
  attr :stats, :map, required: true
  attr :team_count, :integer, required: true

  defp question_card(assigns) do
    ~H"""
    <div
      id={"question-card-#{@round.id}-#{@question.id}"}
      class="rounded-lg border-2 border-base-300 bg-base-100 p-4 break-inside-avoid"
    >
      <div class="flex items-baseline justify-between gap-2">
        <span class="font-mono text-xs text-base-content/60">Q{@q_idx + 1}</span>
        <span class="text-xs font-semibold text-base-content/70">
          {correct_pct(@stats, @question, @team_count)} % richtig
        </span>
      </div>
      <div class="mt-1 font-medium">{@question.prompt}</div>
      <div class="text-xs text-success mt-0.5">
        Richtig: {letter(@question.correct_index)} · {option_text(@question, @question.correct_index)}
      </div>
      <div class="mt-3 flex h-7 w-full overflow-hidden rounded-md border border-base-300 bg-base-200">
        <%= for {idx, count} <- Enum.sort(@stats.picks), count > 0 do %>
          <div
            data-correct={to_string(idx == @question.correct_index)}
            class={[
              "flex items-center justify-center overflow-hidden whitespace-nowrap text-xs font-semibold",
              idx == @question.correct_index && "bg-success text-success-content",
              idx != @question.correct_index && "bg-base-300 text-base-content/80"
            ]}
            style={"width: #{segment_pct(count, @team_count)}%"}
            title={"#{letter(idx)}: #{count}×"}
          >
            {letter(idx)} · {count}
          </div>
        <% end %>
        <%= if @stats.no_answer > 0 do %>
          <div
            data-no-answer
            class="flex items-center justify-center overflow-hidden whitespace-nowrap bg-base-200 text-xs text-base-content/50"
            style={"width: #{segment_pct(@stats.no_answer, @team_count)}%"}
            title={"Keine Antwort: #{@stats.no_answer}×"}
          >
            – · {@stats.no_answer}
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp letter(index), do: letter_for_index(index)

  defp option_text(question, index) do
    question.options
    |> Enum.at(index)
    |> case do
      %{"text" => text} -> text
      text when is_binary(text) -> text
      _ -> ""
    end
  end

  defp correct_pct(_stats, _question, 0), do: 0

  defp correct_pct(stats, question, team_count) do
    round(Map.get(stats.picks, question.correct_index, 0) / team_count * 100)
  end

  defp segment_pct(_count, 0), do: 0

  defp segment_pct(count, team_count) do
    Float.round(count / team_count * 100, 2)
  end

  defp format_duration(nil), do: "—"

  defp format_duration(seconds) when seconds < 60, do: "#{seconds} Sek."

  defp format_duration(seconds) do
    minutes = round(seconds / 60)

    if minutes < 60 do
      "#{minutes} Min."
    else
      "#{div(minutes, 60)} Std. #{rem(minutes, 60)} Min."
    end
  end
end
