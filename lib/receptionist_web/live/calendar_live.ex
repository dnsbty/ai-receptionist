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
      |> load_events()

    {:ok, socket}
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


  defp load_events(socket) do
    # Load both day and week ranges to support responsive view
    day_dates = [socket.assigns.current_date]
    week_dates = Enum.map(0..6, fn days ->
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
      <div class="min-h-screen bg-gray-50">
        <div class="px-4 sm:px-6 lg:px-8 py-8">
          <div class="bg-white rounded-lg shadow">
            <%!-- Header --%>
            <div class="px-6 py-4 border-b border-gray-200">
              <div class="flex items-center justify-between">
                <h1 class="text-2xl font-semibold text-gray-900">Schedule</h1>
                <div class="flex items-center space-x-2">
                  <button
                    phx-click="today"
                    class="px-3 py-1 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
                  >
                    Today
                  </button>
                  
                  <%!-- Mobile: Day navigation buttons --%>
                  <button
                    phx-click="prev_day"
                    class="lg:hidden p-2 text-gray-600 hover:text-gray-900 hover:bg-gray-100 rounded-md"
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
                    class="lg:hidden p-2 text-gray-600 hover:text-gray-900 hover:bg-gray-100 rounded-md"
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
                    class="hidden lg:block p-2 text-gray-600 hover:text-gray-900 hover:bg-gray-100 rounded-md"
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
                    class="hidden lg:block p-2 text-gray-600 hover:text-gray-900 hover:bg-gray-100 rounded-md"
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
                <h2 class="text-lg font-medium text-gray-900 mb-4">
                  {format_date(@current_date)}
                </h2>
                <div class="space-y-2">
                  <%= for event <- Map.get(@events_by_date, @current_date, []) do %>
                    <div class="bg-blue-50 border-l-4 border-blue-500 p-3 rounded hover:bg-blue-100 cursor-pointer transition-colors">
                      <div class="flex items-start justify-between">
                        <div>
                          <p class="font-medium text-gray-900">{event.name}</p>
                          <%= if event.description do %>
                            <p class="text-sm text-gray-600 mt-1">{event.description}</p>
                          <% end %>
                        </div>
                        <div class="text-sm text-gray-500 whitespace-nowrap ml-4">
                          {format_time(event.start_time, @timezone)} - {format_time(
                            event.end_time,
                            @timezone
                          )}
                        </div>
                      </div>
                      <%= if length(event.contacts) > 0 do %>
                        <div class="mt-2 text-sm text-gray-600">
                          <span class="font-medium">Contacts:</span>
                          <%= for contact <- event.contacts do %>
                            <span class="inline-block mr-2">
                              {contact.first_name} {contact.last_name}
                            </span>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                  <%= if Map.get(@events_by_date, @current_date, []) == [] do %>
                    <p class="text-gray-500 italic">No events scheduled</p>
                  <% end %>
                </div>
              </div>
            </div>

            <%!-- Desktop Week View --%>
            <div class="hidden lg:block">
              <div class="overflow-x-auto">
                <div class="min-w-full">
                  <%!-- Day headers --%>
                  <div class="grid grid-cols-7 border-b border-gray-200 ml-16">
                    <%= for date <- get_week_dates(@current_date) do %>
                      <div class={[
                        "px-4 py-3 text-center border-r border-gray-200 last:border-r-0",
                        is_today?(date) && "bg-blue-50"
                      ]}>
                        <div class="text-sm font-medium text-gray-900">
                          {format_date_short(date)}
                        </div>
                        <%= if is_today?(date) do %>
                          <div class="text-xs text-blue-600 font-medium mt-1">Today</div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>

                  <%!-- Time grid and events --%>
                  <div class="relative">
                    <%!-- Hour lines --%>
                    <%= for hour <- 6..21 do %>
                      <div class="relative border-b border-gray-100 h-12">
                        <span class="absolute left-2 -top-2 text-xs text-gray-400 w-12">
                          {format_hour(hour)}
                        </span>
                        <div class="grid grid-cols-7 ml-16 h-full">
                          <%= for _ <- 1..7 do %>
                            <div class="border-r border-gray-100 last:border-r-0"></div>
                          <% end %>
                        </div>
                      </div>
                    <% end %>

                    <%!-- Events overlay --%>
                    <div class="absolute inset-0 left-16 grid grid-cols-7">
                      <%= for {date, index} <- Enum.with_index(get_week_dates(@current_date)) do %>
                        <div class="relative border-r border-gray-200 last:border-r-0">
                          <%= for event <- Map.get(@events_by_date, date, []) do %>
                            <% {top, height} = calculate_event_position(event, @timezone) %>
                            <div
                              class="absolute left-1 right-1 bg-blue-100 border border-blue-300 rounded p-1 overflow-hidden hover:bg-blue-200 cursor-pointer transition-colors"
                              style={"top: #{top}%; height: #{height}%; min-height: 30px;"}
                            >
                              <div class="text-xs font-medium text-blue-900 truncate">
                                {event.name}
                              </div>
                              <div class="text-xs text-blue-700">
                                {format_time(event.start_time, @timezone)}
                              </div>
                            </div>
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
    </Layouts.app>
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
