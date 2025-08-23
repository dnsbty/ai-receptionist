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
end
