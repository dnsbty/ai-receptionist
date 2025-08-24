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

# Lists of realistic first and last names for random generation
first_names = [
  "James",
  "Mary",
  "John",
  "Patricia",
  "Robert",
  "Jennifer",
  "Michael",
  "Linda",
  "William",
  "Elizabeth",
  "David",
  "Barbara",
  "Richard",
  "Susan",
  "Joseph",
  "Jessica",
  "Thomas",
  "Sarah",
  "Charles",
  "Karen",
  "Christopher",
  "Nancy",
  "Daniel",
  "Lisa",
  "Matthew",
  "Betty",
  "Anthony",
  "Helen",
  "Donald",
  "Sandra",
  "Mark",
  "Donna",
  "Paul",
  "Carol",
  "Steven",
  "Ruth",
  "Andrew",
  "Sharon",
  "Kenneth",
  "Michelle",
  "Joshua",
  "Laura",
  "Kevin",
  "Emily",
  "Brian",
  "Kimberly",
  "George",
  "Deborah",
  "Edward",
  "Dorothy",
  "Ronald",
  "Amy",
  "Timothy",
  "Angela",
  "Jason",
  "Ashley",
  "Jeffrey",
  "Brenda",
  "Ryan",
  "Emma",
  "Jacob",
  "Virginia",
  "Gary",
  "Kathleen",
  "Nicholas",
  "Pamela",
  "Eric",
  "Martha",
  "Jonathan",
  "Debra",
  "Stephen",
  "Amanda",
  "Larry",
  "Stephanie",
  "Justin",
  "Janet",
  "Scott",
  "Carolyn",
  "Brandon",
  "Christine",
  "Benjamin",
  "Marie",
  "Samuel",
  "Catherine",
  "Frank",
  "Frances",
  "Gregory",
  "Christina",
  "Raymond",
  "Samantha",
  "Alexander",
  "Nicole",
  "Patrick",
  "Judith",
  "Jack",
  "Andrea",
  "Dennis",
  "Olivia",
  "Jerry",
  "Ann",
  "Tyler",
  "Jean",
  "Aaron",
  "Alice"
]

last_names = [
  "Smith",
  "Johnson",
  "Williams",
  "Brown",
  "Jones",
  "Garcia",
  "Miller",
  "Davis",
  "Rodriguez",
  "Martinez",
  "Hernandez",
  "Lopez",
  "Gonzalez",
  "Wilson",
  "Anderson",
  "Thomas",
  "Taylor",
  "Moore",
  "Jackson",
  "Martin",
  "Lee",
  "Perez",
  "Thompson",
  "White",
  "Harris",
  "Sanchez",
  "Clark",
  "Ramirez",
  "Lewis",
  "Robinson",
  "Walker",
  "Young",
  "Allen",
  "King",
  "Wright",
  "Scott",
  "Torres",
  "Nguyen",
  "Hill",
  "Flores",
  "Green",
  "Adams",
  "Nelson",
  "Baker",
  "Hall",
  "Rivera",
  "Campbell",
  "Mitchell",
  "Carter",
  "Roberts",
  "Gomez",
  "Phillips",
  "Evans",
  "Turner",
  "Diaz",
  "Parker",
  "Cruz",
  "Edwards",
  "Collins",
  "Reyes",
  "Stewart",
  "Morris",
  "Morales",
  "Murphy",
  "Cook",
  "Rogers",
  "Gutierrez",
  "Ortiz",
  "Morgan",
  "Cooper",
  "Peterson",
  "Bailey",
  "Reed",
  "Kelly",
  "Howard",
  "Ramos",
  "Kim",
  "Cox",
  "Ward",
  "Richardson",
  "Watson",
  "Brooks",
  "Chavez",
  "Wood",
  "James",
  "Bennett",
  "Gray",
  "Mendoza",
  "Ruiz",
  "Hughes",
  "Price",
  "Alvarez",
  "Castillo",
  "Sanders",
  "Patel",
  "Myers",
  "Long",
  "Ross",
  "Foster",
  "Jimenez",
  "Powell",
  "Jenkins",
  "Perry",
  "Russell"
]

# Area codes for various US regions (using 555 prefix for all numbers)
area_codes = [
  "212",
  "415",
  "310",
  "713",
  "305",
  "312",
  "617",
  "404",
  "206",
  "801",
  "503",
  "602",
  "619",
  "720",
  "813",
  "702",
  "916",
  "480",
  "407",
  "214"
]

# Create 100 contacts with random names and phone numbers
contacts =
  for i <- 1..100 do
    first_name = Enum.random(first_names)
    last_name = Enum.random(last_names)
    area_code = Enum.random(area_codes)
    # Generate random last 4 digits (0000-9999)
    last_four = (:rand.uniform(10000) - 1) |> Integer.to_string() |> String.pad_leading(4, "0")

    {:ok, contact} =
      Scheduling.create_contact(%{
        first_name: first_name,
        last_name: last_name,
        email: "#{String.downcase(first_name)}.#{String.downcase(last_name)}#{i}@example.com",
        phone_number: "+1#{area_code}555#{last_four}"
      })

    contact
  end

IO.puts("Created #{length(contacts)} contacts!")

