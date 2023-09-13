use anyhow::{anyhow, bail, Context, Result};
use clap::Parser;
use futures::channel::mpsc;
use futures::{future, FutureExt, SinkExt, StreamExt};
use opentelemetry::sdk::trace::TracerProvider;
use opentelemetry::trace::TracerProvider as _;
use opentelemetry_otlp::WithExportConfig;
use opentelemetry_stackdriver::Authorizer;
use phoenix_channel::{Error, Event, PhoenixChannel};
use prometheus_client::registry::Registry;
use rand::rngs::StdRng;
use rand::{Rng, SeedableRng};
use relay::{
    AddressFamily, Allocation, AllocationId, Command, IpStack, Server, Sleep, SocketAddrExt,
    UdpSocket,
};
use std::collections::hash_map::Entry;
use std::collections::HashMap;
use std::convert::Infallible;
use std::net::{Ipv4Addr, Ipv6Addr, SocketAddr};
use std::pin::Pin;
use std::task::Poll;
use std::time::SystemTime;
use tracing::level_filters::LevelFilter;
use tracing::{Span, Subscriber};
use tracing_core::Dispatch;
use tracing_stackdriver::CloudTraceConfiguration;
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;
use tracing_subscriber::{EnvFilter, Layer};
use url::Url;

#[derive(Parser, Debug)]
struct Args {
    /// The public (i.e. internet-reachable) IPv4 address of the relay server.
    #[arg(long, env)]
    public_ip4_addr: Option<Ipv4Addr>,
    /// The public (i.e. internet-reachable) IPv6 address of the relay server.
    #[arg(long, env)]
    public_ip6_addr: Option<Ipv6Addr>,
    /// The address of the local interface where we should serve the prometheus metrics.
    /// The metrics will be available at `http://<metrics_addr>/metrics`.
    #[arg(long, env)]
    metrics_addr: Option<SocketAddr>,
    // See https://www.rfc-editor.org/rfc/rfc8656.html#name-allocations
    /// The lowest port used for TURN allocations.
    #[arg(long, env, default_value = "49152")]
    lowest_port: u16,
    /// The highest port used for TURN allocations.
    #[arg(long, env, default_value = "65535")]
    highest_port: u16,
    /// The websocket URL of the portal server to connect to.
    #[arg(long, env, default_value = "wss://api.firezone.dev")]
    portal_ws_url: Url,
    /// Token generated by the portal to authorize websocket connection.
    ///
    /// If omitted, we won't connect to the portal on startup.
    #[arg(long, env)]
    portal_token: Option<String>,
    /// A seed to use for all randomness operations.
    ///
    /// Only available in debug builds.
    #[arg(long, env)]
    rng_seed: Option<u64>,

    /// How to format the logs.
    #[arg(long, env, default_value = "human")]
    log_format: LogFormat,

    /// Where to send trace data to.
    #[arg(long, env)]
    trace_collector: Option<TraceCollector>,

    /// Which OTLP collector we should connect to.
    ///
    /// This setting only has an effect if `TRACE_COLLECTOR` is set to `otlp`.
    #[arg(long, env, default_value = "127.0.0.1:4317")]
    otlp_grpc_endpoint: SocketAddr,

    /// The Google Project ID to embed in spans.
    ///
    /// Set this if you are running on Google Cloud but using the OTLP trace collector.
    /// OTLP is vendor-agnostic but for spans to be correctly recognised by Google Cloud, they need the project ID to be set.
    #[arg(long, env)]
    google_cloud_project_id: Option<String>,
}

#[derive(clap::ValueEnum, Debug, Clone, Copy)]
enum LogFormat {
    Human,
    Json,
    GoogleCloud,
}

#[derive(clap::ValueEnum, Debug, Clone, Copy)]
enum TraceCollector {
    /// Sends traces to Google Cloud Trace.
    GoogleCloudTrace,
    /// Sends traces to an OTLP collector.
    Otlp,
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();

    let root_span = setup_tracing(&args).await?;
    let _guard = root_span.enter();

    let public_addr = match (args.public_ip4_addr, args.public_ip6_addr) {
        (Some(ip4), Some(ip6)) => IpStack::Dual { ip4, ip6 },
        (Some(ip4), None) => IpStack::Ip4(ip4),
        (None, Some(ip6)) => IpStack::Ip6(ip6),
        (None, None) => {
            bail!("Must listen on at least one of IPv4 or IPv6")
        }
    };

