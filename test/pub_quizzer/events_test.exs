defmodule PubQuizzer.EventsTest do
  use PubQuizzer.DataCase, async: false

  alias PubQuizzer.Quiz
  alias PubQuizzer.Names

  describe "create_event/1" do
    test "creates an event with a 4-digit code and N team slots" do
      {:ok, event} = Quiz.create_event(%{team_count: 5})

      assert event.code =~ ~r/^\d{4}$/
      assert event.status == "lobby"
      assert event.team_count == 5
      assert length(event.teams) == 5

      for team <- event.teams do
        assert team.name != nil
        assert team.claimed_at == nil
      end

      # Slot indices are sequential
      indices = Enum.map(event.teams, & &1.slot_index)
      assert indices == [0, 1, 2, 3, 4]
    end

    test "team names are unique within the event" do
      {:ok, event} = Quiz.create_event(%{team_count: 5})
      names = Enum.map(event.teams, & &1.name)
      assert length(names) == length(Enum.uniq(names))
    end
  end

  describe "get_event_by_code/1" do
    test "returns the event with teams preloaded" do
      {:ok, event} = Quiz.create_event(%{team_count: 3})
      found = Quiz.get_event_by_code(event.code)
      assert found.id == event.id
      assert length(found.teams) == 3
    end

    test "returns nil for non-existent code" do
      assert Quiz.get_event_by_code("9999") == nil
    end
  end

  describe "claim_next_team_slot/1" do
    test "claims the first unclaimed slot" do
      {:ok, event} = Quiz.create_event(%{team_count: 3})
      {:ok, team} = Quiz.claim_next_team_slot(event)
      assert team.claimed_at != nil
      assert team.slot_index == 0
    end

    test "claims slots in order" do
      {:ok, event} = Quiz.create_event(%{team_count: 3})
      {:ok, t1} = Quiz.claim_next_team_slot(event)
      {:ok, t2} = Quiz.claim_next_team_slot(event)
      assert t1.slot_index == 0
      assert t2.slot_index == 1
    end

    test "returns :full when all slots claimed" do
      {:ok, event} = Quiz.create_event(%{team_count: 2})
      {:ok, _} = Quiz.claim_next_team_slot(event)
      {:ok, _} = Quiz.claim_next_team_slot(event)
      assert {:error, :full} = Quiz.claim_next_team_slot(event)
    end
  end

  describe "team management" do
    test "add_team_slot adds one slot and increments team_count" do
      {:ok, event} = Quiz.create_event(%{team_count: 3})
      {:ok, updated, team} = Quiz.add_team_slot(event)
      assert updated.team_count == 4
      assert team.slot_index == 3
    end

    test "remove_team_slot removes the last unclaimed slot" do
      {:ok, event} = Quiz.create_event(%{team_count: 3})
      {:ok, updated} = Quiz.remove_team_slot(event)
      assert updated.team_count == 2
      teams = Quiz.list_teams_for_event(event.id)
      assert length(teams) == 2
    end

    test "remove_team_slot fails if last slot is claimed" do
      {:ok, event} = Quiz.create_event(%{team_count: 2})
      {:ok, _} = Quiz.claim_next_team_slot(event)
      {:ok, _} = Quiz.claim_next_team_slot(event)
      assert {:error, :team_claimed} = Quiz.remove_team_slot(event)
    end

    test "update_team_name renames a team" do
      {:ok, event} = Quiz.create_event(%{team_count: 1})
      team = hd(event.teams)
      {:ok, updated} = Quiz.update_team_name(team, "The Quizlamic State")
      assert updated.name == "The Quizlamic State"
    end
  end

  describe "start_event/1" do
    test "transitions from lobby to topic_selection" do
      {:ok, event} = Quiz.create_event(%{team_count: 2})
      {:ok, started} = Quiz.start_event(event)
      assert started.status == "topic_selection"
      assert started.started_at != nil
    end
  end

  describe "team_belongs_to_event?/2" do
    test "returns true if team belongs to event" do
      {:ok, event} = Quiz.create_event(%{team_count: 2})
      team = hd(event.teams)
      assert Quiz.team_belongs_to_event?(team.id, event.id)
    end

    test "returns false if team does not belong to event" do
      {:ok, event1} = Quiz.create_event(%{team_count: 2})
      {:ok, event2} = Quiz.create_event(%{team_count: 2})
      team = hd(event1.teams)
      refute Quiz.team_belongs_to_event?(team.id, event2.id)
    end
  end

  describe "Names" do
    test "generate/0 returns 'Team 1'" do
      name = Names.generate()
      assert name == "Team 1"
    end

    test "generate_many/1 returns N sequential names" do
      names = Names.generate_many(5)
      assert names == ["Team 1", "Team 2", "Team 3", "Team 4", "Team 5"]
    end

    test "generate/1 avoids existing names by incrementing" do
      existing = MapSet.new(["Team 1", "Team 2"])
      name = Names.generate(existing)
      assert name == "Team 3"
    end
  end
end
