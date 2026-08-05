defmodule PubQuizzer.Repo.Migrations.AddLayoutToQuestions do
  use Ecto.Migration

  def up do
    alter table(:questions) do
      add :layout, :string, default: "classic", null: false
    end

    alter table(:question_versions) do
      add :layout, :string
    end

    # Preserve current visual: any question that currently shows an image
    # (and therefore uses the left/right split) becomes "image_side"; the
    # rest default to "classic".
    execute "UPDATE questions SET layout = 'image_side' WHERE image IS NOT NULL AND image != ''"
  end

  def down do
    alter table(:question_versions) do
      remove :layout
    end

    alter table(:questions) do
      remove :layout
    end
  end
end
