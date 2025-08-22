defmodule ReceptionistWeb.ContactsLive do
  use ReceptionistWeb, :live_view

  alias Receptionist.Scheduling
  alias Receptionist.Scheduling.Contact
  import ReceptionistWeb.PhoneHelper

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    case socket.assigns.live_action do
      :index ->
        page = String.to_integer(params["page"] || "1")
        search = params["search"] || ""

        result = Scheduling.list_contacts(search: search, page: page, per_page: 25)

        {:noreply,
         socket
         |> assign(:page_title, "Contacts")
         |> assign(:search, search)
         |> assign(:contacts, result.contacts)
         |> assign(:page, result.page)
         |> assign(:total_pages, result.total_pages)
         |> assign(:total_count, result.total_count)}

      :new ->
        changeset = Scheduling.change_contact(%Contact{})

        {:noreply,
         socket
         |> assign(:page_title, "New Contact")
         |> assign(:form, to_form(changeset))}

      :show ->
        contact = Scheduling.get_contact_with_events!(params["id"])

        {:noreply,
         socket
         |> assign(:page_title, "#{contact.first_name} #{contact.last_name}")
         |> assign(:contact, contact)}

      :edit ->
        contact = Scheduling.get_contact!(params["id"])
        # Format the phone number for display in the form
        formatted_contact = Map.put(contact, :phone_number, format_phone(contact.phone_number))
        changeset = Scheduling.change_contact(formatted_contact)

        {:noreply,
         socket
         |> assign(:page_title, "Edit Contact")
         |> assign(:contact, contact)
         |> assign(:form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, push_patch(socket, to: ~p"/contacts?#{[search: search]}")}
  end

  @impl true
  def handle_event("save", %{"contact" => contact_params}, socket) do
    save_contact(socket, socket.assigns.live_action, contact_params)
  end

  defp save_contact(socket, :edit, contact_params) do
    case Scheduling.update_contact(socket.assigns.contact, contact_params) do
      {:ok, contact} ->
        {:noreply,
         socket
         |> put_flash(:info, "Contact updated successfully")
         |> push_navigate(to: ~p"/contacts/#{contact}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_contact(socket, :new, contact_params) do
    case Scheduling.create_contact(contact_params) do
      {:ok, contact} ->
        {:noreply,
         socket
         |> put_flash(:info, "Contact created successfully")
         |> push_navigate(to: ~p"/contacts/#{contact}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(%{live_action: :index} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <div class="mb-8 flex items-center justify-between">
            <h1 class="text-3xl font-bold text-gray-900 dark:text-white">Contacts</h1>
            <.link
              navigate={~p"/contacts/new"}
              class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 dark:bg-blue-500 dark:hover:bg-blue-600 font-medium"
            >
              Create contact
            </.link>
          </div>

          <div class="mb-6">
            <form phx-change="search" phx-submit="search">
              <div class="relative">
                <input
                  type="text"
                  name="search"
                  value={@search}
                  placeholder="Search by name, email, or phone..."
                  class="w-full px-4 py-2 pl-10 pr-4 border border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent bg-white dark:bg-gray-800 text-gray-900 dark:text-white"
                />
                <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                  <.icon name="hero-magnifying-glass" class="h-5 w-5 text-gray-400" />
                </div>
              </div>
            </form>
          </div>

          <div class="bg-white dark:bg-gray-800 shadow overflow-hidden sm:rounded-md">
            <ul class="divide-y divide-gray-200 dark:divide-gray-700">
              <%= for contact <- @contacts do %>
                <li>
                  <.link
                    navigate={~p"/contacts/#{contact}"}
                    class="block hover:bg-gray-50 dark:hover:bg-gray-700 px-4 py-4 sm:px-6"
                  >
                    <div class="flex items-center justify-between">
                      <div class="flex items-center">
                        <div class="flex-shrink-0">
                          <div class="h-10 w-10 rounded-full bg-blue-500 flex items-center justify-center">
                            <span class="text-white font-medium">
                              {String.first(contact.first_name)}{String.first(contact.last_name)}
                            </span>
                          </div>
                        </div>
                        <div class="ml-4">
                          <div class="text-sm font-medium text-gray-900 dark:text-white">
                            {contact.first_name} {contact.last_name}
                          </div>
                          <div class="text-sm text-gray-500 dark:text-gray-400">
                            {contact.email}
                          </div>
                        </div>
                      </div>
                      <div class="text-sm text-gray-500 dark:text-gray-400">
                        {format_phone(contact.phone_number)}
                      </div>
                    </div>
                  </.link>
                </li>
              <% end %>
            </ul>
          </div>

          <%= if @total_pages > 1 do %>
            <div class="mt-6 flex items-center justify-between">
              <div class="text-sm text-gray-700 dark:text-gray-300">
                Showing {(@page - 1) * 25 + 1} to {min(@page * 25, @total_count)} of {@total_count} contacts
              </div>
              <div class="flex gap-2">
                <%= if @page > 1 do %>
                  <.link
                    patch={~p"/contacts?#{[page: @page - 1, search: @search]}"}
                    class="px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md text-sm font-medium text-gray-700 dark:text-gray-300 bg-white dark:bg-gray-800 hover:bg-gray-50 dark:hover:bg-gray-700"
                  >
                    Previous
                  </.link>
                <% end %>
                <%= if @page < @total_pages do %>
                  <.link
                    patch={~p"/contacts?#{[page: @page + 1, search: @search]}"}
                    class="px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md text-sm font-medium text-gray-700 dark:text-gray-300 bg-white dark:bg-gray-800 hover:bg-gray-50 dark:hover:bg-gray-700"
                  >
                    Next
                  </.link>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <div class="mb-6 flex items-center justify-between">
            <.link
              navigate={~p"/contacts"}
              class="text-blue-600 dark:text-blue-400 hover:text-blue-800 dark:hover:text-blue-300 flex items-center gap-2"
            >
              <.icon name="hero-arrow-left" class="h-5 w-5" /> Back to Contacts
            </.link>
            <.link
              patch={~p"/contacts/#{@contact}/edit"}
              class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 dark:bg-blue-500 dark:hover:bg-blue-600"
            >
              Edit
            </.link>
          </div>

          <div class="bg-white dark:bg-gray-800 shadow overflow-hidden sm:rounded-lg">
            <div class="px-4 py-5 sm:px-6">
              <h3 class="text-lg leading-6 font-medium text-gray-900 dark:text-white">
                {@contact.first_name} {@contact.last_name}
              </h3>
            </div>
            <div class="border-t border-gray-200 dark:border-gray-700">
              <dl>
                <div class="bg-gray-50 dark:bg-gray-900 px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
                  <dt class="text-sm font-medium text-gray-500 dark:text-gray-400">Email</dt>
                  <dd class="mt-1 text-sm text-gray-900 dark:text-white sm:mt-0 sm:col-span-2">
                    {@contact.email}
                  </dd>
                </div>
                <div class="bg-white dark:bg-gray-800 px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
                  <dt class="text-sm font-medium text-gray-500 dark:text-gray-400">Phone</dt>
                  <dd class="mt-1 text-sm text-gray-900 dark:text-white sm:mt-0 sm:col-span-2">
                    {format_phone(@contact.phone_number)}
                  </dd>
                </div>
              </dl>
            </div>
          </div>

          <%= if length(@contact.events) > 0 do %>
            <div class="mt-8">
              <h3 class="text-lg font-medium text-gray-900 dark:text-white mb-4">Events</h3>
              <div class="bg-white dark:bg-gray-800 shadow overflow-hidden sm:rounded-md">
                <ul class="divide-y divide-gray-200 dark:divide-gray-700">
                  <%= for event <- @contact.events do %>
                    <li>
                      <.link
                        navigate={~p"/events/#{event}"}
                        class="block hover:bg-gray-50 dark:hover:bg-gray-700 px-4 py-4 sm:px-6"
                      >
                        <div class="flex items-center justify-between">
                          <div>
                            <p class="text-sm font-medium text-gray-900 dark:text-white">
                              {event.name}
                            </p>
                            <p class="text-sm text-gray-500 dark:text-gray-400">
                              {format_datetime(event.start_time)} - {format_time(event.end_time)}
                            </p>
                          </div>
                        </div>
                      </.link>
                    </li>
                  <% end %>
                </ul>
              </div>
            </div>
          <% else %>
            <div class="mt-8 text-center py-12">
              <p class="text-gray-500 dark:text-gray-400">No events scheduled with this contact.</p>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def render(%{live_action: :new} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
        <div class="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <div class="mb-6">
            <.link
              navigate={~p"/contacts"}
              class="text-blue-600 dark:text-blue-400 hover:text-blue-800 dark:hover:text-blue-300 flex items-center gap-2"
            >
              <.icon name="hero-arrow-left" class="h-5 w-5" /> Back to Contacts
            </.link>
          </div>

          <div class="bg-white dark:bg-gray-800 shadow sm:rounded-lg">
            <div class="px-4 py-5 sm:p-6">
              <h3 class="text-lg leading-6 font-medium text-gray-900 dark:text-white mb-4">
                New Contact
              </h3>

              <.form for={@form} id="contact-form" phx-submit="save">
                <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
                  <div>
                    <.input field={@form[:first_name]} type="text" label="First Name" />
                  </div>
                  <div>
                    <.input field={@form[:last_name]} type="text" label="Last Name" />
                  </div>
                  <div class="sm:col-span-2">
                    <.input field={@form[:email]} type="email" label="Email" />
                  </div>
                  <div class="sm:col-span-2">
                    <.input field={@form[:phone_number]} type="tel" label="Phone Number" />
                  </div>
                </div>

                <div class="mt-6 flex gap-3">
                  <button
                    type="submit"
                    class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 dark:bg-blue-500 dark:hover:bg-blue-600 text-sm font-medium"
                  >
                    Create Contact
                  </button>
                  <.link
                    navigate={~p"/contacts"}
                    class="px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-md text-sm font-medium text-gray-700 dark:text-gray-300 bg-white dark:bg-gray-800 hover:bg-gray-50 dark:hover:bg-gray-700"
                  >
                    Cancel
                  </.link>
                </div>
              </.form>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def render(%{live_action: :edit} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
        <div class="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <div class="mb-6">
            <.link
              navigate={~p"/contacts/#{@contact}"}
              class="text-blue-600 dark:text-blue-400 hover:text-blue-800 dark:hover:text-blue-300 flex items-center gap-2"
            >
              <.icon name="hero-arrow-left" class="h-5 w-5" /> Back to Contact
            </.link>
          </div>

          <div class="bg-white dark:bg-gray-800 shadow sm:rounded-lg">
            <div class="px-4 py-5 sm:p-6">
              <h3 class="text-lg leading-6 font-medium text-gray-900 dark:text-white mb-4">
                Edit Contact
              </h3>

              <.form for={@form} id="contact-form" phx-submit="save">
                <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
                  <div>
                    <.input field={@form[:first_name]} type="text" label="First Name" />
                  </div>
                  <div>
                    <.input field={@form[:last_name]} type="text" label="Last Name" />
                  </div>
                  <div class="sm:col-span-2">
                    <.input field={@form[:email]} type="email" label="Email" />
                  </div>
                  <div class="sm:col-span-2">
                    <.input field={@form[:phone_number]} type="text" label="Phone Number" />
                  </div>
                </div>

                <div class="mt-6 flex gap-3">
                  <button
                    type="submit"
                    class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 dark:bg-blue-500 dark:hover:bg-blue-600 text-sm font-medium"
                  >
                    Save
                  </button>
                  <.link
                    navigate={~p"/contacts/#{@contact}"}
                    class="px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-md text-sm font-medium text-gray-700 dark:text-gray-300 bg-white dark:bg-gray-800 hover:bg-gray-50 dark:hover:bg-gray-700"
                  >
                    Cancel
                  </.link>
                </div>
              </.form>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_datetime(datetime) do
    {:ok, local_dt} = DateTime.shift_zone(datetime, "Etc/UTC")
    Calendar.strftime(local_dt, "%b %d, %Y at %I:%M %p")
  end

  defp format_time(datetime) do
    {:ok, local_dt} = DateTime.shift_zone(datetime, "Etc/UTC")
    Calendar.strftime(local_dt, "%I:%M %p")
  end
end
