defmodule PubQuizzer.Accounts.AuthEmailTest do
  use PubQuizzer.DataCase, async: true

  import Swoosh.TestAssertions

  alias PubQuizzer.Accounts
  alias PubQuizzer.Accounts.AuthEmail

  describe "deliver_first_login_notice/2" do
    setup do
      moderator =
        Accounts.create_user!(%{email: "mod@test", name: "Mira Moderator", role: "moderator"})

      admin =
        Accounts.create_user!(%{email: "admin@test", name: "Ada Admin", role: "superadmin"})

      %{moderator: moderator, admin: admin}
    end

    test "delivers the notice to every superadmin", %{moderator: moderator, admin: admin} do
      second =
        Accounts.create_user!(%{email: "root@test", name: "Root Admin", role: "superadmin"})

      assert {:ok, _} = AuthEmail.deliver_first_login_notice(moderator, [admin, second])

      assert_email_sent(
        to: [{admin.name, admin.email}, {second.name, second.email}],
        subject: "#{moderator.name} hat sich zum ersten Mal angemeldet"
      )
    end

    test "mentions the moderator in both bodies", %{moderator: moderator, admin: admin} do
      assert {:ok, _} = AuthEmail.deliver_first_login_notice(moderator, [admin])

      assert_email_sent(fn email ->
        email.html_body =~ moderator.name and email.text_body =~ moderator.email
      end)
    end
  end
end
