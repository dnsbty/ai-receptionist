defmodule Receptionist.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :name, :string, null: false
      add :description, :text
      add :start_time, :utc_datetime, null: false
      add :end_time, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
