defmodule Receptionist.Repo.Migrations.CreateContacts do
  use Ecto.Migration

  def change do
    create table(:contacts) do
      add :first_name, :string, null: false
      add :last_name, :string, null: false
      add :email, :string, null: false
      add :phone_number, :string, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
