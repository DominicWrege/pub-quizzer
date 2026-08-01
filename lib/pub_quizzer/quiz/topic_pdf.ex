defmodule PubQuizzer.Quiz.TopicPdf do
  @moduledoc """
  Renders a topic's questions and answers as a printable PDF cheat sheet.

  The document is laid out as a designed, layered piece rather than a text
  dump:

    * a warm **paper canvas** (never plain white) with soft ambient circles
      bleeding in from the page edges
    * a floating, rounded **masthead card** in the brand colour, carrying an
      eyebrow tag, the wrapped topic title and a circular wax-seal style
      question counter
    * one rounded white **card per question** with a flat offset shadow, a
      brand number badge, circular A/B/C/D letter chips and the correct
      answer set in a padded green pill that is optically centred
    * a quiet **footer** with a brand mark and the page number on every page

  The `:pdf` library exposes no rounded-rectangle, arc or gradient operators,
  so rounded corners and circles are drawn as polygonal paths
  (`rounded_fill/6`). Background shapes are sized by *measuring* the text
  first with the pure helpers in `Pdf.Font` / `Pdf.Text` (`text_width/3`,
  `chunk_text/3` + `wrap_all_chunks/2`), which use the same wrapping
  algorithm as the renderer — so shapes and text always agree, and questions
  move to the next page as a whole instead of breaking mid-card.

  Uses the built-in Helvetica font with WinAnsi encoding (German umlauts, ß,
  €, typographic quotes and dashes). Characters outside WinAnsi (e.g. emoji)
  are stripped first, because the library raises on unsupported input.
  """

  # --- Page geometry (points, A4) ---
  @page_w 595
  @page_h 842
  @margin 44
  @page_top_gap 28
  @top_margin 48
  @bottom_margin 60

  # --- Masthead ---
  @h_pad_x 24
  @h_pad_top 18
  @h_pad_bottom 16
  @h_corner 12
  @eyebrow_size 8
  @eyebrow_h 17
  @eyebrow_title_gap 9
  @title_size 23
  @title_leading 27
  @seal_d 60
  @seal_num 18
  @seal_label 6.5
  @seal_gap 2

  # --- Meta / legend ---
  @meta_size 10
  @meta_leading 14
  @legend_size 9

  # --- Question card ---
  @card_corner 10
  @card_pad_l 20
  @card_pad_r 20
  @card_pad_top 18
  @card_pad_bottom 16
  @card_gap 14
  @card_shadow 2
  @badge 26
  @badge_corner 7
  @badge_num 12
  @prompt_size 13
  @prompt_leading 18
  @prompt_gap 12
  @top_opts_gap 12

  # --- Options ---
  @chip_d 20
  @chip_letter 10
  @opt_size 11
  @opt_leading 15
  @opt_text_gap 11
  @slot 34
  @pad_v 9
  @opt_gap 8
  @pill_inset 8

  # --- Footer ---
  @footer_rule_y 44
  @footer_text_y 31
  @footer_size 8.5

  # Helvetica cap-height in font units (per-mille); used to centre text.
  @cap_units 718

  # --- Palette (RGB) ---
  @paper {0xF2, 0xEE, 0xE6}
  @ambient {0xEA, 0xE2, 0xD4}
  @card_white {0xFF, 0xFF, 0xFF}
  @shadow {0xE3, 0xDA, 0xCB}
  @brand {0xA0, 0x4E, 0x1A}
  @brand_hi {0xB8, 0x64, 0x2C}
  @brand_lo {0x7C, 0x3C, 0x12}
  @ink {0x22, 0x1C, 0x15}
  @body {0x3A, 0x32, 0x28}
  @muted {0x7A, 0x6F, 0x61}
  @faint {0xA8, 0x9D, 0x8E}
  @chip_bg {0xEF, 0xE9, 0xDE}
  @green {0x1B, 0x7A, 0x39}
  @green_pill {0xE2, 0xF1, 0xE6}
  @rule {0xE6, 0xDE, 0xD1}
  @white {0xFF, 0xFF, 0xFF}

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
      |> Pdf.set_font("Helvetica", @opt_size)
      |> draw_page_background()
      |> Pdf.set_cursor(@page_h - @page_top_gap)
      |> draw_header(topic, length(questions))
      |> draw_meta_and_legend(topic)
      |> draw_questions(questions)
      |> draw_footer()
      |> Pdf.export()
    end)
  end

  # --- Geometry ---

  defp content_w, do: @page_w - 2 * @margin
  defp card_w, do: content_w()
  defp inner_w, do: card_w() - @card_pad_l - @card_pad_r
  defp inner_left, do: @margin + @card_pad_l
  defp prompt_w, do: inner_w() - @badge - @prompt_gap
  defp opt_text_w, do: inner_w() - @chip_d - @opt_text_gap
  defp new_page_top, do: @page_h - @top_margin
  defp content_bottom, do: @bottom_margin
  defp cap_h(size), do: @cap_units * size / 1000

  # --- Pure measurement ---

  defp helvetica(opts), do: Pdf.Fonts.get_internal_font("Helvetica", opts)

  defp text_width(text, size, opts \\ []),
    do: Pdf.Font.text_width(helvetica(opts), text, size)

  defp line_count(text, width, size, opts) do
    text
    |> Pdf.Text.chunk_text(helvetica(opts), size)
    |> Pdf.Text.wrap_all_chunks(width)
    |> length()
  end

  defp wrapped_lines(text, width, size, opts \\ []) do
    text
    |> Pdf.Text.chunk_text(helvetica(opts), size)
    |> Pdf.Text.wrap_all_chunks(width)
    |> Enum.map(fn {:line, chunks} -> Enum.map_join(chunks, "", &elem(&1, 0)) end)
  end

  # --- Shapes (the library has no rounded-rect / arc ops) ---

  # Fills a rounded rectangle (or circle, when r == w/2 == h/2) by tracing a
  # polygonal path: straight edges plus `n`-segment quarter-arcs per corner.
  # `(x, y)` is the bottom-left corner, `y + h` the top edge (PDF y-up).
  defp rounded_fill(pdf, x, y, w, h, r, color) do
    r = min(r, w / 2) |> min(h / 2)
    n = 6

    top_y = y + h
    bot_y = y
    left_x = x
    right_x = x + w

    arc = fn cx, cy, a0, a1 ->
      for i <- 1..n do
        a = (a0 + (a1 - a0) * i / n) * :math.pi() / 180
        {cx + r * :math.cos(a), cy + r * :math.sin(a)}
      end
    end

    verts =
      [{x + r, top_y}, {right_x - r, top_y}] ++
        arc.(right_x - r, top_y - r, 90, 0) ++
        [{right_x, bot_y + r}] ++
        arc.(right_x - r, bot_y + r, 0, -90) ++
        [{x + r, bot_y}] ++
        arc.(left_x + r, bot_y + r, -90, -180) ++
        [{left_x, top_y - r}] ++
        arc.(left_x + r, top_y - r, 180, 90)

    [{vx, vy} | rest] = verts

    pdf =
      rest
      |> Enum.reduce(Pdf.move_to(pdf, {vx, vy}), fn {px, py}, p ->
        Pdf.line_append(p, {px, py})
      end)

    pdf
    |> Pdf.set_fill_color(color)
    |> Pdf.fill()
  end

  defp circle_fill(pdf, cx, cy, r, color),
    do: rounded_fill(pdf, cx - r, cy - r, 2 * r, 2 * r, r, color)

  # --- Page background ---

  defp draw_page_background(pdf) do
    pdf
    |> Pdf.set_fill_color(@paper)
    |> Pdf.rectangle({0, 0}, {@page_w, @page_h})
    |> Pdf.fill()
    |> circle_fill(@page_w - 8, 470, 72, @ambient)
    |> circle_fill(6, 250, 56, @ambient)
    |> circle_fill(@page_w - 30, 120, 40, @ambient)
  end

  # --- Masthead ---

  defp draw_header(pdf, topic, count) do
    title = sanitize(topic.name)
    title_w = content_w() - 2 * @h_pad_x - @seal_d - 18
    title_lines = max(line_count(title, title_w, @title_size, bold: true), 1)

    eyebrow = "KNEIPENQUIZ   ·   SPICKZETTEL"
    ew = text_width(eyebrow, @eyebrow_size, bold: true)
    ep_w = ew + 18

    inner_h =
      @h_pad_top + @eyebrow_h + @eyebrow_title_gap +
        title_lines * @title_leading + @h_pad_bottom

    card_h = max(inner_h, @seal_d + 28)
    card_top = Pdf.cursor(pdf)
    card_left = @margin
    card_right = @margin + content_w()
    seal_cy = card_top - card_h / 2

    pdf
    # flat shadow + brand card
    |> rounded_fill(card_left + 3, card_top - card_h - 3, content_w(), card_h, @h_corner, @shadow)
    |> rounded_fill(card_left, card_top - card_h, content_w(), card_h, @h_corner, @brand)
    # tonal ambient circle framing the seal (left side kept clean for text)
    |> circle_fill(card_right - 76, seal_cy, 22, @brand_hi)
    # eyebrow tag pill
    |> draw_eyebrow(card_left + @h_pad_x, card_top - @h_pad_top, ep_w, eyebrow, ew)
    # title
    |> Pdf.set_cursor(card_top - @h_pad_top - @eyebrow_h - @eyebrow_title_gap)
    |> draw_title(card_left + @h_pad_x, title_w, title_lines, title)
    # wax-seal question counter
    |> draw_seal(card_right - @h_pad_x - @seal_d / 2, seal_cy, count)
    |> Pdf.set_cursor(card_top - card_h - 16)
  end

  defp draw_eyebrow(pdf, x, top, pill_w, text, text_w) do
    cy = top - @eyebrow_h / 2

    pdf
    |> rounded_fill(x, top - @eyebrow_h, pill_w, @eyebrow_h, @eyebrow_h / 2, @brand_lo)
    |> Pdf.text_at(
      {x + (pill_w - text_w) / 2, cy - cap_h(@eyebrow_size) / 2},
      [{text, [bold: true, font_size: @eyebrow_size, color: @white]}]
    )
  end

  defp draw_title(pdf, x, width, lines, title) do
    {pdf, _} =
      Pdf.text_wrap(
        pdf,
        {x, :cursor},
        {width, lines * @title_leading + 6},
        [{title, [bold: true, font_size: @title_size, color: @white]}],
        leading: @title_leading
      )

    pdf
  end

  defp draw_seal(pdf, cx, cy, count) do
    count_str = Integer.to_string(count)
    cw = text_width(count_str, @seal_num, bold: true)
    label = if count == 1, do: "FRAGE", else: "FRAGEN"
    lw = text_width(label, @seal_label, bold: true)

    # Centre the number + label block on `cy`: caps sit above their baseline,
    # so each baseline is pulled down by half its own cap-height.
    block_h = cap_h(@seal_num) + @seal_gap + cap_h(@seal_label)
    nb = cy + block_h / 2 - cap_h(@seal_num)
    lb = cy - block_h / 2

    pdf
    |> circle_fill(cx, cy, @seal_d / 2, @brand_lo)
    |> circle_fill(cx, cy, @seal_d / 2 - 4, @brand)
    |> Pdf.text_at(
      {cx - cw / 2, nb},
      [{count_str, [bold: true, font_size: @seal_num, color: @white]}]
    )
    |> Pdf.text_at({cx - lw / 2, lb}, [
      {label, [bold: true, font_size: @seal_label, color: @white]}
    ])
  end

  # --- Meta + legend ---

  defp draw_meta_and_legend(pdf, topic) do
    pdf =
      case topic.description do
        nil ->
          pdf

        "" ->
          pdf

        desc ->
          {pdf, _} =
            Pdf.text_wrap(
              pdf,
              {@margin, :cursor},
              {content_w(), @meta_leading * 3},
              [{truncate(sanitize(desc), 150), [font_size: @meta_size, color: @muted]}],
              leading: @meta_leading
            )

          Pdf.move_down(pdf, 9)
      end

    baseline = Pdf.cursor(pdf) - 3
    legend = "Richtige Antwort ist grün markiert"

    pdf
    |> circle_fill(@margin + 4, baseline + cap_h(@legend_size) / 2, 3.5, @green)
    |> Pdf.text_at(
      {@margin + 14, baseline},
      [{legend, [font_size: @legend_size, color: @muted]}]
    )
    |> Pdf.set_cursor(baseline - 16)
  end

  # --- Questions ---

  defp draw_questions(pdf, questions) do
    questions
    |> Enum.with_index(1)
    |> Enum.reduce(pdf, fn {question, number}, pdf ->
      draw_question(pdf, question, number)
    end)
  end

  defp draw_question(pdf, question, number) do
    card_h = question_card_h(question)
    pdf = ensure_space(pdf, card_h + @card_shadow + @card_gap)

    card_top = Pdf.cursor(pdf)
    inner_top = card_top - @card_pad_top

    pdf
    # shadow + white card
    |> rounded_fill(
      @margin + @card_shadow,
      card_top - card_h - @card_shadow,
      card_w(),
      card_h,
      @card_corner,
      @shadow
    )
    |> rounded_fill(@margin, card_top - card_h, card_w(), card_h, @card_corner, @card_white)
    # number badge
    |> rounded_fill(inner_left(), inner_top - @badge, @badge, @badge, @badge_corner, @brand)
    |> draw_badge_number(inner_left(), inner_top, number)
    # prompt
    |> Pdf.set_cursor(inner_top)
    |> draw_prompt(question)
    # options
    |> Pdf.set_cursor(inner_top - max(@badge, prompt_h(question)) - @top_opts_gap)
    |> draw_options(question)
    |> Pdf.set_cursor(card_top - card_h - @card_gap)
  end

  defp draw_badge_number(pdf, x, inner_top, number) do
    num = Integer.to_string(number)
    nw = text_width(num, @badge_num, bold: true)

    Pdf.text_at(
      pdf,
      {x + @badge / 2 - nw / 2, inner_top - @badge / 2 - cap_h(@badge_num) / 2},
      [{num, [bold: true, font_size: @badge_num, color: @white]}]
    )
  end

  defp draw_prompt(pdf, question) do
    content = [{sanitize(question.prompt), [bold: true, font_size: @prompt_size, color: @ink]}]

    {pdf, _} =
      Pdf.text_wrap(
        pdf,
        {inner_left() + @badge + @prompt_gap, :cursor},
        {prompt_w(), prompt_h(question) + 4},
        content,
        leading: @prompt_leading
      )

    pdf
  end

  defp draw_options(pdf, question) do
    (question.options || [])
    |> Enum.with_index()
    |> Enum.reduce(pdf, fn {option, index}, pdf ->
      row_top = Pdf.cursor(pdf)
      row_h = option_row_h(option_text(option), index == question.correct_index)

      pdf
      |> draw_option(option_text(option), index, question.correct_index, row_top)
      |> Pdf.set_cursor(row_top - row_h)
    end)
  end

  defp draw_option(pdf, raw_text, index, correct_index, row_top) do
    text = sanitize(raw_text)
    correct? = index == correct_index
    letter = letter(index)
    n = max(line_count(text, opt_text_w(), @opt_size, []), 1)
    lines = wrapped_lines(text, opt_text_w(), @opt_size)

    chip_cx = inner_left() + @chip_d / 2
    text_x = inner_left() + @chip_d + @opt_text_gap

    {pill_or_slot, chip_fill, letter_color, text_color, bold?} =
      if correct? do
        tbh = cap_h(@opt_size) + (n - 1) * @opt_leading
        pill_h = max(@slot, tbh + 2 * @pad_v)
        {pill_h, @green, @white, @green, true}
      else
        {@slot, @chip_bg, @muted, @body, false}
      end

    vcenter = row_top - pill_or_slot / 2
    # Baseline of the first line so the whole text block is optically centred
    # on `vcenter` (caps sit *above* the baseline, so subtract half a cap-height).
    first_baseline = vcenter + (n - 1) * @opt_leading / 2 - cap_h(@opt_size) / 2

    pdf =
      if correct? do
        rounded_fill(
          pdf,
          inner_left() - @pill_inset,
          row_top - pill_or_slot,
          inner_w() + 2 * @pill_inset,
          pill_or_slot,
          pill_or_slot / 2,
          @green_pill
        )
      else
        pdf
      end

    pdf
    # letter chip
    |> circle_fill(chip_cx, vcenter, @chip_d / 2, chip_fill)
    |> Pdf.text_at(
      {chip_cx - text_width(letter, @chip_letter, bold: true) / 2,
       vcenter - cap_h(@chip_letter) / 2},
      [{letter, [bold: true, font_size: @chip_letter, color: letter_color]}]
    )
    # option text (one baseline per wrapped line)
    |> draw_option_lines(lines, text_x, first_baseline, text_color, bold?)
  end

  defp draw_option_lines(pdf, lines, x, first_baseline, color, bold?) do
    lines
    |> Enum.with_index()
    |> Enum.reduce(pdf, fn {line, i}, pdf ->
      Pdf.text_at(
        pdf,
        {x, first_baseline - i * @opt_leading},
        [{line, [bold: bold?, font_size: @opt_size, color: color]}]
      )
    end)
  end

  # --- Height measurement (mirrors the drawing above) ---

  defp prompt_h(question) do
    line_count(sanitize(question.prompt), prompt_w(), @prompt_size, bold: true) *
      @prompt_leading
  end

  defp option_row_h(raw_text, correct?) do
    text = sanitize(raw_text)
    n = max(line_count(text, opt_text_w(), @opt_size, []), 1)
    tbh = cap_h(@opt_size) + (n - 1) * @opt_leading

    content_h =
      if correct?, do: max(@slot, tbh + 2 * @pad_v), else: max(@slot, tbh)

    content_h + @opt_gap
  end

  defp options_h(question) do
    (question.options || [])
    |> Enum.with_index()
    |> Enum.reduce(0, fn {option, index}, acc ->
      acc + option_row_h(option_text(option), index == question.correct_index)
    end)
  end

  defp question_card_h(question) do
    top_region = max(@badge, prompt_h(question))

    @card_pad_top + top_region + @top_opts_gap + options_h(question) + @card_pad_bottom
  end

  # --- Paging & footer ---

  defp ensure_space(pdf, needed) do
    if Pdf.cursor(pdf) - content_bottom() < needed do
      new_page(pdf)
    else
      pdf
    end
  end

  defp new_page(pdf) do
    pdf
    |> draw_footer()
    |> Pdf.add_page()
    |> Pdf.set_font("Helvetica", @opt_size)
    |> draw_page_background()
    |> Pdf.set_cursor(new_page_top())
  end

  defp draw_footer(pdf) do
    page_label = "Seite #{Pdf.page_number(pdf)}"
    label_w = text_width(page_label, @footer_size)

    pdf
    |> Pdf.set_stroke_color(@rule)
    |> Pdf.set_line_width(0.75)
    |> Pdf.line({@margin, @footer_rule_y}, {@page_w - @margin, @footer_rule_y})
    |> Pdf.stroke()
    |> circle_fill(@margin + 3, @footer_text_y + cap_h(@footer_size) / 2, 3, @brand)
    |> Pdf.text_at(
      {@margin + 12, @footer_text_y},
      [{"Kneipenquiz", [font_size: @footer_size, color: @faint]}]
    )
    |> Pdf.text_at(
      {@page_w - @margin - label_w, @footer_text_y},
      [{page_label, [font_size: @footer_size, color: @faint]}]
    )
  end

  # --- Text helpers ---

  defp option_text(option) when is_map(option),
    do: Map.get(option, "text") || Map.get(option, :text) || ""

  defp option_text(option) when is_binary(option), do: option
  defp option_text(_), do: ""

  defp letter(index), do: Enum.at(@letters, index, "?")

  defp truncate(text, max) do
    if String.length(text) > max do
      String.slice(text, 0, max - 1) <> "…"
    else
      text
    end
  end

  # Keeps only characters representable in WinAnsi, preserving valid UTF-8 so
  # the PDF library's internal encoding step never raises.
  defp sanitize(text) when is_binary(text) do
    for <<codepoint::utf8 <- text>>, into: "" do
      if MapSet.member?(@win_ansi_codepoints, codepoint), do: <<codepoint::utf8>>, else: ""
    end
  end

  defp sanitize(_), do: ""
end