    let mut metric_registry = Registry::with_prefix("relay");
    let server = Server::new(
        public_addr,
        make_rng(args.rng_seed),
        &mut metric_registry,
        args.lowest_port,
        args.highest_port,
    );

    let channel = if let Some(token) = args.portal_token {
        let mut url = args.portal_ws_url.clone();
        if !url.path().is_empty() {
            tracing::warn!("Overwriting path component of portal URL with '/relay/websocket'");
        }

        url.set_path("relay/websocket");
        url.query_pairs_mut().append_pair("token", &token);

        if let Some(public_ip4_addr) = args.public_ip4_addr {
            url.query_pairs_mut()
                .append_pair("ipv4", &public_ip4_addr.to_string());
        }
        if let Some(public_ip6_addr) = args.public_ip6_addr {
            url.query_pairs_mut()
                .append_pair("ipv6", &public_ip6_addr.to_string());
        }

        let mut channel = PhoenixChannel::<InboundPortalMessage, ()>::connect(
            url,
            format!("relay/{}", env!("CARGO_PKG_VERSION")),
        )
        .await
        .context("Failed to connect to the portal")?;

        tracing::info!("Connected to portal, waiting for init message",);

        channel.join(
            "relay",
            JoinMessage {
                stamp_secret: server.auth_secret().to_string(),
            },
        );

        loop {
            match future::poll_fn(|cx| channel.poll(cx))
                .await
                .context("portal connection failed")?
            {
                Event::JoinedRoom { topic } if topic == "relay" => {
                    tracing::info!("Joined relay room on portal")
                }
                Event::InboundMessage {
                    topic,
                    msg: InboundPortalMessage::Init {},
                } => {
                    tracing::info!("Received init message from portal on topic {topic}, starting relay activities");
                    break Some(channel);
                }
                other => {
                    tracing::debug!("Unhandled message from portal: {other:?}");
                }
            }
        }
    } else {
        tracing::warn!("No portal token supplied, starting standalone mode");

        None
    };

    let mut eventloop = Eventloop::new(server, channel, public_addr, &mut metric_registry)?;

    if let Some(metrics_addr) = args.metrics_addr {
        tokio::spawn(relay::metrics::serve(metrics_addr, metric_registry));
    }

    tracing::info!("Listening for incoming traffic on UDP port 3478");

    future::poll_fn(|cx| eventloop.poll(cx))
        .await
        .context("event loop failed")?;

    Ok(())
}

