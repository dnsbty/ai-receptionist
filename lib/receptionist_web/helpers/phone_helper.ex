defmodule ReceptionistWeb.PhoneHelper do
  @moduledoc """
  Helper functions for formatting phone numbers for display.
  """

  @doc """
  Formats a phone number from E.164 format to a human-readable format.

  ## Examples

      iex> format_phone("+14155552671")
      "(415) 555-2671"
      
      iex> format_phone("+442071838750")
      "+44 20 7183 8750"
  """
  def format_phone(nil), do: ""

  def format_phone(phone_number) when is_binary(phone_number) do
    # Default to US region for parsing
    case ExPhoneNumber.parse(phone_number, "US") do
      {:ok, parsed} ->
        # Always use national format for US numbers
        ExPhoneNumber.format(parsed, :national)

      {:error, _} ->
        # If parsing fails, return the original string
        phone_number
    end
  end

  def format_phone(_), do: ""
end
