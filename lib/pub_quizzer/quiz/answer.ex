defmodule PubQuizzer.Quiz.Answer do
  use Ecto.Schema
  import Ecto.Changeset

  schema "answers" do
    field :selected_index, :integer

    belongs_to :question, PubQuizzer.Quiz.Question
    belongs_to :round, PubQuizzer.Quiz.Round
    belongs_to :team, PubQuizzer.Quiz.Team

    timestamps(type: :utc_datetime)
  end

  def changeset(answer, attrs) do
    answer
    |> cast(attrs, [:selected_index, :question_id, :round_id, :team_id])
    |> validate_required([:selected_index, :question_id, :round_id, :team_id])
    |> unique_constraint([:round_id, :question_id, :team_id],
      name: :answers_round_id_question_id_team_id_index
    )
  end
end
