defmodule Receptionist.Repo.Migrations.CreateContacts do
  use Ecto.Migration

  def change do
    create table(:contacts) do
      add :first_name, :string
      add :last_name, :string
      add :email, :string
      add :phone_number, :string, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