/// Sets up our tracing infrastructure.
///
/// See [`log_layer`] for details on the base log layer.
///
/// ## Integration with Google Cloud Trace
///
/// If the user has specified [`TraceCollector::GoogleCloudTrace`], we will attempt to connect to Google Cloud Trace.
/// This requires authentication.
/// Here is how we will attempt to obtain those, for details see <https://docs.rs/gcp_auth/0.9.0/gcp_auth/struct.AuthenticationManager.html#method.new>.
///
/// 1. Check if the `GOOGLE_APPLICATION_CREDENTIALS` environment variable if set; if so, use a custom service account as the token source.
/// 2. Look for credentials in `.config/gcloud/application_default_credentials.json`; if found, use these credentials to request refresh tokens.
/// 3. Send a HTTP request to the internal metadata server to retrieve a token; if it succeeds, use the default service account as the token source.
/// 4. Check if the `gcloud` tool is available on the PATH; if so, use the `gcloud auth print-access-token` command as the token source.
///
/// ## Integration with OTLP
///
/// If the user has specified [`TraceCollector::Otlp`], we will set up an OTLP-exporter that connects to an OTLP collector specified at `Args.otlp_grpc_endpoint`.
async fn setup_tracing(args: &Args) -> Result<Span> {
    // Use `tracing_core` directly for the temp logger because that one does not initialize a `log` logger.
    // A `log` Logger cannot be unset once set, so we can't use that for our temp logger during the setup.
    let temp_logger_guard = tracing_core::dispatcher::set_default(
        &tracing_subscriber::registry()
            .with(log_layer(args, args.google_cloud_project_id.clone()))
            .into(),
    );

    let dispatch: Dispatch = match args.trace_collector {
        None => tracing_subscriber::registry()
            .with(log_layer(args, args.google_cloud_project_id.clone()))
            .into(),
        Some(TraceCollector::GoogleCloudTrace) => {
            tracing::trace!("Setting up Google-Cloud-Trace collector");

            let authorizer = opentelemetry_stackdriver::GcpAuthorizer::new()
                .await
                .context("Failed to find GCP credentials")?;

            let project_id = authorizer.project_id().to_owned();

            tracing::trace!(%project_id, "Successfully retrieved authentication token for Google services");

            let (exporter, driver) = opentelemetry_stackdriver::Builder::default()
                .build(authorizer)
                .await
                .context("Failed to create StackDriverExporter")?;
            tokio::spawn(driver);

            let tracer = TracerProvider::builder()
                .with_batch_exporter(exporter, opentelemetry::runtime::Tokio)
                .build()
                .tracer("relay");

            tracing::trace!("Successfully initialized trace provider on tokio runtime");

            tracing_subscriber::registry()
                .with(log_layer(args, Some(project_id)))
                .with(tracing_opentelemetry::layer().with_tracer(tracer))
                .into()
        }
        Some(TraceCollector::Otlp) => {
            let grpc_endpoint = format!("http://{}", args.otlp_grpc_endpoint);

            tracing::trace!(%grpc_endpoint, "Setting up OTLP exporter for collector");

            let exporter = opentelemetry_otlp::new_exporter()
                .tonic()
                .with_endpoint(grpc_endpoint);

            let tracer = opentelemetry_otlp::new_pipeline()
                .tracing()
                .with_exporter(exporter)
                .install_batch(opentelemetry::runtime::Tokio)
                .context("Failed to create OTLP pipeline")?;

            tracing::trace!("Successfully initialized trace provider on tokio runtime");

            // TODO: This is where we could also configure metrics.

            tracing_subscriber::registry()
                .with(log_layer(args, args.google_cloud_project_id.clone()))
                .with(tracing_opentelemetry::layer().with_tracer(tracer))
                .into()
        }
    };

    drop(temp_logger_guard); // Drop as late as possible

    dispatch
        .try_init()
        .context("Failed to initialize tracing")?;

    // If we have a trace collector, we must define a root span, otherwise traces will not be sampled, i.e. discarded.
    let root_span = if args.trace_collector.is_some() {
        tracing::error_span!("root")
    } else {
        Span::none()
    };

    Ok(root_span)
}

/// Constructs the base log layer.
///
/// The user has a choice between:
///
/// - human-centered formatting
/// - JSON-formatting
/// - Google Cloud optimised formatting
fn log_layer<T>(
    args: &Args,
    google_cloud_trace_project_id: Option<String>,
) -> Box<dyn Layer<T> + Send + Sync>
where
    T: Subscriber + for<'a> tracing_subscriber::registry::LookupSpan<'a>,
{
    let env_filter = EnvFilter::builder()
        .with_default_directive(LevelFilter::INFO.into())
        .from_env_lossy();

    let log_layer = match (args.log_format, google_cloud_trace_project_id) {
        (LogFormat::Human, _) => tracing_subscriber::fmt::layer().boxed(),
        (LogFormat::Json, _) => tracing_subscriber::fmt::layer().json().boxed(),
        (LogFormat::GoogleCloud, None) => {
            tracing::warn!("Emitting logs in Google Cloud format but without the project ID set. Spans will be emitted without IDs!");

            tracing_stackdriver::layer().boxed()
        }
        (LogFormat::GoogleCloud, Some(project_id)) => tracing_stackdriver::layer()
            .with_cloud_trace(CloudTraceConfiguration { project_id })
            .boxed(),
    };

    log_layer.with_filter(env_filter).boxed()
}

#[derive(serde::Serialize, PartialEq, Debug)]
struct JoinMessage {
    stamp_secret: String,
}

#[derive(serde::Deserialize, PartialEq, Debug)]
#[serde(rename_all = "snake_case", tag = "event", content = "payload")]
enum InboundPortalMessage {
    Init {},
}

