# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Receptionist.Repo.insert!(%Receptionist.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Receptionist.Scheduling
alias Receptionist.Scheduling.{Event, Contact}

# Clear existing data
Receptionist.Repo.delete_all(Event)
Receptionist.Repo.delete_all(Contact)

# Create contacts
{:ok, john} =
  Scheduling.create_contact(%{
    first_name: "John",
    last_name: "Doe",
    email: "john.doe@example.com",
    phone_number: "555-1234"
  })

{:ok, jane} =
  Scheduling.create_contact(%{
    first_name: "Jane",
    last_name: "Smith",
    email: "jane.smith@example.com",
    phone_number: "555-5678"
  })

{:ok, bob} =
  Scheduling.create_contact(%{
    first_name: "Bob",
    last_name: "Johnson",
    email: "bob.johnson@example.com",
    phone_number: "555-9012"
  })

{:ok, alice} =
  Scheduling.create_contact(%{
    first_name: "Alice",
    last_name: "Williams",
    email: "alice.williams@example.com",
    phone_number: "555-3456"
  })

{:ok, charlie} =
  Scheduling.create_contact(%{
    first_name: "Charlie",
    last_name: "Brown",
    email: "charlie.brown@example.com",
    phone_number: "555-7890"
  })

# Get today's date in UTC
today = Date.utc_today()
{:ok, base_datetime} = DateTime.new(today, ~T[00:00:00], "Etc/UTC")

# Create events for today and the next few days
events_data = [
  # Today's events
  %{
    name: "Morning Standup",
    description: "Daily team sync meeting",
    # 9 AM UTC
    start_time: DateTime.add(base_datetime, 9 * 3600, :second),
    # 9:30 AM UTC
    end_time: DateTime.add(base_datetime, 9 * 3600 + 30 * 60, :second),
    contact_ids: [john.id, jane.id]
  },
  %{
    name: "Client Meeting",
    description: "Quarterly review with ABC Corp",
    # 2 PM UTC
    start_time: DateTime.add(base_datetime, 14 * 3600, :second),
    # 3 PM UTC
    end_time: DateTime.add(base_datetime, 15 * 3600, :second),
    contact_ids: [alice.id]
  },
  %{
    name: "Product Demo",
    description: "New feature demonstration",
    # 4 PM UTC
    start_time: DateTime.add(base_datetime, 16 * 3600, :second),
    # 5 PM UTC
    end_time: DateTime.add(base_datetime, 17 * 3600, :second),
    contact_ids: [bob.id, charlie.id]
  },

  # Tomorrow's events
  %{
    name: "Team Lunch",
    description: "Monthly team building",
    # Tomorrow 12 PM UTC
    start_time: DateTime.add(base_datetime, 24 * 3600 + 12 * 3600, :second),
    # Tomorrow 1:30 PM UTC
    end_time: DateTime.add(base_datetime, 24 * 3600 + 13 * 3600 + 30 * 60, :second),
    contact_ids: [john.id, jane.id, bob.id, alice.id]
  },
  %{
    name: "Design Review",
    description: "Review new UI mockups",
    # Tomorrow 3 PM UTC
    start_time: DateTime.add(base_datetime, 24 * 3600 + 15 * 3600, :second),
    # Tomorrow 4 PM UTC
    end_time: DateTime.add(base_datetime, 24 * 3600 + 16 * 3600, :second),
    contact_ids: [jane.id]
  },

  # Day after tomorrow's events
  %{
    name: "Sprint Planning",
    description: "Plan next sprint tasks",
    # Day after tomorrow 10 AM UTC
    start_time: DateTime.add(base_datetime, 48 * 3600 + 10 * 3600, :second),
    # Day after tomorrow 12 PM UTC
    end_time: DateTime.add(base_datetime, 48 * 3600 + 12 * 3600, :second),
    contact_ids: [john.id, jane.id, bob.id]
  },
  %{
    name: "One-on-One",
    description: "Manager check-in",
    # Day after tomorrow 2 PM UTC
    start_time: DateTime.add(base_datetime, 48 * 3600 + 14 * 3600, :second),
    # Day after tomorrow 2:45 PM UTC
    end_time: DateTime.add(base_datetime, 48 * 3600 + 14 * 3600 + 45 * 60, :second),
    contact_ids: [alice.id]
  },

  # More events throughout the week
  %{
    name: "Workshop",
    description: "Elixir best practices",
    # 3 days from now 1 PM UTC
    start_time: DateTime.add(base_datetime, 72 * 3600 + 13 * 3600, :second),
    # 3 days from now 4 PM UTC
    end_time: DateTime.add(base_datetime, 72 * 3600 + 16 * 3600, :second),
    contact_ids: [charlie.id, john.id]
  },
  %{
    name: "Board Meeting",
    description: "Quarterly board review",
    # 4 days from now 3 PM UTC
    start_time: DateTime.add(base_datetime, 96 * 3600 + 15 * 3600, :second),
    # 4 days from now 5 PM UTC
    end_time: DateTime.add(base_datetime, 96 * 3600 + 17 * 3600, :second),
    contact_ids: [alice.id, bob.id]
  },
  %{
    name: "Training Session",
    description: "New employee onboarding",
    # 5 days from now 10 AM UTC
    start_time: DateTime.add(base_datetime, 120 * 3600 + 10 * 3600, :second),
    # 5 days from now 12 PM UTC
    end_time: DateTime.add(base_datetime, 120 * 3600 + 12 * 3600, :second),
    contact_ids: [jane.id, charlie.id]
  }
]

# Create events and associate contacts
for event_data <- events_data do
  contact_ids = Map.get(event_data, :contact_ids, [])
  event_attrs = Map.drop(event_data, [:contact_ids])

  {:ok, event} = Scheduling.create_event(event_attrs)

  # Associate contacts with the event using the join table
  contacts = Enum.map(contact_ids, &Receptionist.Repo.get!(Contact, &1))

  event
  |> Receptionist.Repo.preload(:contacts)
  |> Ecto.Changeset.change()
  |> Ecto.Changeset.put_assoc(:contacts, contacts)
  |> Receptionist.Repo.update!()
end

IO.puts("Seeded #{length(events_data)} events with contacts!")
