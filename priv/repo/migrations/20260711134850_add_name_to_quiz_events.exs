defmodule PubQuizzer.Repo.Migrations.AddNameToQuizEvents do
  use Ecto.Migration

  def change do
    alter table(:quiz_events) do
      add :name, :string
    end
  end
end
