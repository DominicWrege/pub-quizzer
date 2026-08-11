defmodule PubQuizzer.Repo.Migrations.AddTokenToTeams do
  use Ecto.Migration

  def change do
    alter table(:teams) do
      add :token, :string
    end

    create unique_index(:teams, [:token])
  end
end
