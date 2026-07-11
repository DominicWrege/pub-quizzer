defmodule PubQuizzer.Quiz.Team do
  use Ecto.Schema
  import Ecto.Changeset

  schema "teams" do
    field :name, :string
    field :slot_index, :integer
    field :claimed_at, :utc_datetime

    belongs_to :quiz_event, PubQuizzer.Quiz.QuizEvent

    timestamps(type: :utc_datetime)
  end

  def changeset(team, attrs) do
    team
    |> cast(attrs, [:name, :slot_index, :claimed_at, :quiz_event_id])
    |> validate_required([:name, :slot_index])
    |> validate_length(:name, min: 1, max: 50)
  end
end
