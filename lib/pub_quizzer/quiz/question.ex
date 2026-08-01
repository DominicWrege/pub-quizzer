defmodule PubQuizzer.Quiz.Question do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(draft published)
  @image_positions ~w(left right)

  schema "questions" do
    field :prompt, :string
    field :options, {:array, :map}
    field :correct_index, :integer
    field :position, :integer, default: 0
    field :image, :string
    field :image_position, :string, default: "left"
    field :status, :string, default: "draft"

    belongs_to :topic, PubQuizzer.Quiz.Topic

    timestamps(type: :utc_datetime)
  end

  def changeset(question, attrs) do
    question
    |> cast(attrs, [
      :prompt,
      :options,
      :correct_index,
      :position,
      :image,
      :image_position,
      :status
    ])
    |> normalize_image()
    |> validate_required([:prompt, :options, :correct_index])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:image_position, @image_positions)
    |> validate_length(:prompt, min: 1, max: 500)
    |> validate_length(:options, min: 2, max: 6)
    |> validate_options_text()
    |> validate_correct_index()
  end

  defp normalize_image(changeset) do
    update_change(changeset, :image, fn
      value when is_binary(value) -> if String.trim(value) == "", do: nil, else: value
      value -> value
    end)
  end

  defp validate_options_text(changeset) do
    options = get_field(changeset, :options)

    if is_list(options) do
      empty_text? =
        Enum.any?(options, fn opt ->
          text = if is_map(opt), do: Map.get(opt, "text", "") |> String.trim(), else: ""
          text == ""
        end)

      if empty_text?,
        do: add_error(changeset, :options, "jede Option muss einen Text haben"),
        else: changeset
    else
      changeset
    end
  end

  defp validate_correct_index(changeset) do
    options = get_field(changeset, :options)
    correct_index = get_field(changeset, :correct_index)

    cond do
      is_nil(options) or is_nil(correct_index) ->
        changeset

      correct_index < 0 or correct_index >= length(options) ->
        add_error(
          changeset,
          :correct_index,
          "must be between 0 and #{length(options) - 1}"
        )

      true ->
        changeset
    end
  end
end
