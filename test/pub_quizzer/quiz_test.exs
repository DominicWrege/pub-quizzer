defmodule PubQuizzer.QuizTest do
  use PubQuizzer.DataCase, async: true

  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.{Topic, Question}

  describe "topics" do
    test "create_topic/1 with valid attrs creates a topic" do
      attrs = %{name: "Geography", description: "Capitals and rivers"}
      assert {:ok, %Topic{} = topic} = Quiz.create_topic(attrs)
      assert topic.name == "Geography"
      assert topic.description == "Capitals and rivers"
    end

    test "create_topic/1 without a name returns error" do
      assert {:error, changeset} = Quiz.create_topic(%{description: "no name"})
      assert errors_on(changeset)[:name] == ["can't be blank"]
    end

    test "create_topic/1 with duplicate name returns error" do
      Quiz.create_topic(%{name: "Music"})
      assert {:error, changeset} = Quiz.create_topic(%{name: "Music"})
      assert errors_on(changeset)[:name] == ["has already been taken"]
    end

    test "list_topics/0 returns topics ordered by name" do
      {:ok, _} = Quiz.create_topic(%{name: "Zoology"})
      {:ok, _} = Quiz.create_topic(%{name: "Art"})
      names = Enum.map(Quiz.list_topics(), & &1.name)
      assert names == ["Art", "Zoology"]
    end

    test "delete_topic/1 also deletes its questions" do
      {:ok, topic} = Quiz.create_topic(%{name: "Sports"})

      {:ok, _} =
        Quiz.create_question(%{
          prompt: "How many players on a soccer team?",
          options: ["9", "10", "11", "12"],
          correct_index: 2,
          topic_id: topic.id
        })

      Quiz.delete_topic(topic)
      assert Quiz.list_questions_for_topic(topic.id) == []
    end
  end

  describe "questions" do
    setup do
      {:ok, topic} = Quiz.create_topic(%{name: "Science"})
      %{topic: topic}
    end

    test "create_question/1 with valid attrs", %{topic: topic} do
      attrs = %{
        prompt: "What is H2O?",
        options: ["Water", "Salt", "Sugar", "Acid"],
        correct_index: 0,
        topic_id: topic.id
      }

      assert {:ok, %Question{} = q} = Quiz.create_question(attrs)
      assert q.prompt == "What is H2O?"
      assert q.options == ["Water", "Salt", "Sugar", "Acid"]
      assert q.correct_index == 0
    end

    test "create_question/1 with too few options returns error", %{topic: topic} do
      attrs = %{
        prompt: "True or false: the sky is blue",
        options: ["True"],
        correct_index: 0,
        topic_id: topic.id
      }

      assert {:error, changeset} = Quiz.create_question(attrs)
      assert errors_on(changeset)[:options] == ["should have at least 2 item(s)"]
    end

    test "create_question/1 with out-of-range correct_index returns error", %{topic: topic} do
      attrs = %{
        prompt: "Pick one",
        options: ["A", "B", "C", "D"],
        correct_index: 5,
        topic_id: topic.id
      }

      assert {:error, changeset} = Quiz.create_question(attrs)
      assert changeset.errors[:correct_index] != nil
    end

    test "create_question/1 without prompt returns error", %{topic: topic} do
      attrs = %{
        options: ["A", "B"],
        correct_index: 0,
        topic_id: topic.id
      }

      assert {:error, changeset} = Quiz.create_question(attrs)
      assert errors_on(changeset)[:prompt] == ["can't be blank"]
    end
  end
end
