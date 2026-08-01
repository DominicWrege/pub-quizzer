defmodule PubQuizzer.Repo.Migrations.AddImagePositionToQuestions do
  use Ecto.Migration

  def change do
    alter table(:questions) do
      add :image_position, :string, default: "left", null: false
    end
  end
end