#[cfg(debug_assertions)]
fn make_rng(seed: Option<u64>) -> StdRng {
    let Some(seed) = seed else {
        return StdRng::from_entropy();
    };

    tracing::info!("Seeding RNG from '{seed}'");

    StdRng::seed_from_u64(seed)
}

#[cfg(not(debug_assertions))]
fn make_rng(seed: Option<u64>) -> StdRng {
    if seed.is_some() {
        tracing::debug!("Ignoring rng-seed because we are running in release mode");
    }

    StdRng::from_entropy()
}

struct Eventloop<R> {
    inbound_data_receiver: mpsc::Receiver<(Vec<u8>, SocketAddr)>,
    outbound_ip4_data_sender: mpsc::Sender<(Vec<u8>, SocketAddr)>,
    outbound_ip6_data_sender: mpsc::Sender<(Vec<u8>, SocketAddr)>,
    server: Server<R>,
    channel: Option<PhoenixChannel<InboundPortalMessage, ()>>,
    allocations: HashMap<(AllocationId, AddressFamily), Allocation>,
    relay_data_sender: mpsc::Sender<(Vec<u8>, SocketAddr, AllocationId)>,
    relay_data_receiver: mpsc::Receiver<(Vec<u8>, SocketAddr, AllocationId)>,
    sleep: Sleep,
}

