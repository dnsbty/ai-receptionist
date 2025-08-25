defmodule ReceptionistWeb.SurgeHandler do
  @moduledoc """
  Responsible for handling incoming webhook events from Surge.

  See `Surge.WebhookPlug` for more information.
  """

  alias Receptionist.Agent
  alias Receptionist.Scheduling

  @behaviour Surge.WebhookHandler

  @impl true
  def handle_event(%Surge.Events.Event{type: :message_received} = event) do
    phone_number = event.data.conversation.contact.phone_number
    message = event.data.body

    {:ok, contact} = Scheduling.get_or_create_contact_by_phone_number(phone_number)

    case Agent.handle_message(contact, message) do
      {:ok, response} when is_binary(response) ->
        surge_api_key = Application.fetch_env!(:receptionist, :surge_api_key)
        surge_base_url = Application.fetch_env!(:receptionist, :surge_base_url)
        client = Surge.Client.new(surge_api_key, base_url: surge_base_url)

        Surge.Messages.create(client, event.account_id, %{
          to: phone_number,
          body: response
        })

      {:ok, nil} ->
        :ok

      {:error, error} ->
        IO.inspect(error, label: "Error handling message")
        {:error, error}
    end
  end

  # Return HTTP 200 for unhandled events
  @impl true
  def handle_event(_event), do: :ok
end
