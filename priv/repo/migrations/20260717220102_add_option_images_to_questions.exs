defmodule PubQuizzer.Repo.Migrations.AddOptionImagesToQuestions do
  use Ecto.Migration

  def up do
    transform_options("questions")
    transform_options("question_versions")
  end

  def down do
    revert_options("questions")
    revert_options("question_versions")
  end

  defp transform_options(table) do
    repo().query!("SELECT id, options FROM #{table} WHERE options IS NOT NULL", [], log: false)
    |> then(fn %{rows: rows} ->
      for [id, options_json] <- rows do
        new_options =
          options_json
          |> Jason.decode!()
          |> Enum.map(fn val -> %{"text" => val} end)
          |> Jason.encode!()

        repo().query!(
          "UPDATE #{table} SET options = ?1 WHERE id = ?2",
          [new_options, id],
          log: false
        )
      end
    end)
  end

  defp revert_options(table) do
    repo().query!("SELECT id, options FROM #{table} WHERE options IS NOT NULL", [], log: false)
    |> then(fn %{rows: rows} ->
      for [id, options_json] <- rows do
        old_options =
          options_json
          |> Jason.decode!()
          |> Enum.map(fn %{"text" => text} -> text end)
          |> Jason.encode!()

        repo().query!(
          "UPDATE #{table} SET options = ?1 WHERE id = ?2",
          [old_options, id],
          log: false
        )
      end
    end)
  end
end
