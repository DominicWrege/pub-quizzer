defmodule PubQuizzer.Repo.Migrations.AddImageToQuestions do
  use Ecto.Migration

  def change do
    alter table(:questions) do
      add :image, :string
    end
  end
end
