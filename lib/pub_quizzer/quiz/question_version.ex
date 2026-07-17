defmodule PubQuizzer.Quiz.QuestionVersion do
  use Ecto.Schema
  import Ecto.Changeset

  schema "question_versions" do
    field :prompt, :string
    field :options, {:array, :map}
    field :correct_index, :integer
    field :image, :string
    field :action, :string

    belongs_to :question, PubQuizzer.Quiz.Question
    belongs_to :user, PubQuizzer.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(question_version, attrs) do
    question_version
    |> cast(attrs, [:prompt, :options, :correct_index, :image, :action, :question_id, :user_id])
    |> validate_required([:prompt, :options, :correct_index, :action, :question_id])
  end
end
