defmodule Receptionist.Repo.Migrations.AddAgentConversationIdToContacts do
  use Ecto.Migration

  def change do
    alter table(:contacts) do
      add :agent_conversation_id, :string
    end
  end
end
