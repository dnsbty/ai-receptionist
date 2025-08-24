defmodule Receptionist.Agent.OpenAi do
  @moduledoc """
  A client for interacting the OpenAI API.
  """

  alias Receptionist.Agent.Error

  @base_url "https://api.openai.com"

  @doc """
  Create a conversation.

  Conversations can be used for tracking the state of a multi-turn chat so that
  we don't have to store all the context in our own system.

  See https://platform.openai.com/docs/api-reference/conversations/create
  """
  @spec create_conversation(%{
          optional(:metadata) => %{String.t() => String.t()},
          optional(:items) => [
            %{
              role: :assistant | :developer | :system | :user,
              content: String.t()
            }
          ]
        }) :: {:ok, map()} | {:error, Receptionist.Agent.Error.t()}
  def create_conversation(payload) do
    base_request()
    |> Req.post(url: "/v1/conversations", json: payload)
    |> expect_status(200)
  end

  @doc """
  Create a new response from the model.

  See https://platform.openai.com/docs/api-reference/responses/create
  """
  @spec create_response(%{
          optional(:conversation) => String.t(),
          optional(:input) =>
            String.t()
            | [
                %{
                  :arguments => String.t(),
                  :call_id => String.t(),
                  :name => String.t(),
                  :type => :function_call,
                  optional(:id) => String.t(),
                  optional(:status) => :in_progress | :completed | :incomplete
                }
              ],
          optional(:model) => String.t(),
          optional(:parallel_tool_calls) => boolean(),
          optional(:tools) => [
            %{
              :name => String.t(),
              :parameters => map(),
              :strict => boolean(),
              :type => :function,
              optional(:description) => String.t()
            }
          ]
        }) :: {:ok, map()} | {:error, Error.t()}
  def create_response(payload) do
    base_request()
    |> Req.post(url: "/v1/responses", json: payload)
    |> expect_status(200)
  end

  # Private

  @spec base_request :: Req.Request.t()
  defp base_request do
    api_key = Application.fetch_env!(:receptionist, :openai_api_key)
    headers = [accept: "application/json"]
    Req.new(base_url: @base_url, headers: headers, auth: {:bearer, api_key})
  end

  @spec expect_status({:ok, Req.Response.t()} | {:error, any()}, atom() | 100..599) ::
          {:ok, map()} | {:error, Receptionist.Agent.Error.t() | any()}
  defp expect_status({:ok, response}, status) do
    cond do
      response.status == status ->
        {:ok, response.body}

      match?(%{"error" => _}, response.body) ->
        IO.inspect(response.body, label: "OpenAI API Error")
        {:error, Error.from_map(response.body)}

      true ->
        {:error,
         %Error{
           message:
             "Unexpected response with status #{response.status}: #{inspect(response.body)}"
         }}
    end
  end

  defp expect_status({:error, reason}, _status) do
    {:error, reason}
  end
end
