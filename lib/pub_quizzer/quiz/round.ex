defmodule PubQuizzer.Quiz.Round do
  use Ecto.Schema
  import Ecto.Changeset

  schema "rounds" do
    field :round_number, :integer

    belongs_to :topic, PubQuizzer.Quiz.Topic
    belongs_to :quiz_event, PubQuizzer.Quiz.QuizEvent
    belongs_to :chosen_by_team, PubQuizzer.Quiz.Team
    belongs_to :winner_team, PubQuizzer.Quiz.Team

    has_many :answers, PubQuizzer.Quiz.Answer

    timestamps(type: :utc_datetime)
  end

  def changeset(round, attrs) do
    round
    |> cast(attrs, [:round_number, :topic_id, :quiz_event_id, :chosen_by_team_id, :winner_team_id])
    |> validate_required([:round_number, :quiz_event_id])
  end
end
