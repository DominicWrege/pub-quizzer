defmodule PubQuizzer.Quiz.TopicPdf do
  @moduledoc """
  Renders a topic's questions and answers as a printable PDF cheat sheet.

  Uses the `:pdf` library's built-in Helvetica font with WinAnsi encoding,
  which covers German umlauts, ß, €, typographic quotes and dashes. Characters
  outside WinAnsi (e.g. emoji) are stripped before rendering, because the
  library raises on unsupported input — crashing its internal GenServer.

  Text is laid out with `Pdf.text_wrap/5`, which handles word wrapping and
  reports a `{:continue, remaining}` continuation when a block runs out of
  vertical space; we then start a new page and resume, so content never
  overflows or is lost.
  """

  @page_width 595
  @page_height 842
  @margin 40

  @title_size 18
  @subtitle_size 10
  @prompt_size 12
  @option_size 11

  @correct_color :green
  @muted_color :gray

  # Spacing (points)
  @question_gap 12
  @min_question_space 56

  @letters ~w(A B C D E F)

  # Unicode codepoints the WinAnsi encoding can represent. Anything else is
  # stripped from the text before it reaches the PDF library.
  @win_ansi_codepoints MapSet.new(
                         for {_byte, utf, _name} <- Pdf.Encoding.WinAnsi.characters(),
                             utf != nil,
                             do: utf
                       )

  @doc """
  Returns the PDF document for `topic` and its ordered `questions` as a binary.
  """
  @spec render(PubQuizzer.Quiz.Topic.t(), [PubQuizzer.Quiz.Question.t()]) :: binary()
  def render(topic, questions) do
    Pdf.build([size: :a4, compress: true], fn pdf ->
      pdf
      |> Pdf.set_info(title: sanitize(topic.name), creator: "Kneipenquiz")
      |> Pdf.set_font("Helvetica", @option_size)
      |> Pdf.set_cursor(top_y())
      |> draw_header(topic, length(questions))
      |> draw_questions(questions)
      |> Pdf.export()
    end)
  end

  defp top_y, do: @page_height - @margin
  defp content_width, do: @page_width - 2 * @margin
  defp full_height, do: @page_height - 2 * @margin

  # --- Header ---

  defp draw_header(pdf, topic, count) do
    pdf
    |> draw_block([{sanitize(topic.name), [bold: true, font_size: @title_size]}])
    |> move_gap(4)
    |> draw_block([{subtitle(topic, count), [font_size: @subtitle_size, color: @muted_color]}])
    |> move_gap(8)
    |> draw_rule()
    |> move_gap(12)
  end

  defp subtitle(topic, count) do
    questions_label = if count == 1, do: "1 Frage", else: "#{count} Fragen"

    case topic.description do
      nil -> questions_label
      "" -> questions_label
      desc -> "#{sanitize(desc)} · #{questions_label}"
    end
  end

  defp draw_rule(pdf) do
    y = Pdf.cursor(pdf)

    pdf
    |> Pdf.set_stroke_color(:silver)
    |> Pdf.set_line_width(0.5)
    |> Pdf.line({@margin, y}, {@page_width - @margin, y})
    |> Pdf.stroke()
  end

  # --- Questions ---

  defp draw_questions(pdf, questions) do
    questions
    |> Enum.with_index(1)
    |> Enum.reduce(pdf, fn {question, number}, pdf ->
      pdf
      |> maybe_page_break()
      |> draw_block(question_content(question, number))
      |> move_gap(@question_gap)
    end)
  end

  defp maybe_page_break(pdf) do
    if Pdf.cursor(pdf) - @margin < @min_question_space do
      new_page(pdf)
    else
      pdf
    end
  end

  defp question_content(question, number) do
    prompt = [
      {"#{number}. #{sanitize(question.prompt)}\n", [bold: true, font_size: @prompt_size]}
    ]

    prompt ++ option_contents(question)
  end

  defp option_contents(question) do
    options = question.options || []

    options
    |> Enum.with_index()
    |> Enum.flat_map(fn {option, index} ->
      correct? = index == question.correct_index
      letter = letter(index)

      attrs =
        if correct?,
          do: [font_size: @option_size, bold: true, color: @correct_color],
          else: [font_size: @option_size]

      suffix =
        if correct?,
          do: [{"   (richtig)", [font_size: @option_size, bold: true, color: @correct_color]}],
          else: []

      [{"#{letter}. #{sanitize(option_text(option))}", attrs}] ++
        suffix ++ [{"\n", [font_size: @option_size]}]
    end)
  end

  defp option_text(option) when is_map(option),
    do: Map.get(option, "text") || Map.get(option, :text) || ""

  defp option_text(option) when is_binary(option), do: option
  defp option_text(_), do: ""

  defp letter(index), do: Enum.at(@letters, index, "?")

  # --- Layout helpers ---

  # Draws `content` at the left margin / current cursor, wrapping to the content
  # width and flowing onto new pages via the library's continuation mechanism.
  defp draw_block(pdf, content) do
    available = Pdf.cursor(pdf) - @margin
    continue_wrap(pdf, content, available)
  end

  defp continue_wrap(pdf, content, height) do
    case Pdf.text_wrap(pdf, {@margin, :cursor}, {content_width(), height}, content) do
      {pdf, :complete} ->
        pdf

      {pdf, {:continue, _} = continuation} ->
        pdf
        |> new_page()
        |> continue_wrap(continuation, full_height())
    end
  end

  defp new_page(pdf) do
    pdf
    |> Pdf.add_page()
    |> Pdf.set_font("Helvetica", @option_size)
    |> Pdf.set_cursor(top_y())
  end

  defp move_gap(pdf, amount), do: Pdf.move_down(pdf, amount)

  # Keeps only characters representable in WinAnsi, preserving valid UTF-8 so
  # the PDF library's internal encoding step never raises.
  defp sanitize(text) when is_binary(text) do
    for <<codepoint::utf8 <- text>>, into: "" do
      if MapSet.member?(@win_ansi_codepoints, codepoint), do: <<codepoint::utf8>>, else: ""
    end
  end

  defp sanitize(_), do: ""
end
