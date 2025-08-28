defmodule Receptionist.Agent do
  @moduledoc """
  AI agent that handles natural language scheduling for a dog grooming business.
  """

  alias Receptionist.Agent.OpenAi
  alias Receptionist.Scheduling
  alias Receptionist.Scheduling.Contact

  @model "gpt-5-nano"

  @system_prompt """
  You are Pam, a receptionist for Alpine Pup Parlour, a high end dog grooming
  business in Salt Lake City, Utah. Your primary role is to manage the dog
  groomer's schedule and help customers book appointments.

  Maintain a friendly and professional tone, but occasional jokes are ok.

  Please return one complete answer and then stop.

  Important guidelines:
  - Always stay in character as Pam from Alpine Pup Parlour
  - You are communicating via SMS text messages so try to limit responses to 160
    characters when possible with no special unicode characters like emdashes or
    ellipsis, but NEVER go over 450 characters for your response. Try to still
    use full words rather than abbreviations just for brevity's sake though.
  - If the contact sends a message that doesn't require a response, use the
    "ignore_message" tool to not respond to that message
  - Because you're using SMS, don't provide updates like "Proceeding to book the
    appointment now.". Just book the appointment and return the ONE message that
    should be sent to the contact.
  - Do not send any messages about waiting for tool calls or anything like that.
    Just respond naturally as if you are having a conversation.
  - Do not mention you are an AI model or language model
  - Only create events for contacts who have both a full name and email
  - If the contact already has a full name and email on file, you don't need to
    ask again or confirm
  - If you don't have a contact's full name or email, ask for it before creating
    any appointments, and use the "update_contact" tool to save it
  - If a contact wants to book an appointment, use the "find_available_slots" tool
    to get available times and ask which time they prefer. Try to offer 3
    options and ask which day/time works best.
  - Once the contact provides a time they would like to book, use the
    "create_event" tool to book it
  - Standard appointments are 30 minutes unless the customer specifically
    requests a 1-hour appointment. Don't mention the duration of the appointment
    unless they do.
  - Event names should be the contact's full name
  - Event descriptions should be "Dog grooming appointment with [contact name]"
  - Business hours are Monday-Friday 8am-6pm, Saturday 10am-4pm, closed Sunday
  - If someone asks something irrelevant to scheduling or dog grooming, politely
    steer the conversation back to scheduling
  - If you are asked to do something outside your capabilities, politely inform
    the contact you cannot do that
  - Feel free to use their first name in friendly conversation once you know it
  - Do not mention the tools you have available to the contact
  - Do not mention the contact's ID, email address, last name, or other internal
    details
  - Only confirm the appointment one time. After that, just end the conversation
    politely.

  Here is an example of how to respond when someone wants to book an appointment

  <example>
  Contact: "Hi, can I set up a grooming appointment for my dog?"
  Pam: "I'd be happy to help you book a grooming appointment! Could I please
    have your full name and email address to get started?"
  Contact: "Sure, it's Jane Doe jane.doe@gmail.com"
  Pam: "Thanks Jane! When would you like to schedule the appointment? We have
    openings tomorrow morning or Saturday afternoon."
  Contact: "How about Saturday at 2pm?"
  Pam: "Great! I have you down for a 30-minute grooming appointment on Saturday
    at 2pm. Does that work for you?"
  Contact: "Yes, that works."
  Pam: "Perfect! Your appointment is booked for Saturday at 2pm. We look forward
    to seeing you and your pup then! If you have any questions before your
    appointment, feel free to reach out."
  Contact: "Thanks! See you then"
  </example>
  """

  @tools [
    %{
      type: :function,
      name: "create_event",
      description:
        "Create a new appointment/event. Use this after confirming the time with the customer.",
      parameters: %{
        type: :object,
        properties: %{
          name: %{
            type: :string,
            description: "Name of the event (usually the contact's full name)"
          },
          description: %{
            type: :string,
            description: "Description of the event"
          },
          start_time: %{
            type: :string,
            description: "Start time in ISO 8601 format (e.g., 2024-03-15T14:00:00Z)"
          },
          end_time: %{
            type: :string,
            description: "End time in ISO 8601 format (e.g., 2024-03-15T14:30:00Z)"
          }
        },
        required: [:name, :start_time, :end_time]
      }
    },
    %{
      type: :function,
      name: "find_available_slots",
      description:
        "Find available appointment slots. Call this when someone wants to book an appointment.",
      parameters: %{
        type: :object,
        properties: %{
          start_time: %{
            type: :string,
            description:
              "Starting time to search from in ISO 8601 format (optional, defaults to now)"
          },
          duration: %{
            type: :integer,
            description: "Duration in minutes (30 or 60, defaults to 30)"
          }
        }
      }
    },
    %{
      type: :function,
      name: "ignore_message",
      description:
        "Don't respond to the message that was received. Use this if the input message doesn't require a response."
    },
    %{
      type: :function,
      name: "update_contact",
      description: "Update an existing contact's information",
      parameters: %{
        type: :object,
        properties: %{
          first_name: %{
            type: :string,
            description: "Updated first name"
          },
          last_name: %{
            type: :string,
            description: "Updated last name"
          },
          email: %{
            type: :string,
            description: "Updated email address"
          },
          phone_number: %{
            type: :string,
            description: "Updated phone number"
          }
        }
      }
    }
  ]

  @doc """
  Handles a message from a contact and returns an AI-generated response.
  """
  def handle_message(%Contact{agent_conversation_id: nil} = contact, message) do
    {:ok, contact} = create_conversation(contact)
    handle_message(contact, message)
  end

  def handle_message(%Contact{} = contact, message) when is_binary(message) do
    params = %{
      conversation: contact.agent_conversation_id,
      input: message,
      model: @model,
      parallel_tool_calls: false,
      reasoning: %{effort: :low},
      text: %{verbosity: :low},
      tools: @tools
    }

    case OpenAi.create_response(params) do
      {:ok, response} ->
        handle_response(response, contact)

      {:error, error} ->
        {:error, "Failed to get AI response: #{inspect(error)}"}
    end
  end

  # Private

  # Create a new OpenAI conversation and store the ID on the contact.
  @spec create_conversation(%Contact{}) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  defp create_conversation(%Contact{} = contact) do
    {:ok, conversation} =
      OpenAi.create_conversation(%{
        items: [
          %{role: "system", content: system_prompt_with_context(contact)}
        ]
      })

    Scheduling.update_contact(contact, %{
      agent_conversation_id: conversation["id"]
    })
  end

  # Add dynamic context to the system prompt
  @spec system_prompt_with_context(%Contact{}) :: String.t()
  defp system_prompt_with_context(contact) do
    """
    #{@system_prompt}

    Current date and time: #{DateTime.utc_now() |> DateTime.shift_zone!("America/Denver") |> DateTime.to_string()}

    Contact information:
    ID: #{contact.id}
    First name: #{contact.first_name || "Unknown"}
    Last name: #{contact.last_name || "Unknown"}
    Email: #{contact.email || "Not provided"}
    Phone: #{contact.phone_number || "Not provided"}
    """
  end

  @spec handle_response(map, %Contact{}) :: {:ok, String.t() | nil} | {:error, String.t()}
  defp handle_response(response, contact) do
    case response do
      %{"output" => output} ->
        message = Enum.find(output, fn item -> item["type"] in ["function_call", "message"] end)
        IO.inspect(message, label: "AI Response")
        handle_assistant_message(message, contact)

      _ ->
        {:error, "Unexpected response format"}
    end
  end

  @spec handle_assistant_message(map, %Contact{}) ::
          {:ok, String.t() | nil} | {:error, String.t()}
  defp handle_assistant_message(%{"type" => "function_call"} = message, contact) do
    message
    |> execute_tool_call(contact)
    |> IO.inspect(label: "Tool call result")
    |> handle_tool_result(message, contact)
  end

  defp handle_assistant_message(%{"content" => content}, _contact) do
    output = Enum.find(content, fn item -> item["type"] == "output_text" end)
    {:ok, output["text"]}
  end

  @spec handle_tool_result(map() | :ignore_message, map(), %Contact{}) ::
          {:ok, String.t() | nil} | {:error, String.t()}
  defp handle_tool_result(:ignore_message, _message, _contact) do
    {:ok, nil}
  end

  defp handle_tool_result(result, message, contact) do
    tool_input = %{
      type: :function_call_output,
      call_id: message["call_id"],
      output: Jason.encode!(result)
    }

    params = %{
      conversation: contact.agent_conversation_id,
      input: [tool_input],
      model: @model,
      parallel_tool_calls: false,
      reasoning: %{effort: :low},
      text: %{verbosity: :low}
    }

    case OpenAi.create_response(params) do
      {:ok, response} ->
        handle_response(response, contact)

      {:error, error} ->
        {:error, "Failed to get final response: #{inspect(error)}"}
    end
  end

  @spec execute_tool_call(map(), %Contact{}) :: map() | :ignore_message
  defp execute_tool_call(%{"name" => function_name, "arguments" => args_json}, contact) do
    args = Jason.decode!(args_json)

    case function_name do
      "create_event" ->
        create_event(contact, args)

      "find_available_slots" ->
        find_available_slots(args)

      "ignore_message" ->
        :ignore_message

      "update_contact" ->
        update_contact(contact, args)

      _ ->
        %{error: "Unknown function: #{function_name}"}
    end
  end

  @spec update_contact(%Contact{}, map()) :: map()
  defp update_contact(contact, args) do
    attrs = Map.take(args, ["first_name", "last_name", "email", "phone_number"])

    case Scheduling.update_contact(contact, attrs) do
      {:ok, _updated_contact} -> %{success: true, contact_id: contact.id}
      {:error, changeset} -> %{success: false, errors: format_changeset_errors(changeset)}
    end
  end

  @spec create_event(%Contact{}, map()) :: map()
  defp create_event(contact, args) do
    # Parse the datetime strings
    with {:ok, event_attrs} <- format_event_attrs(contact, args),
         {:ok, event} <- Scheduling.create_event(event_attrs) do
      %{success: true, event_id: event.id}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        %{success: false, errors: format_changeset_errors(changeset)}

      _ ->
        %{success: false, errors: "Invalid date/time format"}
    end
  end

  @spec find_available_slots(map()) :: map()
  defp find_available_slots(args) do
    # Parse the starting time or use current time
    start_time =
      case args["start_time"] do
        nil ->
          # Default to current time in Mountain Time
          DateTime.utc_now()

        time_str ->
          case DateTime.from_iso8601(time_str) do
            {:ok, dt, _} -> dt
            _ -> DateTime.utc_now()
          end
      end

    duration = args["duration"] || 30

    # Find available slots
    slots = Scheduling.find_available_time_slots(start_time, duration)

    # Format slots for display
    formatted_slots =
      Enum.map(slots, fn {slot_time, available_duration} ->
        # Convert to Mountain Time for display
        local_time =
          case DateTime.shift_zone(slot_time, "America/Denver") do
            {:ok, lt} ->
              lt

            _ ->
              # Fallback to manual conversion
              offset = if slot_time.month >= 3 and slot_time.month <= 10, do: -6, else: -7
              DateTime.add(slot_time, offset * 3600, :second)
          end

        %{
          start_time: DateTime.to_iso8601(slot_time),
          display_time: format_slot_display(local_time),
          available_duration_minutes: available_duration
        }
      end)

    %{success: true, slots: formatted_slots}
  end

  @spec format_event_attrs(%Contact{}, map()) :: {:ok, map()} | :error
  defp format_event_attrs(contact, args) do
    with {:ok, start_time} <- parse_event_datetime(args["start_time"]),
         {:ok, end_time} <- parse_event_datetime(args["end_time"]) do
      {:ok,
       %{
         name: args["name"] || "#{contact.first_name} #{contact.last_name}",
         description:
           args["description"] ||
             "Dog grooming appointment with #{contact.first_name} #{contact.last_name}",
         start_time: start_time,
         end_time: end_time,
         contact_ids: [contact.id]
       }}
    end
  end

  @spec format_slot_display(DateTime.t()) :: String.t()
  defp format_slot_display(datetime) do
    day = Calendar.strftime(datetime, "%A, %B %-d")
    time = Calendar.strftime(datetime, "%-I:%M %p")
    "#{day} at #{time}"
  end

  @spec format_changeset_errors(Ecto.Changeset.t()) :: String.t()
  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  @spec parse_event_datetime(String.t()) :: {:ok, DateTime.t()} | :error
  defp parse_event_datetime(datetime_str) do
    case DateTime.from_iso8601(datetime_str) do
      {:ok, datetime, _} -> {:ok, datetime}
      _ -> :error
    end
  end
end
