defmodule PubQuizzer.Quiz.Question do
  use Ecto.Schema
  import Ecto.Changeset

  schema "questions" do
    field :prompt, :string
    field :options, {:array, :string}
    field :correct_index, :integer
    field :position, :integer, default: 0
    field :image, :string

    belongs_to :topic, PubQuizzer.Quiz.Topic

    timestamps(type: :utc_datetime)
  end

  def changeset(question, attrs) do
    question
    |> cast(attrs, [:prompt, :options, :correct_index, :position, :image])
    |> validate_required([:prompt, :options, :correct_index])
    |> validate_length(:prompt, min: 1, max: 500)
    |> validate_length(:options, min: 2, max: 6)
    |> validate_correct_index()
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