# Helper function to create datetime in Mountain Time and convert to UTC
create_event_time = fn date, hour, minute ->
  {:ok, mt_time} = DateTime.new(date, Time.new!(hour, minute, 0), "America/Denver")
  {:ok, utc_time} = DateTime.shift_zone(mt_time, "Etc/UTC")
  utc_time
end

# Generate random appointments for the next 4 weeks
# 25 appointments per week = 100 total appointments

# Start from the previous Sunday
today = Date.utc_today()
day_of_week = Date.day_of_week(today)
# day_of_week: 1 = Monday, 7 = Sunday
# Calculate days to go back to get to Sunday
days_since_sunday = rem(day_of_week, 7)
start_date = Date.add(today, -days_since_sunday)

IO.puts("Today's date: #{today}")
IO.puts("Starting from Sunday: #{start_date}")

# Business hours configuration
# M-F: 8am-6pm (8:00-18:00)
# Sat: 10am-4pm (10:00-16:00)
# Sun: Closed

# Helper function to check if two time ranges overlap
check_overlap = fn existing_start, existing_end, new_start, new_end ->
  # Two ranges overlap if one starts before the other ends
  not (DateTime.compare(new_end, existing_start) == :lt or
         DateTime.compare(new_start, existing_end) == :gt)
end

# Track all scheduled appointments to avoid overlaps
# Map of date -> list of {start_time, end_time} tuples
all_scheduled_slots = %{}

# Recursive function to create appointments without overlaps
create_week_appointments = fn week_start,
                              target_count,
                              scheduled_slots,
                              contacts,
                              create_event_time,
                              check_overlap ->
  create_appointments_recursive = fn create_appointments_recursive,
                                     current_count,
                                     current_slots,
                                     attempts ->
    if current_count >= target_count or attempts >= 500 do
      {current_count, current_slots, attempts}
    else
      # Pick a random contact
      contact = Enum.random(contacts)

      # Pick a random day within this week (Mon-Sat only)
      # 0-5 for Mon-Sat
      day_offset = :rand.uniform(6) - 1
      appointment_date = Date.add(week_start, day_offset)
      day_of_week = Date.day_of_week(appointment_date)

      # Skip Sunday (should not happen with 0-5 range, but double-check)
      if day_of_week != 7 do
        # Determine business hours based on day
        {start_hour, end_hour} =
          case day_of_week do
            # Saturday
            6 -> {10, 16}
            # Monday-Friday
            _ -> {8, 18}
          end

        # Generate random start time within business hours
        # Leave at least 30 minutes before closing
        latest_start = end_hour - 1
        hour = start_hour + :rand.uniform(latest_start - start_hour + 1) - 1
        # Start times at 00 or 30 minutes
        minute = Enum.random([0, 30])

        # Randomly choose 30 minutes or 1 hour duration
        duration_minutes = Enum.random([30, 60])

        # Create the appointment times
        start_time = create_event_time.(appointment_date, hour, minute)
        end_time = DateTime.add(start_time, duration_minutes * 60, :second)

        # Check if this time slot conflicts with existing appointments
        existing_slots = Map.get(current_slots, appointment_date, [])

        has_conflict =
          Enum.any?(existing_slots, fn {existing_start, existing_end} ->
            check_overlap.(existing_start, existing_end, start_time, end_time)
          end)

        # Only create the appointment if there's no conflict
        if not has_conflict do
          # Create full name for the contact
          full_name = "#{contact.first_name} #{contact.last_name}"

          # Create event with contact association in a single transaction
          {:ok, _event} =
            Scheduling.create_event(%{
              name: full_name,
              description: "Appointment with #{full_name}",
              start_time: start_time,
              end_time: end_time,
              contact_ids: [contact.id]
            })

          # Track this slot to prevent future overlaps
          updated_slots =
            Map.update(
              current_slots,
              appointment_date,
              [{start_time, end_time}],
              fn slots -> [{start_time, end_time} | slots] end
            )

          create_appointments_recursive.(
            create_appointments_recursive,
            current_count + 1,
            updated_slots,
            attempts + 1
          )
        else
          create_appointments_recursive.(
            create_appointments_recursive,
            current_count,
            current_slots,
            attempts + 1
          )
        end
      else
        create_appointments_recursive.(
          create_appointments_recursive,
          current_count,
          current_slots,
          attempts + 1
        )
      end
    end
  end

  create_appointments_recursive.(create_appointments_recursive, 0, scheduled_slots, 0)
end

# Create appointments for each week
all_scheduled_slots =
  Enum.reduce(0..3, %{}, fn week, scheduled_slots ->
    week_start = Date.add(start_date, week * 7)
    week_end = Date.add(start_date, week * 7 + 6)
    IO.puts("Week #{week}: #{week_start} to #{week_end}")

    {appointments_created, updated_slots, attempts} =
      create_week_appointments.(
        week_start,
        25,
        scheduled_slots,
        contacts,
        create_event_time,
        check_overlap
      )

    if appointments_created < 25 do
      IO.puts(
        "  Warning: Only created #{appointments_created} appointments for week #{week} (attempted #{attempts} times)"
      )
    else
      IO.puts("  Successfully created #{appointments_created} appointments for week #{week}")
    end

    updated_slots
  end)

IO.puts("Created 100 appointments over 4 weeks!")
