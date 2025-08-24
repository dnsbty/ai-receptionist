defmodule Receptionist.Agent.Error do
  @moduledoc """
  Error struct for OpenAI API errors.
  """

  defstruct [:message, :type, :code]

  @type t :: %__MODULE__{
    message: String.t(),
    type: String.t() | nil,
    code: String.t() | nil
  }

  @doc """
  Create an Error struct from an API error response.
  """
  def from_map(%{"error" => error}) do
    %__MODULE__{
      message: error["message"],
      type: error["type"],
      code: error["code"]
    }
  end

  def from_map(map) when is_map(map) do
    %__MODULE__{
      message: inspect(map)
    }
  end
end