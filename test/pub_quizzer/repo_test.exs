defmodule PubQuizzer.RepoTest do
  use PubQuizzer.DataCase, async: false

  alias PubQuizzer.Quiz

  import Ecto.Adapters.SQL, only: [query!: 3]

  defp pragma(sql) do
    query!(Repo, sql, []).rows |> List.first() |> List.first()
  end

  describe "SQLite lock-avoidance configuration" do
    test "uses WAL journal mode" do
      assert pragma("PRAGMA journal_mode") == "wal"
    end

    test "waits up to 15s for the write lock instead of failing fast" do
      # exqlite applies :busy_timeout through a custom busy-handler NIF (see
      # Exqlite.Connection.set_busy_timeout/2), not via `PRAGMA busy_timeout`,
      # so that pragma reads 0 by design. Assert the configured value the
      # handler actually uses.
      assert Application.get_env(:pub_quizzer, PubQuizzer.Repo)[:busy_timeout] == 15_000
    end

    test "uses NORMAL synchronous (safe with WAL)" do
      assert pragma("PRAGMA synchronous") == 1
    end

    test "enforces foreign keys" do
      assert pragma("PRAGMA foreign_keys") == 1
    end
  end

  describe "concurrent writes" do
    test "many parallel inserts do not raise 'database is locked'" do
      {:ok, topic} =
        Quiz.create_topic(%{name: "Lock #{System.unique_integer([:positive])}"})

      results =
        1..20
        |> Task.async_stream(
          fn i ->
            Quiz.create_question(%{
              prompt: "Question #{i}",
              options: ["a", "b", "c", "d"],
              correct_index: 0,
              topic_id: topic.id,
              status: "published"
            })
          end,
          max_concurrency: 20,
          timeout: 30_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert length(results) == 20
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end
end
