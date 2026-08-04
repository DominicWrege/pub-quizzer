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

      assert q.options == [
               %{"text" => "Water"},
               %{"text" => "Salt"},
               %{"text" => "Sugar"},
               %{"text" => "Acid"}
             ]

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

    test "list_questions_for_topic/1 attaches last_editor_name from latest version", %{
      topic: topic
    } do
      question = insert_question(topic)
      user = insert_user()

      Quiz.create_question_version!(question, user, "create")

      [loaded] = Quiz.list_questions_for_topic(topic.id)
      assert loaded.last_editor_name == user.name
    end

    test "list_questions_for_topic/1 returns nil last_editor_name when no versions exist", %{
      topic: topic
    } do
      _question = insert_question(topic)
      [loaded] = Quiz.list_questions_for_topic(topic.id)
      assert loaded.last_editor_name == nil
    end

    test "create_question/1 defaults new questions to published", %{topic: topic} do
      {:ok, q} =
        Quiz.create_question(%{
          prompt: "New question",
          options: ["A", "B", "C", "D"],
          correct_index: 0,
          topic_id: topic.id
        })

      assert q.status == "published"
    end

    test "list_published_questions_for_topic/1 excludes drafts", %{topic: topic} do
      {:ok, _draft} =
        Quiz.create_question(%{
          prompt: "Draft",
          options: ["A", "B"],
          correct_index: 0,
          topic_id: topic.id,
          status: "draft"
        })

      {:ok, published} =
        Quiz.create_question(%{
          prompt: "Published",
          options: ["A", "B"],
          correct_index: 0,
          topic_id: topic.id,
          status: "published"
        })

      assert Enum.map(Quiz.list_published_questions_for_topic(topic.id), & &1.id) == [
               published.id
             ]
    end

    test "create_question/1 appends increasing positions per topic", %{topic: topic} do
      {:ok, other_topic} = Quiz.create_topic(%{name: "Other"})

      {:ok, q1} = create_simple_question(topic, "First")
      {:ok, q2} = create_simple_question(topic, "Second")
      {:ok, q3} = create_simple_question(other_topic, "Other topic")

      assert q1.position == 0
      assert q2.position == 1
      assert q3.position == 0
    end

    test "reorder_questions/2 sets positions to the given order", %{topic: topic} do
      {:ok, q1} = create_simple_question(topic, "First")
      {:ok, q2} = create_simple_question(topic, "Second")
      {:ok, q3} = create_simple_question(topic, "Third")

      assert {:ok, _questions} = Quiz.reorder_questions(topic.id, [q3.id, q1.id, q2.id])

      prompts = Enum.map(Quiz.list_questions_for_topic(topic.id), & &1.prompt)
      assert prompts == ["Third", "First", "Second"]
    end

    test "reorder_questions/2 returns mismatch when ids do not match", %{topic: topic} do
      {:ok, q1} = create_simple_question(topic, "First")

      assert {:error, :mismatch} = Quiz.reorder_questions(topic.id, [q1.id, -1])
      assert {:error, :mismatch} = Quiz.reorder_questions(topic.id, [])
    end

    test "list_topic_names/0 excludes topics that only have draft questions" do
      {:ok, draft_topic} = Quiz.create_topic(%{name: "Draft Only"})
      {:ok, live_topic} = Quiz.create_topic(%{name: "Has Published"})

      {:ok, _} =
        Quiz.create_question(%{
          prompt: "Draft q",
          options: ["A", "B"],
          correct_index: 0,
          topic_id: draft_topic.id,
          status: "draft"
        })

      {:ok, _} =
        Quiz.create_question(%{
          prompt: "Live q",
          options: ["A", "B"],
          correct_index: 0,
          topic_id: live_topic.id,
          status: "published"
        })

      ids = Enum.map(Quiz.list_topic_names(), & &1.id)
      assert live_topic.id in ids
      refute draft_topic.id in ids
    end
  end

  defp create_simple_question(topic, prompt) do
    Quiz.create_question(%{
      prompt: prompt,
      options: ["A", "B", "C", "D"],
      correct_index: 0,
      topic_id: topic.id
    })
  end

  defp insert_question(topic) do
    {:ok, q} =
      Quiz.create_question(%{
        prompt: "What is H2O?",
        options: ["Water", "Salt", "Sugar", "Acid"],
        correct_index: 0,
        topic_id: topic.id
      })

    q
  end

  defp insert_user do
    {:ok, user} =
      PubQuizzer.Accounts.create_user(%{
        email: "editor@test.com",
        name: "Editor",
        password: "password123"
      })

    user
  end
end
