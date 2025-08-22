defmodule ReceptionistWeb.CalendarLiveTest do
  use ReceptionistWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Receptionist.Scheduling

  setup do
    # Create test contacts
    {:ok, contact1} = Scheduling.create_contact(%{
      first_name: "Test",
      last_name: "User",
      email: "test@example.com",
      phone_number: "415-555-0001"
    })
    
    {:ok, contact2} = Scheduling.create_contact(%{
      first_name: "Another",
      last_name: "Person",
      email: "another@example.com", 
      phone_number: "415-555-0002"
    })
    
    %{contact1: contact1, contact2: contact2}
  end

  describe "calendar view" do
    test "renders calendar with header", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")
      
      assert html =~ "Schedule"
      assert html =~ "Today"
      assert html =~ "Create event"
    end
    
    test "shows current week on desktop", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      
      # Should show day headers for the week
      today = Date.utc_today()
      
      for i <- 0..6 do
        date = Date.add(today, i)
        day_name = Calendar.strftime(date, "%a")
        assert render(view) =~ day_name
      end
    end
  end

  describe "event creation" do
    test "opens create event modal when button is clicked", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      
      refute render(view) =~ "Create Event"
      
      view
      |> element("button", "Create event")
      |> render_click()
      
      assert render(view) =~ "Create Event"
      assert render(view) =~ "Event Name"
      assert render(view) =~ "Description"
      assert render(view) =~ "Start Date"
      assert render(view) =~ "End Date"
    end
    
    test "closes modal when cancel is clicked", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      
      view
      |> element("button", "Create event")
      |> render_click()
      
      assert render(view) =~ "Create Event"
      
      view
      |> element("button", "Cancel")
      |> render_click()
      
      refute render(view) =~ "Create Event"
    end
    
    test "creates event with valid data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      
      view
      |> element("button", "Create event")
      |> render_click()
      
      today = Date.utc_today()
      
      view
      |> form("#event-form", %{
        event: %{
          name: "Test Event",
          description: "Test Description",
          start_date: Date.to_iso8601(today),
          start_time: "10:00",
          end_date: Date.to_iso8601(today),
          end_time: "11:00"
        }
      })
      |> render_submit()
      
      assert render(view) =~ "Event created successfully"
      assert render(view) =~ "Test Event"
    end
    
    test "shows validation errors for invalid data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      
      view
      |> element("button", "Create event")
      |> render_click()
      
      view
      |> form("#event-form", %{
        event: %{
          name: "",
          description: "Test Description"
        }
      })
      |> render_change()
      
      assert render(view) =~ "can&#39;t be blank"
    end
  end

  describe "contact selection" do
    test "searches and adds contacts to event", %{conn: conn, contact1: contact1} do
      {:ok, view, _html} = live(conn, ~p"/")
      
      view
      |> element("button", "Create event")
      |> render_click()
      
      # Search for contact - trigger the event directly
      view
      |> render_hook("search_contacts", %{"value" => "Test"})
      
      html = render(view)
      assert html =~ "Test User"
      assert html =~ "test@example.com"
      
      # Add contact
      view
      |> element("button", "Test User - test@example.com")
      |> render_click()
      
      html = render(view)
      assert html =~ "Test User"
      # Should show remove button (X icon)
      assert html =~ "M6 18L18 6M6 6l12 12"
    end
    
    test "removes contact from selection", %{conn: conn, contact1: contact1} do
      {:ok, view, _html} = live(conn, ~p"/")
      
      view
      |> element("button", "Create event")
      |> render_click()
      
      # Add contact first
      view
      |> render_hook("search_contacts", %{"value" => "Test"})
      
      view
      |> element("button", "Test User - test@example.com")
      |> render_click()
      
      assert render(view) =~ "Test User"
      
      # Remove contact
      view
      |> element("button[phx-click='remove_contact'][phx-value-contact_id='#{contact1.id}']")
      |> render_click()
      
      # Contact should be removed from selected list
      html = render(view)
      refute html =~ "<span class=\"text-sm text-gray-900 dark:text-white\">\n                                    Test User"
    end
    
    test "creates event with contacts", %{conn: conn, contact1: contact1, contact2: contact2} do
      {:ok, view, _html} = live(conn, ~p"/")
      
      view
      |> element("button", "Create event")
      |> render_click()
      
      # Add first contact
      view
      |> render_hook("search_contacts", %{"value" => "Test"})
      
      view
      |> element("button", "Test User - test@example.com")
      |> render_click()
      
      # Add second contact
      view
      |> render_hook("search_contacts", %{"value" => "Another"})
      
      view
      |> element("button", "Another Person - another@example.com")
      |> render_click()
      
      today = Date.utc_today()
      
      # Create event
      view
      |> form("#event-form", %{
        event: %{
          name: "Meeting",
          description: "Team meeting",
          start_date: Date.to_iso8601(today),
          start_time: "14:00",
          end_date: Date.to_iso8601(today),
          end_time: "15:00"
        }
      })
      |> render_submit()
      
      assert render(view) =~ "Event created successfully"
      
      # Verify event was created with contacts
      events = Scheduling.list_events_in_range(
        DateTime.utc_now() |> DateTime.add(-1, :day),
        DateTime.utc_now() |> DateTime.add(1, :day)
      )
      
      event = Enum.find(events, &(&1.name == "Meeting"))
      assert event != nil
      assert length(event.contacts) == 2
      contact_ids = Enum.map(event.contacts, & &1.id)
      assert contact1.id in contact_ids
      assert contact2.id in contact_ids
    end
  end

  describe "event display" do
    test "shows event on calendar after creation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      
      view
      |> element("button", "Create event")
      |> render_click()
      
      today = Date.utc_today()
      
      view
      |> form("#event-form", %{
        event: %{
          name: "Important Meeting",
          description: "Discuss project",
          start_date: Date.to_iso8601(today),
          start_time: "09:00",
          end_date: Date.to_iso8601(today),
          end_time: "10:00"
        }
      })
      |> render_submit()
      
      html = render(view)
      assert html =~ "Important Meeting"
    end
    
    test "clicking event shows details modal", %{conn: conn} do
      # Create an event first
      today = Date.utc_today()
      {:ok, datetime} = DateTime.new(today, ~T[14:00:00], "Etc/UTC")
      {:ok, end_datetime} = DateTime.new(today, ~T[15:00:00], "Etc/UTC")
      
      {:ok, event} = Scheduling.create_event(%{
        name: "Test Event",
        description: "Event description",
        start_time: datetime,
        end_time: end_datetime
      })
      
      {:ok, view, _html} = live(conn, ~p"/")
      
      view
      |> element("[phx-click='show_event'][phx-value-id='#{event.id}']")
      |> render_click()
      
      html = render(view)
      assert html =~ "Test Event"
      assert html =~ "Event description"
    end
  end
end