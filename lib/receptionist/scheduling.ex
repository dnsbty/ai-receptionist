defmodule Receptionist.Scheduling do
  @moduledoc """
  The Scheduling context.
  """

  import Ecto.Query, warn: false
  alias Receptionist.Repo

  alias Receptionist.Scheduling.Contact
  alias Receptionist.Scheduling.Event

  @doc """
  Returns events for a date range.
  """
  def list_events_in_range(start_datetime, end_datetime) do
    query =
      from e in Event,
        where: e.start_time < ^end_datetime and e.end_time > ^start_datetime,
        order_by: [asc: e.start_time],
        preload: [:contacts]

    Repo.all(query)
  end

  @doc """
  Returns paginated contacts with optional search.

  ## Examples

      iex> list_contacts()
      [%Contact{}, ...]

      iex> list_contacts(search: "john", page: 2)
      %{contacts: [...], page: 2, ...}

  """
  def list_contacts(opts \\ []) do
    search = Keyword.get(opts, :search, "")
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 25)

    query =
      from c in Contact,
        order_by: [asc: c.last_name, asc: c.first_name]

    query =
      if search != "" do
        search_term = "%#{String.downcase(search)}%"

        from c in query,
          where:
            like(fragment("LOWER(? || ' ' || ?)", c.first_name, c.last_name), ^search_term) or
              like(fragment("LOWER(?)", c.email), ^search_term) or
              like(fragment("LOWER(?)", c.phone_number), ^search_term)
      else
        query
      end

    total_count = Repo.aggregate(query, :count)

    contacts =
      query
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> Repo.all()

    %{
      contacts: contacts,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: ceil(total_count / per_page)
    }
  end

  @doc """
  Gets a single contact.

  Raises `Ecto.NoResultsError` if the Contact does not exist.

  ## Examples

      iex> get_contact!(123)
      %Contact{}

      iex> get_contact!(456)
      ** (Ecto.NoResultsError)

  """
  def get_contact!(id), do: Repo.get!(Contact, id)

  @doc """
  Gets a single contact with events preloaded.
  """
  def get_contact_with_events!(id) do
    Contact
    |> Repo.get!(id)
    |> Repo.preload(events: from(e in Event, order_by: [desc: e.start_time]))
  end

  @doc """
  Creates a contact.

  ## Examples

      iex> create_contact(%{field: value})
      {:ok, %Contact{}}

      iex> create_contact(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_contact(attrs \\ %{}) do
    %Contact{}
    |> Contact.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a contact.

  ## Examples

      iex> update_contact(contact, %{field: new_value})
      {:ok, %Contact{}}

      iex> update_contact(contact, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_contact(%Contact{} = contact, attrs) do
    contact
    |> Contact.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a contact.

  ## Examples

      iex> delete_contact(contact)
      {:ok, %Contact{}}

      iex> delete_contact(contact)
      {:error, %Ecto.Changeset{}}

  """
  def delete_contact(%Contact{} = contact) do
    Repo.delete(contact)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking contact changes.

  ## Examples

      iex> change_contact(contact)
      %Ecto.Changeset{data: %Contact{}}

  """
  def change_contact(%Contact{} = contact, attrs \\ %{}) do
    Contact.changeset(contact, attrs)
  end

  @doc """
  Returns the list of events.

  ## Examples

      iex> list_events()
      [%Event{}, ...]

  """
  def list_events do
    Repo.all(Event)
  end

  @doc """
  Gets a single event.

  Raises `Ecto.NoResultsError` if the Event does not exist.

  ## Examples

      iex> get_event!(123)
      %Event{}

      iex> get_event!(456)
      ** (Ecto.NoResultsError)

  """
  def get_event!(id) do
    Event
    |> Repo.get!(id)
    |> Repo.preload(:contacts)
  end

  @doc """
  Creates a event.

  ## Examples

      iex> create_event(%{field: value})
      {:ok, %Event{}}

      iex> create_event(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_event(attrs \\ %{}) do
    # Extract contact_ids if provided
    {contact_ids, event_attrs} = Map.pop(attrs, :contact_ids, [])
    changeset = Event.changeset(%Event{}, event_attrs)

    # If contact_ids are provided, associate them with the event
    changeset =
      if contact_ids != [] do
        contacts = Repo.all(from c in Contact, where: c.id in ^contact_ids)
        Ecto.Changeset.put_assoc(changeset, :contacts, contacts)
      else
        changeset
      end

    Repo.insert(changeset)
  end

  @doc """
  Updates a event.

  ## Examples

      iex> update_event(event, %{field: new_value})
      {:ok, %Event{}}

      iex> update_event(event, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_event(%Event{} = event, attrs) do
    event
    |> Event.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a event.

  ## Examples

      iex> delete_event(event)
      {:ok, %Event{}}

      iex> delete_event(event)
      {:error, %Ecto.Changeset{}}

  """
  def delete_event(%Event{} = event) do
    Repo.delete(event)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking event changes.

  ## Examples

      iex> change_event(event)
      %Ecto.Changeset{data: %Event{}}

  """
  def change_event(%Event{} = event, attrs \\ %{}) do
    Event.changeset(event, attrs)
  end

  @doc """
  Finds the next available time slots starting from a given time.

  Takes a start_time (DateTime) and duration (30 or 60 minutes) and returns
  the next ten available time windows that have at least the requested duration.

  Returns a list of {start_time, open_duration} tuples where open_duration
  is the total minutes available in that slot.

  ## Examples

      iex> find_available_time_slots(~U[2025-08-25 14:00:00Z], 30)
      [
        {~U[2025-08-25 14:00:00Z], 60},
        {~U[2025-08-25 15:30:00Z], 90},
        {~U[2025-08-26 14:00:00Z], 120}
      ]
  """
  def find_available_time_slots(start_time, requested_duration)
      when requested_duration in [30, 60] do
    # Define business hours in UTC (adjust these based on Mountain Time offset)
    # Mountain Time is UTC-6 in summer, so 8am-6pm MT = 2pm UTC-midnight UTC
    # We'll use 23:59 instead of 24:00 for the end time
    # Saturday 10am-4pm MT = 4pm-10pm UTC (16:00-22:00)
    business_hours = %{
      # Monday (2pm-11:59pm UTC = 8am-5:59pm MT)
      1 => {14, 23},
      # Tuesday
      2 => {14, 23},
      # Wednesday
      3 => {14, 23},
      # Thursday
      4 => {14, 23},
      # Friday
      5 => {14, 23},
      # Saturday (4pm-10pm UTC = 10am-4pm MT)
      6 => {16, 22},
      # Sunday (closed)
      7 => nil
    }

    # Get events for the next 30 days
    end_search = DateTime.add(start_time, 30 * 24 * 3600, :second)
    existing_events = list_events_in_range(start_time, end_search)

    # Group events by date for easier lookup
    events_by_date =
      Enum.group_by(existing_events, fn event ->
        DateTime.to_date(event.start_time)
      end)

    # Find available slots
    find_slots_recursive(
      start_time,
      end_search,
      requested_duration,
      business_hours,
      events_by_date,
      [],
      10
    )
  end

  defp find_slots_recursive(
         _current_time,
         _end_time,
         _requested_duration,
         _business_hours,
         _events_by_date,
         slots,
         0
       ) do
    # Found enough slots
    Enum.reverse(slots)
  end

  defp find_slots_recursive(
         current_time,
         end_time,
         requested_duration,
         business_hours,
         events_by_date,
         slots,
         needed
       ) do
    if DateTime.compare(current_time, end_time) == :gt do
      # Reached end of search period
      Enum.reverse(slots)
    else
      current_date = DateTime.to_date(current_time)
      day_of_week = Date.day_of_week(current_date)

      case Map.get(business_hours, day_of_week) do
        nil ->
          # Closed day, move to next day at start of business
          next_day = DateTime.new!(Date.add(current_date, 1), ~T[00:00:00], "Etc/UTC")

          find_slots_recursive(
            next_day,
            end_time,
            requested_duration,
            business_hours,
            events_by_date,
            slots,
            needed
          )

        {start_hour, end_hour} ->
          # Get current time's hour and minute
          current_hour = current_time.hour
          current_minute = current_time.minute

          # Round up to next 30-minute slot
          slot_minute = if current_minute < 30, do: 30, else: 0
          slot_hour = if current_minute < 30, do: current_hour, else: current_hour + 1

          # Check if we're within business hours
          if slot_hour < start_hour do
            # Before business hours, jump to start of business
            slot_time = DateTime.new!(current_date, Time.new!(start_hour, 0, 0), "Etc/UTC")

            find_slots_recursive(
              slot_time,
              end_time,
              requested_duration,
              business_hours,
              events_by_date,
              slots,
              needed
            )
          else
            if slot_hour >= end_hour do
              # After business hours, move to next day
              next_day = DateTime.new!(Date.add(current_date, 1), ~T[00:00:00], "Etc/UTC")

              find_slots_recursive(
                next_day,
                end_time,
                requested_duration,
                business_hours,
                events_by_date,
                slots,
                needed
              )
            else
              # Within business hours, check for availability
              slot_time =
                DateTime.new!(current_date, Time.new!(slot_hour, slot_minute, 0), "Etc/UTC")

              # Get events for this date
              day_events = Map.get(events_by_date, current_date, [])

              # Find how much time is available from this slot
              available_minutes = calculate_available_duration(slot_time, end_hour, day_events)

              if available_minutes >= requested_duration do
                # Found a valid slot
                new_slot = {slot_time, available_minutes}
                new_slots = [new_slot | slots]

                # Move to after this slot for next search
                next_time = DateTime.add(slot_time, available_minutes * 60, :second)

                find_slots_recursive(
                  next_time,
                  end_time,
                  requested_duration,
                  business_hours,
                  events_by_date,
                  new_slots,
                  needed - 1
                )
              else
                # Not enough time available, try next slot
                next_time = DateTime.add(slot_time, 30 * 60, :second)

                find_slots_recursive(
                  next_time,
                  end_time,
                  requested_duration,
                  business_hours,
                  events_by_date,
                  slots,
                  needed
                )
              end
            end
          end
      end
    end
  end

  defp calculate_available_duration(start_time, business_end_hour, day_events) do
    # Calculate end of business day
    # If end hour is 23, we want 23:59:59 (end of day)
    {end_hour, end_minute, end_second} =
      if business_end_hour == 23 do
        {23, 59, 59}
      else
        {business_end_hour, 0, 0}
      end

    business_end =
      DateTime.new!(
        DateTime.to_date(start_time),
        Time.new!(end_hour, end_minute, end_second),
        "Etc/UTC"
      )

    # Find the next event that would block this slot
    next_blocking_event =
      day_events
      |> Enum.filter(fn event ->
        # Event starts after our start time or overlaps with it
        DateTime.compare(event.end_time, start_time) == :gt
      end)
      |> Enum.sort_by(& &1.start_time, DateTime)
      |> List.first()

    # Calculate available duration
    end_time =
      case next_blocking_event do
        nil ->
          # No blocking event, available until end of business
          business_end

        event ->
          # Check if event starts after our slot
          if DateTime.compare(event.start_time, start_time) == :gt do
            # Available until the event starts
            event.start_time
          else
            # Event overlaps with our start time, no availability
            start_time
          end
      end

    # Calculate duration in minutes
    max(0, div(DateTime.diff(end_time, start_time), 60))
  end
end
