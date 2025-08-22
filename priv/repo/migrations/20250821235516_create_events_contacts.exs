defmodule Receptionist.Repo.Migrations.CreateEventsContacts do
  use Ecto.Migration

  def change do
    create table(:events_contacts, primary_key: false) do
      add :event_id, references(:events, on_delete: :delete_all), primary_key: true
      add :contact_id, references(:contacts, on_delete: :delete_all), primary_key: true
    end

    create unique_index(:events_contacts, [:event_id, :contact_id])
  end
end
