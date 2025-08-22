defmodule ReceptionistWeb.CalendarLive do
  use ReceptionistWeb, :live_view
  alias Receptionist.Scheduling

  @impl true
  def mount(_params, _session, socket) do
    timezone = get_connect_params(socket)["timezone"] || "UTC"
    today = today_in_timezone(timezone)

    socket =
      socket
      |> assign(:timezone, timezone)
      |> assign(:current_date, today)
      |> assign(:selected_event, nil)
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

  defp date_to_datetime(date, _timezone, :start) do
    {:ok, datetime} = DateTime.new(date, ~T[00:00:00])
    datetime
  end

  defp date_to_datetime(date, _timezone, :end) do
    {:ok, datetime} = DateTime.new(date, ~T[23:59:59])
    datetime
  end

  defp format_time(datetime, _timezone) do
    # For now, just format as UTC
    # In production, you'd want proper timezone conversion
    hour = datetime.hour
    minute = datetime.minute |> Integer.to_string() |> String.pad_leading(2, "0")

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

  defp calculate_event_position(event, _timezone) do
    # Using UTC times for now
    start_time = event.start_time
    end_time = event.end_time

    start_hour = start_time.hour + start_time.minute / 60
    end_hour = end_time.hour + end_time.minute / 60

    # Calculate position as percentage of day (6am to 10pm = 16 hours)
    # 6am
    day_start = 6
    # 10pm
    day_end = 22
    day_duration = day_end - day_start

    top = max((start_hour - day_start) / day_duration * 100, 0)
    height = (end_hour - start_hour) / day_duration * 100

    {top, height}
  end

  defp is_today?(date) do
    Date.compare(date, Date.utc_today()) == :eq
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
                    <%= for hour <- 6..21 do %>
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
                      {contact.email} • {contact.phone_number}
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
