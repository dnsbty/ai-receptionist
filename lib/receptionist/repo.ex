defmodule Receptionist.Repo do
  use Ecto.Repo,
    otp_app: :receptionist,
    adapter: Ecto.Adapters.SQLite3
end
