defmodule API.Client.Views.Resource do
  alias API.Client.Views
  alias Domain.Resources

  def render_many(resources) do
    Enum.map(resources, &render/1)
  end

  def render(%Resources.Resource{type: :ip} = resource) do
    {:ok, inet} = Domain.Types.IP.cast(resource.address)
    netmask = Domain.Types.CIDR.max_netmask(inet)
    address = to_string(%{inet | netmask: netmask})

    %{
      id: resource.id,
      type: :cidr,
      address: address,
      # TODO: This is a workaround due to clients expecting address_description not
      # to be null. Remove this to send null address_description on or after 8/13/24
      # once we can reasonably expect clients to have upgraded.
      address_description: resource.address_description || address,
      name: resource.name,
      gateway_groups: Views.GatewayGroup.render_many(resource.gateway_groups),
      filters: Enum.flat_map(resource.filters, &render_filter/1)
    }
  end

  def render(%Resources.Resource{} = resource) do
    %{
      id: resource.id,
      type: resource.type,
      address: resource.address,
      # TODO: This is a workaround due to clients expecting address_description not
      # to be null. Remove this to send null address_description on or after 8/13/24
      # once we can reasonably expect clients to have upgraded.
      address_description: resource.address_description || resource.address,
      name: resource.name,
      gateway_groups: Views.GatewayGroup.render_many(resource.gateway_groups),
      filters: Enum.flat_map(resource.filters, &render_filter/1)
    }
  end

  def render_filter(%Resources.Resource.Filter{ports: ports} = filter) when length(ports) > 0 do
    Enum.map(filter.ports, fn port ->
      case String.split(port, "-") do
        [port_start, port_end] ->
          port_start = port_to_number(port_start)
          port_end = port_to_number(port_end)

          %{
            protocol: filter.protocol,
            port_range_start: port_start,
            port_range_end: port_end
          }

        [port] ->
          port = port_to_number(port)

          %{
            protocol: filter.protocol,
            port_range_start: port,
            port_range_end: port
          }
      end
    end)
  end

  def render_filter(%Resources.Resource.Filter{} = filter) do
    [
      %{
        protocol: filter.protocol
      }
    ]
  end

  defp port_to_number(port) do
    port |> String.trim() |> String.to_integer()
  end
end
