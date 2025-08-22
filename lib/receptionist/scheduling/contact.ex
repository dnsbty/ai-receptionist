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
    |> normalize_phone_number()
  end

  defp normalize_phone_number(changeset) do
    case get_change(changeset, :phone_number) do
      nil ->
        changeset

      phone ->
        # Default to US if no country code is provided
        case ExPhoneNumber.parse(phone, "US") do
          {:ok, parsed} ->
            e164 = ExPhoneNumber.format(parsed, :e164)
            put_change(changeset, :phone_number, e164)

          {:error, _reason} ->
            add_error(changeset, :phone_number, "is not a valid phone number")
        end
    end
  end
end