impl<R> Eventloop<R>
where
    R: Rng,
{
    fn new(
        server: Server<R>,
        channel: Option<PhoenixChannel<InboundPortalMessage, ()>>,
        public_address: IpStack,
        _: &mut Registry,
    ) -> Result<Self> {
        let (relay_data_sender, relay_data_receiver) = mpsc::channel(1);
        let (inbound_data_sender, inbound_data_receiver) = mpsc::channel(10);
        let (outbound_ip4_data_sender, outbound_ip4_data_receiver) =
            mpsc::channel::<(Vec<u8>, SocketAddr)>(10);
        let (outbound_ip6_data_sender, outbound_ip6_data_receiver) =
            mpsc::channel::<(Vec<u8>, SocketAddr)>(10);

        if public_address.as_v4().is_some() {
            tokio::spawn(main_udp_socket_task(
                AddressFamily::V4,
                inbound_data_sender.clone(),
                outbound_ip4_data_receiver,
            ));
        }
        if public_address.as_v6().is_some() {
            tokio::spawn(main_udp_socket_task(
                AddressFamily::V6,
                inbound_data_sender,
                outbound_ip6_data_receiver,
            ));
        }

        Ok(Self {
            inbound_data_receiver,
            outbound_ip4_data_sender,
            outbound_ip6_data_sender,
            server,
            channel,
            allocations: Default::default(),
            relay_data_sender,
            relay_data_receiver,
            sleep: Sleep::default(),
        })
    }

    fn poll(&mut self, cx: &mut std::task::Context<'_>) -> Poll<Result<()>> {
        loop {
            let now = SystemTime::now();

            // Priority 1: Execute the pending commands of the server.
            if let Some(next_command) = self.server.next_command() {
                match next_command {
                    Command::SendMessage { payload, recipient } => {
                        let sender = match recipient.family() {
                            AddressFamily::V4 => &mut self.outbound_ip4_data_sender,
                            AddressFamily::V6 => &mut self.outbound_ip6_data_sender,
                        };

                        if let Err(e) = sender.try_send((payload, recipient)) {
                            if e.is_disconnected() {
                                return Poll::Ready(Err(anyhow!(
                                    "Channel to primary UDP socket task has been closed"
                                )));
                            }

                            if e.is_full() {
                                tracing::warn!(%recipient, "Dropping message because channel to primary UDP socket task is full");
                            }
                        }
                    }
                    Command::CreateAllocation { id, family, port } => {
                        self.allocations.insert(
                            (id, family),
                            Allocation::new(self.relay_data_sender.clone(), id, family, port),
                        );
                    }
                    Command::FreeAllocation { id, family } => {
                        if self.allocations.remove(&(id, family)).is_none() {
                            tracing::debug!("Unknown allocation {id}");
                            continue;
                        };

                        tracing::info!("Freeing addresses of allocation {id}");
                    }
                    Command::Wake { deadline } => {
                        match deadline.duration_since(now) {
                            Ok(duration) => {
                                tracing::trace!(?duration, "Suspending event loop")
                            }
                            Err(e) => {
                                let difference = e.duration();

                                tracing::warn!(
                                    ?difference,
                                    "Wake time is already in the past, waking now"
                                )
                            }
                        }

                        Pin::new(&mut self.sleep).reset(deadline);
                    }
                    Command::ForwardData { id, data, receiver } => {
                        let mut allocation = match self.allocations.entry((id, receiver.family())) {
                            Entry::Occupied(entry) => entry,
                            Entry::Vacant(_) => {
                                tracing::debug!(allocation = %id, family = %receiver.family(), "Unknown allocation");
                                continue;
                            }
                        };

                        if allocation.get_mut().send(data, receiver).is_err() {
                            self.server.handle_allocation_failed(id);
                            allocation.remove();
                        }
                    }
                }

                continue; // Attempt to process more commands.
            }

            // Priority 2: Handle time-sensitive tasks:
            if self.sleep.poll_unpin(cx).is_ready() {
                self.server.handle_deadline_reached(now);
                continue; // Handle potentially new commands.
            }

            // Priority 3: Handle relayed data (we prioritize latency for existing allocations over making new ones)
            if let Poll::Ready(Some((data, sender, allocation))) =
                self.relay_data_receiver.poll_next_unpin(cx)
            {
                self.server.handle_relay_input(&data, sender, allocation);
                continue; // Handle potentially new commands.
            }

            // Priority 4: Accept new allocations / answer STUN requests etc
            if let Poll::Ready(Some((buffer, sender))) =
                self.inbound_data_receiver.poll_next_unpin(cx)
            {
                self.server.handle_client_input(&buffer, sender, now);
                continue; // Handle potentially new commands.
            }

            // Priority 5: Handle portal messages
            match self.channel.as_mut().map(|c| c.poll(cx)) {
                Some(Poll::Ready(Ok(Event::InboundMessage {
                    msg: InboundPortalMessage::Init {},
                    ..
                }))) => {
                    tracing::warn!("Received init message during operation");
                    continue;
                }
                Some(Poll::Ready(Err(Error::Serde(e)))) => {
                    tracing::warn!("Failed to deserialize portal message: {e}");
                    continue; // This is not a hard-error, we can continue.
                }
                Some(Poll::Ready(Err(e))) => {
                    return Poll::Ready(Err(anyhow!("Portal connection failed: {e}")));
                }
                Some(Poll::Ready(Ok(Event::SuccessResponse { res: (), .. }))) => {
                    continue;
                }
                Some(Poll::Ready(Ok(Event::JoinedRoom { topic }))) => {
                    tracing::info!("Successfully joined room '{topic}'");
                    continue;
                }
                Some(Poll::Ready(Ok(Event::ErrorResponse {
                    topic,
                    req_id,
                    reason,
                }))) => {
                    tracing::warn!("Request with ID {req_id} on topic {topic} failed: {reason}");
                    continue;
                }
                Some(Poll::Ready(Ok(Event::InboundReq {
                    req: InboundPortalMessage::Init {},
                    ..
                }))) => {
                    return Poll::Ready(Err(anyhow!("Init message is not a request")));
                }
                Some(Poll::Ready(Ok(Event::HeartbeatSent))) => {
                    tracing::debug!("Heartbeat sent to relay");
                    continue;
                }
                Some(Poll::Pending) | None => {}
            }

            return Poll::Pending;
        }
    }
}

async fn main_udp_socket_task(
    family: AddressFamily,
    mut inbound_data_sender: mpsc::Sender<(Vec<u8>, SocketAddr)>,
    mut outbound_data_receiver: mpsc::Receiver<(Vec<u8>, SocketAddr)>,
) -> Result<Infallible> {
    let mut socket = UdpSocket::bind(family, 3478)?;

    loop {
        tokio::select! {
            result = socket.recv() => {
                let (data, sender) = result?;
                inbound_data_sender.send((data.to_vec(), sender)).await?;
            }
            maybe_item = outbound_data_receiver.next() => {
                let (data, recipient) = maybe_item.context("Outbound data channel closed")?;
                socket.send_to(data.as_ref(), recipient).await?;
            }
        }
    }
}
