defmodule ReceptionistWeb.CalendarLive do
  use ReceptionistWeb, :live_view
  alias Receptionist.Scheduling
  import ReceptionistWeb.PhoneHelper

  @impl true
  def mount(_params, _session, socket) do
    timezone = get_connect_params(socket)["timezone"] || "UTC"
    today = today_in_timezone(timezone)

    socket =
      socket
      |> assign(:timezone, timezone)
      |> assign(:current_date, today)
      |> assign(:selected_event, nil)
      |> assign(:show_create_modal, false)
      |> assign(:all_contacts, list_all_contacts())
      |> assign(:selected_contact_ids, [])
      |> assign(:contact_search, "")
      |> assign(:form, to_form(Scheduling.change_event(%Scheduling.Event{})))
      |> load_events()

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    event = Scheduling.get_event!(id)
    {:noreply, assign(socket, :selected_event, event)}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :selected_event, nil)}
  end

  @impl true
  def handle_event("prev_day", _params, socket) do
    new_date = Date.add(socket.assigns.current_date, -1)

    socket =
      socket
      |> assign(:current_date, new_date)
      |> load_events()

    {:noreply, socket}
  end

  @impl true
  def handle_event("next_day", _params, socket) do
    new_date = Date.add(socket.assigns.current_date, 1)

    socket =
      socket
      |> assign(:current_date, new_date)
      |> load_events()

    {:noreply, socket}
  end

  @impl true
  def handle_event("prev_week", _params, socket) do
    new_date = Date.add(socket.assigns.current_date, -7)

    socket =
      socket
      |> assign(:current_date, new_date)
      |> load_events()

    {:noreply, socket}
  end

  @impl true
  def handle_event("next_week", _params, socket) do
    new_date = Date.add(socket.assigns.current_date, 7)

    socket =
      socket
      |> assign(:current_date, new_date)
      |> load_events()

    {:noreply, socket}
  end

  @impl true
  def handle_event("today", _params, socket) do
    today = today_in_timezone(socket.assigns.timezone)

    socket =
      socket
      |> assign(:current_date, today)
      |> load_events()

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/")}
  end

  @impl true
  def handle_event("open_create_modal", _params, socket) do
    changeset = Scheduling.change_event(%Scheduling.Event{})

    {:noreply,
     socket
     |> assign(:show_create_modal, true)
     |> assign(:selected_contact_ids, [])
     |> assign(:contact_search, "")
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("close_create_modal", _params, socket) do
    {:noreply, assign(socket, :show_create_modal, false)}
  end

  @impl true
  def handle_event("add_contact", %{"contact_id" => contact_id}, socket) do
    contact_id = String.to_integer(contact_id)
    selected_ids = Enum.uniq([contact_id | socket.assigns.selected_contact_ids])

    {:noreply,
     socket
     |> assign(:selected_contact_ids, selected_ids)
     |> assign(:contact_search, "")}
  end

  @impl true
  def handle_event("remove_contact", %{"contact_id" => contact_id}, socket) do
    contact_id = String.to_integer(contact_id)
    selected_ids = List.delete(socket.assigns.selected_contact_ids, contact_id)

    {:noreply, assign(socket, :selected_contact_ids, selected_ids)}
  end

  @impl true
  def handle_event("search_contacts", %{"value" => search}, socket) do
    {:noreply, assign(socket, :contact_search, search)}
  end

  @impl true
  def handle_event("search_contacts", %{"search" => search}, socket) do
    {:noreply, assign(socket, :contact_search, search)}
  end

  @impl true
  def handle_event("validate_event", %{"event" => event_params}, socket) do
    # Only validate the actual Event fields (name and description)
    # Keep the date/time fields as they are in the form
    event_fields = Map.take(event_params, ["name", "description"])

    changeset =
      %Scheduling.Event{}
      |> Scheduling.change_event(event_fields)
      |> Map.put(:action, :validate)

    # Preserve the date and time input values
    form = to_form(changeset, as: :event)

    {:noreply, assign(socket, form: form)}
  end

  @impl true
  def handle_event("save_event", %{"event" => event_params}, socket) do
    # Convert date and time inputs to UTC datetime
    with {:ok, start_datetime} <-
           parse_datetime(
             event_params["start_date"],
             event_params["start_time"],
             socket.assigns.timezone
           ),
         {:ok, end_datetime} <-
           parse_datetime(
             event_params["end_date"],
             event_params["end_time"],
             socket.assigns.timezone
           ) do
      # Build params with atom keys for the changeset
      event_params = %{
        name: event_params["name"],
        description: event_params["description"],
        start_time: start_datetime,
        end_time: end_datetime
      }

      case Scheduling.create_event(event_params) do
        {:ok, event} ->
          # Associate contacts with the event
          if length(socket.assigns.selected_contact_ids) > 0 do
            contacts = Enum.map(socket.assigns.selected_contact_ids, &Scheduling.get_contact!/1)

            event
            |> Receptionist.Repo.preload(:contacts)
            |> Ecto.Changeset.change()
            |> Ecto.Changeset.put_assoc(:contacts, contacts)
            |> Receptionist.Repo.update!()
          end

          {:noreply,
           socket
           |> assign(:show_create_modal, false)
           |> load_events()
           |> put_flash(:info, "Event created successfully")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           socket
           |> assign(form: to_form(changeset))
           |> put_flash(:error, "Failed to create event. Please check the form.")}
      end
    else
      _error -> {:noreply, put_flash(socket, :error, "Invalid date or time format")}
    end
  end

  defp parse_datetime(date_string, time_string, timezone) do
    # Add seconds if not present
    time_string =
      if String.contains?(time_string, ":") and String.length(time_string) == 5 do
        time_string <> ":00"
      else
        time_string
      end

    with {:ok, date} <- Date.from_iso8601(date_string),
         {:ok, time} <- Time.from_iso8601(time_string),
         {:ok, naive_datetime} <- NaiveDateTime.new(date, time),
         {:ok, datetime} <- DateTime.from_naive(naive_datetime, timezone),
         {:ok, utc_datetime} <- DateTime.shift_zone(datetime, "Etc/UTC") do
      {:ok, utc_datetime}
    else
      _error -> :error
    end
  end

  defp load_events(socket) do
    # Load both day and week ranges to support responsive view
    day_dates = [socket.assigns.current_date]

    week_dates =
      Enum.map(0..6, fn days ->
        Date.add(socket.assigns.current_date, days)
      end)

    # Get all dates we need (union of both)
    all_dates = Enum.uniq(day_dates ++ week_dates)

    # Get the range for all dates in one query
    {first_date, last_date} = Enum.min_max(all_dates)
    start_of_range = date_to_datetime(first_date, socket.assigns.timezone, :start)
    end_of_range = date_to_datetime(last_date, socket.assigns.timezone, :end)

    # Fetch all events in a single query
    all_events = Scheduling.list_events_in_range(start_of_range, end_of_range)

    # Group events by date for ALL possible dates
    events_by_date =
      all_dates
      |> Enum.reduce(%{}, fn date, acc ->
        start_of_day = date_to_datetime(date, socket.assigns.timezone, :start)
        end_of_day = date_to_datetime(date, socket.assigns.timezone, :end)

        # Filter events for this specific day from the already-loaded events
        events_for_day =
          Enum.filter(all_events, fn event ->
            DateTime.compare(event.start_time, end_of_day) == :lt &&
              DateTime.compare(event.end_time, start_of_day) == :gt
          end)

        Map.put(acc, date, events_for_day)
      end)

    assign(socket, :events_by_date, events_by_date)
  end

  defp get_week_dates(current_date) do
    Enum.map(0..6, fn days ->
      Date.add(current_date, days)
    end)
  end

  defp today_in_timezone(_timezone) do
    # For simplicity, using UTC today
    # In production, you'd want to use a proper timezone library
    Date.utc_today()
  end

  defp date_to_datetime(date, timezone, :start) do
    # Create the start of day in the user's timezone, then convert to UTC
    {:ok, naive} = NaiveDateTime.new(date, ~T[00:00:00])

    case DateTime.from_naive(naive, timezone) do
      {:ok, local_dt} ->
        case DateTime.shift_zone(local_dt, "Etc/UTC") do
          {:ok, utc_dt} ->
            utc_dt

          {:error, _} ->
            # Fallback if timezone conversion fails
            {:ok, dt} = DateTime.new(date, ~T[00:00:00])
            dt
        end

      {:error, _} ->
        # Fallback if timezone conversion fails
        {:ok, dt} = DateTime.new(date, ~T[00:00:00])
        dt
    end
  end

  defp date_to_datetime(date, timezone, :end) do
    # Create the end of day in the user's timezone, then convert to UTC
    {:ok, naive} = NaiveDateTime.new(date, ~T[23:59:59])

    case DateTime.from_naive(naive, timezone) do
      {:ok, local_dt} ->
        case DateTime.shift_zone(local_dt, "Etc/UTC") do
          {:ok, utc_dt} ->
            utc_dt

          {:error, _} ->
            # Fallback if timezone conversion fails
            {:ok, dt} = DateTime.new(date, ~T[23:59:59])
            dt
        end

      {:error, _} ->
        # Fallback if timezone conversion fails
        {:ok, dt} = DateTime.new(date, ~T[23:59:59])
        dt
    end
  end

  defp format_time(datetime, timezone) do
    # Convert from UTC to the user's timezone for display
    local_datetime =
      case DateTime.shift_zone(datetime, timezone) do
        {:ok, local} -> local
        # Fallback to UTC if timezone conversion fails
        {:error, _} -> datetime
      end

    hour = local_datetime.hour
    minute = local_datetime.minute |> Integer.to_string() |> String.pad_leading(2, "0")

    {hour_12, period} =
      cond do
        hour == 0 -> {12, "AM"}
        hour < 12 -> {hour, "AM"}
        hour == 12 -> {12, "PM"}
        true -> {hour - 12, "PM"}
      end

    "#{hour_12}:#{minute} #{period}"
  end

  defp format_date(date) do
    Calendar.strftime(date, "%A, %B %-d")
  end

  defp format_date_short(date) do
    Calendar.strftime(date, "%a %b %-d")
  end

  defp calculate_event_position(event, timezone) do
    # Convert UTC times to local timezone for display positioning
    local_start =
      case DateTime.shift_zone(event.start_time, timezone) do
        {:ok, local} -> local
        {:error, _} -> event.start_time
      end

    local_end =
      case DateTime.shift_zone(event.end_time, timezone) do
        {:ok, local} -> local
        {:error, _} -> event.end_time
      end

    start_hour = local_start.hour + local_start.minute / 60
    end_hour = local_end.hour + local_end.minute / 60

    # Calculate position as percentage of full 24-hour day
    day_start = 0
    day_end = 24
    day_duration = day_end - day_start

    top = (start_hour - day_start) / day_duration * 100
    height = (end_hour - start_hour) / day_duration * 100

    {top, height}
  end

  defp is_today?(date) do
    Date.compare(date, Date.utc_today()) == :eq
  end

  defp filter_contacts(contacts, search_term, selected_ids) do
    search_term = String.downcase(search_term)

    contacts
    |> Enum.filter(fn contact ->
      contact.id not in selected_ids and
        (String.contains?(String.downcase(contact.first_name), search_term) or
           String.contains?(String.downcase(contact.last_name), search_term) or
           String.contains?(String.downcase(contact.email), search_term))
    end)
    |> Enum.take(5)
  end

  defp list_all_contacts do
    # Get all contacts for the dropdown - use a high limit
    result = Scheduling.list_contacts(per_page: 1000)
    result.contacts
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
        <div class="px-4 sm:px-6 lg:px-8 py-8">
          <div class="bg-white dark:bg-gray-800 rounded-lg shadow">
            <%!-- Header --%>
            <div class="px-6 py-4 border-b border-gray-200 dark:border-gray-700">
              <div class="flex items-center justify-between">
                <h1 class="text-2xl font-semibold text-gray-900 dark:text-white">Schedule</h1>
                <div class="flex items-center space-x-2">
                  <button
                    phx-click="today"
                    class="px-3 py-1 text-sm font-medium text-gray-700 dark:text-gray-200 bg-white dark:bg-gray-700 border border-gray-300 dark:border-gray-600 rounded-md hover:bg-gray-50 dark:hover:bg-gray-600"
                  >
                    Today
                  </button>
                  <button
                    phx-click="open_create_modal"
                    class="px-3 py-1 text-sm font-medium text-white bg-blue-600 dark:bg-blue-500 rounded-md hover:bg-blue-700 dark:hover:bg-blue-600"
                  >
                    Create event
                  </button>

                  <%!-- Mobile: Day navigation buttons --%>
                  <button
                    phx-click="prev_day"
                    class="lg:hidden p-2 text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white hover:bg-gray-100 dark:hover:bg-gray-700 rounded-md"
                  >
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M15 19l-7-7 7-7"
                      />
                    </svg>
                  </button>
                  <button
                    phx-click="next_day"
                    class="lg:hidden p-2 text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white hover:bg-gray-100 dark:hover:bg-gray-700 rounded-md"
                  >
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M9 5l7 7-7 7"
                      />
                    </svg>
                  </button>

                  <%!-- Desktop: Week navigation buttons --%>
                  <button
                    phx-click="prev_week"
                    class="hidden lg:block p-2 text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white hover:bg-gray-100 dark:hover:bg-gray-700 rounded-md"
                  >
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M15 19l-7-7 7-7"
                      />
                    </svg>
                  </button>
                  <button
                    phx-click="next_week"
                    class="hidden lg:block p-2 text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white hover:bg-gray-100 dark:hover:bg-gray-700 rounded-md"
                  >
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M9 5l7 7-7 7"
                      />
                    </svg>
                  </button>
                </div>
              </div>
            </div>

            <%!-- Mobile Day View --%>
            <div class="block lg:hidden">
              <div class="px-6 py-4">
                <h2 class="text-lg font-medium text-gray-900 dark:text-white mb-4">
                  {format_date(@current_date)}
                </h2>
                <div class="space-y-2">
                  <%= for event <- Map.get(@events_by_date, @current_date, []) do %>
                    <.link
                      patch={~p"/events/#{event.id}"}
                      class="block bg-blue-50 dark:bg-blue-900/20 border-l-4 border-blue-500 dark:border-blue-400 p-3 rounded hover:bg-blue-100 dark:hover:bg-blue-900/30 cursor-pointer transition-colors"
                    >
                      <div class="flex items-start justify-between">
                        <div>
                          <p class="font-medium text-gray-900 dark:text-white">{event.name}</p>
                          <%= if event.description do %>
                            <p class="text-sm text-gray-600 dark:text-gray-400 mt-1">
                              {event.description}
                            </p>
                          <% end %>
                        </div>
                        <div class="text-sm text-gray-500 dark:text-gray-400 whitespace-nowrap ml-4">
                          {format_time(event.start_time, @timezone)} - {format_time(
                            event.end_time,
                            @timezone
                          )}
                        </div>
                      </div>
                      <%= if length(event.contacts) > 0 do %>
                        <div class="mt-2 text-sm text-gray-600 dark:text-gray-400">
                          <span class="font-medium">Contacts:</span>
                          <%= for contact <- event.contacts do %>
                            <span class="inline-block mr-2">
                              {contact.first_name} {contact.last_name}
                            </span>
                          <% end %>
                        </div>
                      <% end %>
                    </.link>
                  <% end %>
                  <%= if Map.get(@events_by_date, @current_date, []) == [] do %>
                    <p class="text-gray-500 dark:text-gray-400 italic">No events scheduled</p>
                  <% end %>
                </div>
              </div>
            </div>

            <%!-- Desktop Week View --%>
            <div class="hidden lg:block">
              <div class="overflow-x-auto">
                <div class="min-w-full">
                  <%!-- Day headers --%>
                  <div class="grid grid-cols-7 border-b border-gray-200 dark:border-gray-700 ml-16">
                    <%= for date <- get_week_dates(@current_date) do %>
                      <div class={[
                        "px-4 py-3 text-center border-r border-gray-200 dark:border-gray-700 last:border-r-0",
                        is_today?(date) && "bg-blue-50 dark:bg-blue-900/20"
                      ]}>
                        <div class="text-sm font-medium text-gray-900 dark:text-white">
                          {format_date_short(date)}
                        </div>
                        <%= if is_today?(date) do %>
                          <div class="text-xs text-blue-600 dark:text-blue-400 font-medium mt-1">
                            Today
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>

                  <%!-- Time grid and events --%>
                  <div class="relative">
                    <%!-- Hour lines --%>
                    <%= for hour <- 0..23 do %>
                      <div class="relative border-b border-gray-100 dark:border-gray-700 h-12">
                        <span class="absolute left-2 -top-2 text-xs text-gray-400 dark:text-gray-500 w-12">
                          {format_hour(hour)}
                        </span>
                        <div class="grid grid-cols-7 ml-16 h-full">
                          <%= for _ <- 1..7 do %>
                            <div class="border-r border-gray-100 dark:border-gray-700 last:border-r-0">
                            </div>
                          <% end %>
                        </div>
                      </div>
                    <% end %>

                    <%!-- Events overlay --%>
                    <div class="absolute inset-0 left-16 grid grid-cols-7">
                      <%= for {date, index} <- Enum.with_index(get_week_dates(@current_date)) do %>
                        <div class="relative border-r border-gray-200 dark:border-gray-700 last:border-r-0">
                          <%= for event <- Map.get(@events_by_date, date, []) do %>
                            <% {top, height} = calculate_event_position(event, @timezone) %>
                            <.link
                              patch={~p"/events/#{event.id}"}
                              class="absolute left-1 right-1 bg-blue-100 dark:bg-blue-900/30 border border-blue-300 dark:border-blue-600 rounded p-1 overflow-hidden hover:bg-blue-200 dark:hover:bg-blue-900/40 cursor-pointer transition-colors block"
                              style={"top: #{top}%; height: #{height}%; min-height: 30px;"}
                            >
                              <div class="text-xs font-medium text-blue-900 dark:text-blue-100 truncate">
                                {event.name}
                              </div>
                              <div class="text-xs text-blue-700 dark:text-blue-300">
                                {format_time(event.start_time, @timezone)}
                              </div>
                            </.link>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Event Detail Modal --%>
      <%= if @selected_event do %>
        <%!-- Mobile: Full screen modal --%>
        <div class="lg:hidden fixed inset-0 z-50 bg-white dark:bg-gray-900">
          <div class="flex flex-col h-full">
            <div class="flex items-center justify-between p-4 border-b border-gray-200 dark:border-gray-700">
              <.link
                patch={~p"/"}
                class="p-2 -ml-2 text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white"
              >
                <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M10 19l-7-7m0 0l7-7m-7 7h18"
                  />
                </svg>
              </.link>
              <h2 class="text-lg font-semibold text-gray-900 dark:text-white">Event Details</h2>
              <div class="w-10"></div>
            </div>
            <div class="flex-1 overflow-y-auto p-6">
              {render_event_details(assigns)}
            </div>
          </div>
        </div>

        <%!-- Desktop: Modal overlay --%>
        <div class="hidden lg:block fixed inset-0 z-50 overflow-y-auto">
          <div class="flex items-center justify-center min-h-screen p-4">
            <div
              class="fixed inset-0 bg-black/20 dark:bg-black/40 backdrop-blur-sm"
              phx-click="close_modal"
            >
            </div>
            <div class="relative bg-white dark:bg-gray-800 rounded-lg max-w-2xl w-full max-h-[90vh] overflow-hidden shadow-xl">
              <div class="absolute top-4 right-4">
                <.link
                  patch={~p"/"}
                  class="text-gray-400 dark:text-gray-500 hover:text-gray-500 dark:hover:text-gray-400"
                >
                  <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M6 18L18 6M6 6l12 12"
                    />
                  </svg>
                </.link>
              </div>
              <div class="p-6 overflow-y-auto max-h-[90vh]">
                {render_event_details(assigns)}
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Create Event Modal --%>
      <%= if @show_create_modal do %>
        <div
          class="fixed inset-0 z-50 overflow-y-auto"
          aria-labelledby="modal-title"
          role="dialog"
          aria-modal="true"
        >
          <div class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
            <div
              class="fixed inset-0 bg-black/20 dark:bg-black/40 backdrop-blur-sm"
              phx-click="close_create_modal"
              aria-hidden="true"
            >
            </div>

            <span class="hidden sm:inline-block sm:align-middle sm:h-screen" aria-hidden="true">
              &#8203;
            </span>

            <div class="relative inline-block align-bottom bg-white dark:bg-gray-800 rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-2xl sm:w-full">
              <div class="bg-white dark:bg-gray-800 px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
                <div class="sm:flex sm:items-start">
                  <div class="w-full">
                    <h3
                      class="text-lg leading-6 font-medium text-gray-900 dark:text-white mb-4"
                      id="modal-title"
                    >
                      Create Event
                    </h3>

                    <.form
                      for={@form}
                      id="event-form"
                      phx-submit="save_event"
                    >
                      <div class="space-y-4">
                        <div>
                          <.input field={@form[:name]} type="text" label="Event Name" required />
                        </div>

                        <div>
                          <.input
                            field={@form[:description]}
                            type="textarea"
                            label="Description"
                            rows="3"
                          />
                        </div>

                        <div class="grid grid-cols-2 gap-4">
                          <div>
                            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                              Start Date
                            </label>
                            <input
                              type="date"
                              name="event[start_date]"
                              value={Date.to_iso8601(@current_date)}
                              required
                              class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-700 dark:text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                            />
                          </div>
                          <div>
                            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                              Start Time
                            </label>
                            <input
                              type="time"
                              name="event[start_time]"
                              required
                              class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-700 dark:text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                            />
                          </div>
                        </div>

                        <div class="grid grid-cols-2 gap-4">
                          <div>
                            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                              End Date
                            </label>
                            <input
                              type="date"
                              name="event[end_date]"
                              value={Date.to_iso8601(@current_date)}
                              required
                              class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-700 dark:text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                            />
                          </div>
                          <div>
                            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                              End Time
                            </label>
                            <input
                              type="time"
                              name="event[end_time]"
                              required
                              class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-700 dark:text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                            />
                          </div>
                        </div>

                        <div>
                          <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                            Add Contacts
                          </label>
                          <div class="relative">
                            <input
                              type="text"
                              value={@contact_search}
                              phx-keyup="search_contacts"
                              phx-debounce="300"
                              placeholder="Search contacts..."
                              class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-700 dark:text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                            />
                            <%= if @contact_search != "" do %>
                              <div class="absolute z-10 mt-1 w-full bg-white dark:bg-gray-700 shadow-lg max-h-60 rounded-md py-1 text-base ring-1 ring-black ring-opacity-5 overflow-auto focus:outline-none sm:text-sm">
                                <%= for contact <- filter_contacts(@all_contacts, @contact_search, @selected_contact_ids) do %>
                                  <button
                                    type="button"
                                    phx-click="add_contact"
                                    phx-value-contact_id={contact.id}
                                    class="w-full text-left cursor-pointer select-none relative py-2 pl-3 pr-9 hover:bg-gray-100 dark:hover:bg-gray-600"
                                  >
                                    <span class="block truncate text-gray-900 dark:text-white">
                                      {contact.first_name} {contact.last_name} - {contact.email}
                                    </span>
                                  </button>
                                <% end %>
                              </div>
                            <% end %>
                          </div>

                          <%= if length(@selected_contact_ids) > 0 do %>
                            <div class="mt-2 space-y-2">
                              <%= for contact_id <- @selected_contact_ids do %>
                                <% contact = Enum.find(@all_contacts, &(&1.id == contact_id)) %>
                                <div class="flex items-center justify-between bg-gray-100 dark:bg-gray-700 rounded-md px-3 py-2">
                                  <span class="text-sm text-gray-900 dark:text-white">
                                    {contact.first_name} {contact.last_name}
                                  </span>
                                  <button
                                    type="button"
                                    phx-click="remove_contact"
                                    phx-value-contact_id={contact_id}
                                    class="text-red-600 dark:text-red-400 hover:text-red-800 dark:hover:text-red-300"
                                  >
                                    <svg
                                      class="h-4 w-4"
                                      fill="none"
                                      stroke="currentColor"
                                      viewBox="0 0 24 24"
                                    >
                                      <path
                                        stroke-linecap="round"
                                        stroke-linejoin="round"
                                        stroke-width="2"
                                        d="M6 18L18 6M6 6l12 12"
                                      />
                                    </svg>
                                  </button>
                                </div>
                              <% end %>
                            </div>
                          <% end %>
                        </div>
                      </div>

                      <div class="mt-5 sm:mt-6 sm:flex sm:flex-row-reverse">
                        <button
                          type="submit"
                          class="w-full inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-blue-600 text-base font-medium text-white hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 sm:ml-3 sm:w-auto sm:text-sm"
                        >
                          Create
                        </button>
                        <button
                          type="button"
                          phx-click="close_create_modal"
                          class="mt-3 w-full inline-flex justify-center rounded-md border border-gray-300 dark:border-gray-600 shadow-sm px-4 py-2 bg-white dark:bg-gray-700 text-base font-medium text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 sm:mt-0 sm:w-auto sm:text-sm"
                        >
                          Cancel
                        </button>
                      </div>
                    </.form>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  defp render_event_details(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white">{@selected_event.name}</h1>
        <%= if @selected_event.description do %>
          <p class="mt-2 text-gray-600 dark:text-gray-400">{@selected_event.description}</p>
        <% end %>
      </div>

      <div class="space-y-3">
        <div class="flex items-start">
          <svg
            class="w-5 h-5 text-gray-400 dark:text-gray-500 mt-0.5 mr-3"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
            />
          </svg>
          <div>
            <p class="text-sm font-medium text-gray-900 dark:text-white">Date & Time</p>
            <p class="text-sm text-gray-600 dark:text-gray-400">
              {format_date(@selected_event.start_time |> DateTime.to_date())}
            </p>
            <p class="text-sm text-gray-600 dark:text-gray-400">
              {format_time(@selected_event.start_time, @timezone)} - {format_time(
                @selected_event.end_time,
                @timezone
              )}
            </p>
          </div>
        </div>

        <%= if length(@selected_event.contacts) > 0 do %>
          <div class="flex items-start">
            <svg
              class="w-5 h-5 text-gray-400 dark:text-gray-500 mt-0.5 mr-3"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"
              />
            </svg>
            <div>
              <p class="text-sm font-medium text-gray-900 dark:text-white">Attendees</p>
              <div class="mt-1 space-y-1">
                <%= for contact <- @selected_event.contacts do %>
                  <div class="text-sm text-gray-600 dark:text-gray-400">
                    <span class="font-medium">{contact.first_name} {contact.last_name}</span>
                    <div class="text-xs text-gray-500 dark:text-gray-500">
                      {contact.email} • {format_phone(contact.phone_number)}
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_hour(hour) do
    cond do
      hour == 0 -> "12 AM"
      hour < 12 -> "#{hour} AM"
      hour == 12 -> "12 PM"
      true -> "#{hour - 12} PM"
    end
  end
end
