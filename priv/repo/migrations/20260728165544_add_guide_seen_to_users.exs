defmodule PubQuizzer.Repo.Migrations.AddGuideSeenToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :guide_seen, :boolean, default: false, null: false
    end
  end
end
