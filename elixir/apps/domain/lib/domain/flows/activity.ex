defmodule Domain.Flows.Activity do
  use Domain, :schema

  schema "flow_activities" do
    field :window_started_at, :utc_datetime
    field :window_ended_at, :utc_datetime

    field :destination, Domain.Types.ProtocolIPPort
    field :rx_bytes, :integer
    field :tx_bytes, :integer
    field :blocked_tx_bytes, :integer

    field :connectivity_type, Ecto.Enum, values: [:relayed, :direct]

    belongs_to :flow, Domain.Flows.Flow
    belongs_to :account, Domain.Accounts.Account
  end
end
