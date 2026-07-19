defmodule PubQuizzer.Quiz.Topic do
  use Ecto.Schema
  import Ecto.Changeset

  schema "topics" do
    field :name, :string
    field :description, :string
    field :enabled, :boolean, default: true

    has_many :questions, PubQuizzer.Quiz.Question

    timestamps(type: :utc_datetime)
  end

  def changeset(topic, attrs) do
    topic
    |> cast(attrs, [:name, :description, :enabled])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint(:name)
  end
end
