defmodule PubQuizzer.Quiz.Team do
  use Ecto.Schema
  import Ecto.Changeset

  schema "teams" do
    field :name, :string
    field :slot_index, :integer
    field :claimed_at, :utc_datetime
    field :token, :string
    field :link_code, :string

    belongs_to :quiz_event, PubQuizzer.Quiz.QuizEvent

    timestamps(type: :utc_datetime)
  end

  def changeset(team, attrs) do
    team
    |> cast(attrs, [:name, :slot_index, :claimed_at, :token, :quiz_event_id])
    |> validate_required([:name, :slot_index, :link_code])
    |> validate_length(:name, min: 1, max: 50)
    |> validate_format(:link_code, ~r/^[a-z]{3}$/)
    |> unique_constraint([:quiz_event_id, :link_code])
  end
end
