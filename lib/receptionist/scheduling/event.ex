defmodule Receptionist.Scheduling.Event do
  use Ecto.Schema
  import Ecto.Changeset

  schema "events" do
    field :name, :string
    field :description, :string
    field :start_time, :utc_datetime
    field :end_time, :utc_datetime

    many_to_many :contacts, Receptionist.Scheduling.Contact,
      join_through: "events_contacts",
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:name, :description, :start_time, :end_time])
    |> validate_required([:name, :start_time, :end_time])
    |> validate_end_time_after_start_time()
  end

  defp validate_end_time_after_start_time(changeset) do
    start_time = get_field(changeset, :start_time)
    end_time = get_field(changeset, :end_time)

    if start_time && end_time && DateTime.compare(start_time, end_time) != :lt do
      add_error(changeset, :end_time, "must be after start time")
    else
      changeset
    end
  end
end