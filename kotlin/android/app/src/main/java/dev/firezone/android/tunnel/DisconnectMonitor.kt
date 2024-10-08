/* Licensed under Apache 2.0 (C) 2024 Firezone, Inc. */
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import dev.firezone.android.tunnel.TunnelService

// None of the TunnelService lifecycle callbacks are called when a user disconnects the VPN
// from the system settings. This class listens for network changes and shuts down the service
// when the network is lost, which achieves the same effect.
class DisconnectMonitor(private val tunnelService: TunnelService) : ConnectivityManager.NetworkCallback() {
    private var vpnNetwork: Network? = null

    // Android doesn't provide a good way to associate a network with a VPN service, so we
    // have to use the IP addresses of the tunnel to determine if the network is our VPN.
    override fun onLinkPropertiesChanged(
        network: Network,
        linkProperties: LinkProperties,
    ) {
        super.onLinkPropertiesChanged(network, linkProperties)

        if (tunnelService.tunnelIpv4Address.isNullOrBlank() || tunnelService.tunnelIpv6Address.isNullOrBlank()) {
            return
        }

        val ipv4Found = linkProperties.linkAddresses.find { it.address.hostAddress == tunnelService.tunnelIpv4Address }
        val ipv6Found = linkProperties.linkAddresses.find { it.address.hostAddress == tunnelService.tunnelIpv6Address }

        if (ipv4Found != null && ipv6Found != null) {
            // Matched both IPv4 and IPv6 addresses, this is our VPN network
            vpnNetwork = network
        }
    }

    override fun onLost(network: Network) {
        if (network == vpnNetwork) {
            tunnelService.disconnect()
        }

        super.onLost(network)
    }
}
