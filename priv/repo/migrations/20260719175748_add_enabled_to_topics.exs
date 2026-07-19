defmodule PubQuizzer.Repo.Migrations.AddEnabledToTopics do
  use Ecto.Migration

  def change do
    alter table(:topics) do
      add :enabled, :boolean, default: true, null: false
    end
  end
end
