defmodule Receptionist.Scheduling.Contact do
  use Ecto.Schema
  import Ecto.Changeset

  schema "contacts" do
    field :first_name, :string
    field :last_name, :string
    field :email, :string
    field :phone_number, :string

    many_to_many :events, Receptionist.Scheduling.Event,
      join_through: "events_contacts",
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [:first_name, :last_name, :email, :phone_number])
    |> validate_required([:first_name, :last_name, :email, :phone_number])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
  end
end
