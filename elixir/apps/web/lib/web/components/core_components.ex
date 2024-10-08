defmodule Web.CoreComponents do
  @moduledoc """
  Provides core UI components.

  The components in this module use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn how to
  customize the generated components in this module.

  Icons are provided by [heroicons](https://heroicons.com), using the
  [heroicons_elixir](https://github.com/mveytsman/heroicons_elixir) project.
  """
  use Phoenix.Component
  use Web, :verified_routes
  alias Phoenix.LiveView.JS
  alias Domain.Actors

  attr :text, :string, default: "Welcome to Firezone."

  def hero_logo(assigns) do
    ~H"""
    <div class="mb-6">
      <img src={~p"/images/logo.svg"} class="mx-auto pr-10 h-24" alt="Firezone Logo" />
      <p class="text-center mt-4 text-3xl">
        <%= @text %>
      </p>
    </div>
    """
  end

  def logo(assigns) do
    ~H"""
    <a href={~p"/"} class="flex items-center mb-6 text-2xl">
      <img src={~p"/images/logo.svg"} class="mr-3 h-8" alt="Firezone Logo" />
      <span class="self-center text-2xl font-medium whitespace-nowrap">
        Firezone
      </span>
    </a>
    """
  end

  @doc """
  Renders a generic <p> tag using our color scheme.

  ## Examples

    <.p>
      Hello world
    </.p>
  """
  def p(assigns) do
    ~H"""
    <p class="text-neutral-700"><%= render_slot(@inner_block) %></p>
    """
  end

  @doc """
  Render a monospace code block suitable for copying and pasting content.

  ## Examples

  <.code_block id="foo">
    The lazy brown fox jumped over the quick dog.
  </.code_block>
  """
  attr :id, :string, required: true
  attr :class, :string, default: ""
  slot :inner_block, required: true
  attr :rest, :global

  def code_block(assigns) do
    ~H"""
    <div id={@id} phx-hook="Copy" class="relative">
      <div id={"#{@id}-nested"} class={[~w[
        text-sm text-left text-neutral-50
        inline-flex items-center
        space-x-4 p-4 pl-6
        bg-neutral-800
        overflow-x-auto
      ], @class]} {@rest}>
        <code class="block w-full no-scrollbar whitespace-pre rounded-b" data-copy phx-no-format><%= render_slot(@inner_block) %></code>
      </div>

      <span title="Click to copy" class={~w[
            absolute top-1 right-1
            items-center
            cursor-pointer
            rounded
            p-1
            text-xs
            text-neutral-50
            hover:bg-neutral-50
            hover:text-neutral-900
            hover:opacity-50
          ]}>
        <.icon name="hero-clipboard-document" data-icon class="h-4 w-4" />
      </span>
    </div>
    """
  end

  @doc """
  Render an inlined copy-paste button to the right of the content block.

  ## Examples

  <.copy id="foo">
    The lazy brown fox jumped over the quick dog.
  </.copy>
  """
  attr :id, :string, required: true
  attr :class, :string, default: ""
  slot :inner_block, required: true
  attr :rest, :global

  def copy(assigns) do
    ~H"""
    <div id={@id} phx-hook="Copy" class={@class} {@rest}>
      <code data-copy phx-no-format><%= render_slot(@inner_block) %></code>
      <span class={~w[text-neutral-400 cursor-pointer rounded]}>
        <.icon name="hero-clipboard-document" data-icon class="h-4 w-4" />
      </span>
    </div>
    """
  end

  @doc """
  Render a tabs toggle container and its content.

  ## Examples

  <.tabs id={"hello-world"}>
    <:tab id={"hello"} label={"Hello"}>
      <p>Hello</p>
    </:tab>
    <:tab id={"world"} label={"World"}>
      <p>World</p>
    </:tab>
  </.tabs>
  """

  attr :id, :string, required: true, doc: "ID of the tabs container"

  slot :tab, required: true, doc: "Tab content" do
    attr :id, :string, required: true, doc: "ID of the tab"
    attr :label, :any, required: true, doc: "Display label for the tab"
    attr :icon, :string, doc: "Icon for the tab"
    attr :selected, :boolean, doc: "Whether the tab is selected"
    attr :phx_click, :any, doc: "Phoenix click event"
  end

  attr :rest, :global

  def tabs(assigns) do
    ~H"""
    <div class="mb-4 rounded shadow">
      <div
        class="border-neutral-100 border-b-2 bg-neutral-50 rounded-t"
        id={"#{@id}-container"}
        phx-hook="Tabs"
        {@rest}
      >
        <ul
          class="flex flex-wrap text-sm text-center"
          id={"#{@id}-ul"}
          data-tabs-toggle={"##{@id}"}
          role="tablist"
        >
          <%= for tab <- @tab do %>
            <% tab = Map.put(tab, :icon, Map.get(tab, :icon, nil)) %>
            <li class="mr-2" role="presentation">
              <button
                class={
                  [
                    # ! is needed to override Flowbite's default styles
                    (Map.get(tab, :selected) &&
                       "!rounded-t-lg !font-medium !text-accent-600 !border-accent-600") ||
                      "!text-neutral-500 !hover:border-accent-700 !hover:text-accent-600",
                    "inline-block p-4 border-b-2"
                  ]
                }
                id={"#{tab.id}-tab"}
                data-tabs-target={"##{tab.id}"}
                type="button"
                role="tab"
                aria-controls={tab.id}
                aria-selected={(Map.get(tab, :selected) && "true") || "false"}
                phx-click={Map.get(tab, :phx_click)}
                phx-value-id={tab.id}
              >
                <span class="flex items-center">
                  <%= if tab.icon do %>
                    <.icon name={tab.icon} class="h-4 w-4 mr-2" />
                  <% end %>
                  <%= tab.label %>
                </span>
              </button>
            </li>
          <% end %>
        </ul>
      </div>
      <div id={@id}>
        <%= for tab <- @tab do %>
          <div
            class="hidden rounded-b bg-white"
            id={tab.id}
            role="tabpanel"
            aria-labelledby={"#{tab.id}-tab"}
          >
            <%= render_slot(tab) %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Render a section header. Section headers are used in the main content section
  to provide a title for the content and option actions button(s) aligned on the right.

  ## Examples

    <.section>
      <:title>
        All gateways
      </:title>
      <:actions>
        <.add_button navigate={~p"/gateways/new"}>
          Deploy gateway
        </.add_button>
      </:actions>
    </.section>
  """
  slot :title, required: true, doc: "Title of the section"
  slot :actions, required: false, doc: "Buttons or other action elements"
  slot :help, required: false, doc: "A slot for help text to be displayed blow the title"

  def header(assigns) do
    ~H"""
    <div class="py-6 px-1">
      <div class="grid grid-cols-1 xl:grid-cols-3 xl:gap-4">
        <div class="col-span-full">
          <div class="flex justify-between items-center">
            <h2 class="text-2xl leading-none tracking-tight text-neutral-900">
              <%= render_slot(@title) %>
            </h2>
            <div class="inline-flex justify-between items-center space-x-2">
              <%= render_slot(@actions) %>
            </div>
          </div>
        </div>
      </div>
      <div :for={help <- @help} class="pt-3 text-neutral-400">
        <%= render_slot(help) %>
      </div>
    </div>
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, default: "flash", doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil

  attr :kind, :atom,
    values: [:success, :info, :warning, :error],
    doc: "used for styling and flash lookup"

  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"
  attr :style, :string, default: "pill"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      class={[
        "p-4 text-sm flash-#{@kind}",
        @kind == :success && "text-green-800 bg-green-100",
        @kind == :info && "text-blue-800 bg-blue-100",
        @kind == :warning && "text-yellow-800 bg-yellow-100",
        @kind == :error && "text-red-800 bg-red-100",
        @style != "wide" && "mb-4 rounded"
      ]}
      role="alert"
      {@rest}
    >
      <p :if={@title} class="flex items-center gap-1.5 text-sm font-semibold leading-6">
        <.icon :if={@kind == :info} name="hero-information-circle-mini" class="h-4 w-4" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle-mini" class="h-4 w-4" />
        <%= @title %>
      </p>
      <%= maybe_render_changeset_as_flash(msg) %>
    </div>
    """
  end

  def maybe_render_changeset_as_flash({:validation_errors, message, errors}) do
    assigns = %{message: message, errors: errors}

    ~H"""
    <%= @message %>:
    <ul>
      <li :for={{field, field_errors} <- @errors}>
        <%= field %>: <%= Enum.join(field_errors, ", ") %>
      </li>
    </ul>
    """
  end

  def maybe_render_changeset_as_flash(other) do
    other
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  def flash_group(assigns) do
    ~H"""
    <.flash kind={:info} title="Success!" flash={@flash} />
    <.flash kind={:error} title="Error!" flash={@flash} />
    <.flash
      id="disconnected"
      kind={:error}
      title="We can't find the internet"
      phx-disconnected={show("#disconnected")}
      phx-connected={hide("#disconnected")}
      hidden
    >
      Attempting to reconnect <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
    </.flash>
    """
  end

  @doc """
  Renders a standard form label.
  """
  attr :for, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class={["block text-sm text-neutral-900 mb-2", @class]}>
      <%= render_slot(@inner_block) %>
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  attr :rest, :global
  slot :inner_block, required: true
  attr :inline, :boolean, default: false

  def error(assigns) do
    ~H"""
    <p
      class={[
        "flex items-center gap-2 text-sm leading-6",
        "text-rose-600",
        (@inline && "ml-2") || "mt-2 w-full"
      ]}
      {@rest}
    >
      <.icon name="hero-exclamation-circle-mini" class="h-4 w-4 flex-none" />
      <%= render_slot(@inner_block) %>
    </p>
    """
  end

  @doc """
  Generates an error message for a form where it's not related to a specific field but rather to the form itself,
  eg. when there is an internal error during API call or one fields not rendered as a form field is invalid.

  ### Examples

      <.base_error form={@form} field={:base} />
  """
  attr :form, :any, required: true, doc: "the form"
  attr :field, :atom, doc: "field name"
  attr :rest, :global

  def base_error(assigns) do
    assigns = assign_new(assigns, :error, fn -> assigns.form.errors[assigns.field] end)

    ~H"""
    <p
      :if={@error}
      data-validation-error-for={"#{@form.id}[#{@field}]"}
      class="mt-3 mb-3 flex gap-3 text-m leading-6 text-rose-600"
      {@rest}
    >
      <.icon name="hero-exclamation-circle-mini" class="mt-0.5 h-5 w-5 flex-none" />
      <%= translate_error(@error) %>
    </p>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title"><%= @post.title %></:item>
        <:item title="Views"><%= @post.views %></:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <div class="mt-14">
      <dl class="-my-4 divide-y divide-neutral-100">
        <div :for={item <- @item} class="flex gap-4 py-4 text-sm leading-6 sm:gap-8">
          <dt class="w-1/4 flex-none text-neutral-500"><%= item.title %></dt>
          <dd class="text-neutral-700"><%= render_slot(item) %></dd>
        </div>
      </dl>
    </div>
    """
  end

  @doc """
  Renders a [Hero Icon](https://heroicons.com).

  Hero icons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from your `assets/vendor/heroicons` directory and bundled
  within your compiled app.css by the plugin in your `assets/tailwind.config.js`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: nil
  attr :rest, :global

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} {@rest} />
    """
  end

  def icon(%{name: "spinner"} = assigns) do
    ~H"""
    <svg
      class={["inline-block", @class]}
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      {@rest}
    >
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4">
      </circle>
      <path
        class="opacity-75"
        fill="currentColor"
        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
      >
      </path>
    </svg>
    """
  end

  def icon(%{name: "terraform"} = assigns) do
    ~H"""
    <span class={"inline-flex " <> @class} @rest>
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">
        <g fill-rule="evenodd">
          <path d="M77.941 44.5v36.836L46.324 62.918V26.082zm0 0" fill="currentColor" />
          <path d="M81.41 81.336l31.633-18.418V26.082L81.41 44.5zm0 0" fill="currentColor" />
          <path
            d="M11.242 42.36L42.86 60.776V23.941L11.242 5.523zm0 0M77.941 85.375L46.324 66.957v36.82l31.617 18.418zm0 0"
            fill="currentColor"
          />
        </g>
      </svg>
    </span>
    """
  end

  def icon(%{name: "docker"} = assigns) do
    ~H"""
    <span class={"inline-flex " <> @class} @rest>
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 756.26 596.9">
        <defs>
          <style>
            .cls-1 {
              stroke-width: 0px;
            }
          </style>
        </defs>
        <path
          fill="currentColor"
          class="cls-1"
          d="M743.96,245.25c-18.54-12.48-67.26-17.81-102.68-8.27-1.91-35.28-20.1-65.01-53.38-90.95l-12.32-8.27-8.21,12.4c-16.14,24.5-22.94,57.14-20.53,86.81,1.9,18.28,8.26,38.83,20.53,53.74-46.1,26.74-88.59,20.67-276.77,20.67H.06c-.85,42.49,5.98,124.23,57.96,190.77,5.74,7.35,12.04,14.46,18.87,21.31,42.26,42.32,106.11,73.35,201.59,73.44,145.66.13,270.46-78.6,346.37-268.97,24.98.41,90.92,4.48,123.19-57.88.79-1.05,8.21-16.54,8.21-16.54l-12.3-8.27ZM189.67,206.39h-81.7v81.7h81.7v-81.7ZM295.22,206.39h-81.7v81.7h81.7v-81.7ZM400.77,206.39h-81.7v81.7h81.7v-81.7ZM506.32,206.39h-81.7v81.7h81.7v-81.7ZM84.12,206.39H2.42v81.7h81.7v-81.7ZM189.67,103.2h-81.7v81.7h81.7v-81.7ZM295.22,103.2h-81.7v81.7h81.7v-81.7ZM400.77,103.2h-81.7v81.7h81.7v-81.7ZM400.77,0h-81.7v81.7h81.7V0Z"
        />
      </svg>
    </span>
    """
  end

  @doc """
  Renders Gravatar img tag.
  """
  attr :email, :string, required: true
  attr :size, :integer, default: 40
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  def gravatar(assigns) do
    ~H"""
    <img
      src={"https://www.gravatar.com/avatar/#{Base.encode16(:crypto.hash(:md5, @email), case: :lower)}?s=#{@size}&d=retro"}
      {@rest}
    />
    """
  end

  @doc """
  Intersperses separator slot between a list of items.

  Useful when you need to add a separator between items such as when
  rendering breadcrumbs for navigation. Provides each item to the
  inner block.

  ## Examples

  ```heex
  <.intersperse_blocks>
    <:separator>
      <span class="sep">|</span>
    </:separator>

    <:empty>
      nothing
    </:empty>

    <:item>
      home
    </:item>

    <:item>
      profile
    </:item>

    <:item>
      settings
    </:item>
  </.intersperse_blocks>
  ```
  """
  slot :separator, required: false, doc: "the slot for the separator"
  slot :item, required: true, doc: "the slots to intersperse with separators"
  slot :empty, required: false, doc: "the slots to render when there are no items"

  def intersperse_blocks(assigns) do
    ~H"""
    <%= if Enum.empty?(@item) do %>
      <%= render_slot(@empty) %>
    <% else %>
      <%= for item <- Enum.intersperse(@item, :separator) do %>
        <%= if item == :separator do %>
          <%= render_slot(@separator) %>
        <% else %>
          <%= render_slot(
            item,
            cond do
              item == List.first(@item) -> :first
              item == List.last(@item) -> :last
              true -> :middle
            end
          ) %>
        <% end %>
      <% end %>
    <% end %>
    """
  end

  @doc """
  Render children preview.

  Allows to render peeks into a schema preload by rendering a few of the children with a count of remaining ones.

  ## Examples

  ```heex
  <.peek>
    <:empty>
      nobody
    </:empty>

    <:item :let={item}>
      <%= item %>
    </:item>

    <:separator>
      ,
    </:separator>

    <:tail :let={count}>
      <%= count %> more.
    </:tail>
  </.peek>
  ```
  """
  attr :peek, :any,
    required: true,
    doc: "a tuple with the total number of items and items for a preview"

  slot :empty, required: false, doc: "the slots to render when there are no items"
  slot :item, required: true, doc: "the slots to intersperse with separators"
  slot :separator, required: false, doc: "the slot for the separator"
  slot :tail, required: true, doc: "the slots to render to show the remaining count"

  slot :call_to_action,
    required: false,
    doc: "the slot to render to show the call to action after the peek"

  def peek(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-y-2">
      <%= if Enum.empty?(@peek.items) do %>
        <%= render_slot(@empty) %>
      <% else %>
        <% items = if @separator, do: Enum.intersperse(@peek.items, :separator), else: @peek.items %>
        <%= for item <- items do %>
          <%= if item == :separator do %>
            <%= render_slot(@separator) %>
          <% else %>
            <%= render_slot(@item, item) %>
          <% end %>
        <% end %>

        <%= if @peek.count > length(@peek.items) do %>
          <%= render_slot(@tail, @peek.count - length(@peek.items)) %>
        <% end %>

        <%= render_slot(@call_to_action) %>
      <% end %>
    </div>
    """
  end

  attr :type, :string, default: "neutral"
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def badge(assigns) do
    colors = %{
      "success" => "bg-green-100 text-green-800 ",
      "danger" => "bg-red-100 text-red-800",
      "warning" => "bg-yellow-100 text-yellow-800",
      "info" => "bg-blue-100 text-blue-800",
      "primary" => "bg-primary-400 text-primary-800",
      "accent" => "bg-accent-200 text-accent-800",
      "neutral" => "bg-neutral-100 text-neutral-800"
    }

    assigns = assign(assigns, colors: colors)

    ~H"""
    <span
      class={[
        "text-xs px-2.5 py-0.5 rounded whitespace-nowrap",
        @colors[@type],
        @class
      ]}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  attr :type, :string, default: "neutral"

  slot :left, required: true
  slot :right, required: true

  def dual_badge(assigns) do
    colors = %{
      "success" => %{
        "dark" => "bg-green-300 text-green-800",
        "light" => "bg-green-100 text-green-800"
      },
      "danger" => %{
        "dark" => "bg-red-300 text-red-800",
        "light" => "bg-red-100 text-red-800"
      },
      "warning" => %{
        "dark" => "bg-yellow-300 text-yellow-800",
        "light" => "bg-yellow-100 text-yellow-800"
      },
      "info" => %{
        "dark" => "bg-blue-300 text-blue-800",
        "light" => "bg-blue-100 text-blue-800"
      },
      "primary" => %{
        "dark" => "bg-primary-400 text-primary-800",
        "light" => "bg-primary-100 text-primary-800"
      },
      "accent" => %{
        "dark" => "bg-accent-100 text-accent-800",
        "light" => "bg-accent-50 text-accent-800"
      },
      "neutral" => %{
        "dark" => "bg-neutral-100 text-neutral-800",
        "light" => "bg-neutral-50 text-neutral-800"
      }
    }

    assigns = assign(assigns, colors: colors)

    ~H"""
    <span class="flex inline-flex">
      <div class={[
        "text-xs rounded-l py-0.5 pl-2.5 pr-1.5",
        @colors[@type]["dark"]
      ]}>
        <%= render_slot(@left) %>
      </div>
      <span class={[
        "text-xs",
        "rounded-r",
        "mr-2 py-0.5 pl-1.5 pr-2.5",
        @colors[@type]["light"]
      ]}>
        <%= render_slot(@right) %>
      </span>
    </span>
    """
  end

  @doc """
  Renders datetime field in a format that is suitable for the user's locale.
  """
  attr :datetime, DateTime, required: true
  attr :format, :atom, default: :short

  def datetime(assigns) do
    ~H"""
    <span title={@datetime}>
      <%= Cldr.DateTime.to_string!(@datetime, Web.CLDR, format: @format) %>
    </span>
    """
  end

  @doc """
  Returns a string the represents a relative time for a given Datetime
  from the current time or a given base time
  """
  attr :datetime, DateTime, default: nil
  attr :relative_to, DateTime, required: false

  def relative_datetime(assigns) do
    assigns = assign_new(assigns, :relative_to, fn -> DateTime.utc_now() end)

    ~H"""
    <.popover :if={not is_nil(@datetime)}>
      <:target>
        <span class="underline underline-offset-2 decoration-dashed">
          <%= Cldr.DateTime.Relative.to_string!(@datetime, Web.CLDR, relative_to: @relative_to)
          |> String.capitalize() %>
        </span>
      </:target>
      <:content>
        <%= @datetime %>
      </:content>
    </.popover>
    <span :if={is_nil(@datetime)}>
      Never
    </span>
    """
  end

  @doc """
  Renders a popover element with title and content.
  """
  slot :target, required: true
  slot :content, required: true

  def popover(assigns) do
    # Any id will do
    target_id = "popover-#{System.unique_integer([:positive, :monotonic])}"
    assigns = assign(assigns, :target_id, target_id)

    ~H"""
    <span data-popover-target={@target_id}>
      <%= render_slot(@target) %>
    </span>

    <div data-popover id={@target_id} role="tooltip" class={~w[
      absolute z-10 invisible inline-block
      text-sm text-neutral-500 transition-opacity
      duration-50 bg-white border border-neutral-200
      rounded shadow-sm opacity-0
      ]}>
      <div class="px-3 py-2">
        <%= render_slot(@content) %>
      </div>
      <div data-popper-arrow></div>
    </div>
    """
  end

  @doc """
  Renders online or offline status using an `online?` field of the schema.
  """
  attr :schema, :any, required: true

  def connection_status(assigns) do
    assigns = assign_new(assigns, :relative_to, fn -> DateTime.utc_now() end)

    ~H"""
    <span class="flex items-center">
      <.ping_icon color={if @schema.online?, do: "success", else: "danger"} />
      <span
        class="ml-2.5"
        title={
          if @schema.last_seen_at,
            do:
              "Last started #{Cldr.DateTime.Relative.to_string!(@schema.last_seen_at, Web.CLDR, relative_to: @relative_to)}",
            else: "Never connected"
        }
      >
        <%= if @schema.online?, do: "Online", else: "Offline" %>
      </span>
    </span>
    """
  end

  attr :navigate, :string, required: true
  attr :connected?, :boolean, required: true
  attr :type, :string, required: true

  def initial_connection_status(assigns) do
    ~H"""
    <.link
      class={[
        "px-4 py-2",
        "flex items-center",
        "text-sm text-white",
        "rounded",
        "transition-colors",
        (@connected? && "bg-accent-450 hover:bg-accent-700") || "bg-primary-500 cursor-progress"
      ]}
      navigate={@navigate}
      {
        if @connected? do
          %{}
        else
          %{"data-confirm" => "Do you want to skip waiting for #{@type} to be connected?"}
        end
      }
    >
      <span :if={not @connected?}>
        <.icon name="spinner" class="animate-spin h-3.5 w-3.5 mr-1" /> Waiting for connection...
      </span>

      <span :if={@connected?}>
        <.icon name="hero-check" class="h-3.5 w-3.5 mr-1" /> Connected, click to continue
      </span>
    </.link>
    """
  end

  @doc """
  Renders creation timestamp and entity.
  """
  attr :account, :any, required: true
  attr :schema, :any, required: true

  def created_by(%{schema: %{created_by: :system}} = assigns) do
    ~H"""
    <.relative_datetime datetime={@schema.inserted_at} /> by system
    """
  end

  def created_by(%{schema: %{created_by: :actor}} = assigns) do
    ~H"""
    <.relative_datetime datetime={@schema.inserted_at} /> by
    <.actor_link account={@account} actor={@schema.created_by_actor} />
    """
  end

  def created_by(%{schema: %{created_by: :identity}} = assigns) do
    ~H"""
    <.relative_datetime datetime={@schema.inserted_at} /> by
    <.link
      class="text-accent-500 hover:underline"
      navigate={~p"/#{@schema.account_id}/actors/#{@schema.created_by_identity.actor.id}"}
    >
      <%= assigns.schema.created_by_identity.actor.name %>
    </.link>
    """
  end

  def created_by(%{schema: %{created_by: :provider}} = assigns) do
    ~H"""
    <.relative_datetime datetime={@schema.inserted_at} /> by
    <.link
      class="text-accent-500 hover:underline"
      navigate={Web.Settings.IdentityProviders.Components.view_provider(@account, @schema.provider)}
    >
      <%= @schema.provider.name %>
    </.link> sync
    """
  end

  attr :account, :any, required: true
  attr :actor, :any, required: true

  def actor_link(%{actor: %Domain.Actors.Actor{type: :api_client}} = assigns) do
    ~H"""
    <.link class={link_style()} navigate={~p"/#{@account}/settings/api_clients/#{@actor}"}>
      <%= assigns.actor.name %>
    </.link>
    """
  end

  def actor_link(assigns) do
    ~H"""
    <.link class={link_style()} navigate={~p"/#{@account}/actors/#{@actor}"}>
      <%= assigns.actor.name %>
    </.link>
    """
  end

  attr :account, :any, required: true
  attr :identity, :any, required: true

  def identity_identifier(assigns) do
    ~H"""
    <span class="flex items-center" data-identity-id={@identity.id}>
      <.link
        navigate={
          Web.Settings.IdentityProviders.Components.view_provider(@account, @identity.provider)
        }
        data-provider-id={@identity.provider.id}
        title={"View identity provider \"#{@identity.provider.adapter}\""}
        class={~w[
          text-xs
          rounded-l
          py-0.5 px-1.5
          text-neutral-900
          bg-neutral-50
          border-neutral-100
          border
        ]}
      >
        <.provider_icon adapter={@identity.provider.adapter} class="h-3.5 w-3.5" />
      </.link>
      <span class={~w[
        text-xs
        min-w-0
        rounded-r
        mr-2 py-0.5 pl-1.5 pr-2.5
        text-neutral-900
        bg-neutral-100
      ]}>
        <span class="block truncate" title={get_identity_email(@identity)}>
          <%= get_identity_email(@identity) %>
        </span>
      </span>
    </span>
    """
  end

  def get_identity_email(identity) do
    provider_email(identity) || identity.provider_identifier
  end

  def identity_has_email?(identity) do
    not is_nil(provider_email(identity)) or identity.provider.adapter == :email or
      identity.provider_identifier =~ "@"
  end

  defp provider_email(identity) do
    get_in(identity.provider_state, ["userinfo", "email"])
  end

  attr :account, :any, required: true
  attr :group, :any, required: true

  def group(assigns) do
    ~H"""
    <span class="flex items-center" data-group-id={@group.id}>
      <.link
        :if={Actors.group_synced?(@group)}
        navigate={Web.Settings.IdentityProviders.Components.view_provider(@account, @group.provider)}
        data-provider-id={@group.provider_id}
        title={"View identity provider \"#{@group.provider.adapter}\""}
        class={~w[
          rounded-l
          py-0.5 px-1.5
          text-neutral-900
          bg-neutral-50
          border-neutral-100
          border
        ]}
      >
        <.provider_icon adapter={@group.provider.adapter} class="h-3.5 w-3.5" />
      </.link>
      <.link
        title={"View Group \"#{@group.name}\""}
        navigate={~p"/#{@account}/groups/#{@group}"}
        class={~w[
          text-xs
          truncate
          min-w-0
          #{if(Actors.group_synced?(@group), do: "rounded-r pl-1.5 pr-2.5", else: "rounded px-1.5")}
          py-0.5
          text-neutral-800
          bg-neutral-100
        ]}
      >
        <%= @group.name %>
      </.link>
    </span>
    """
  end

  @doc """

  """
  attr :schema, :any, required: true

  def last_seen(assigns) do
    ~H"""
    <code class="text-xs -mr-1">
      <%= @schema.last_seen_remote_ip %>
    </code>
    <span class="text-neutral-500 inline-block text-xs">
      <%= [
        @schema.last_seen_remote_ip_location_region,
        @schema.last_seen_remote_ip_location_city
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ") %>

      <a
        :if={
          not is_nil(@schema.last_seen_remote_ip_location_lat) and
            not is_nil(@schema.last_seen_remote_ip_location_lon)
        }
        class="text-accent-800"
        target="_blank"
        href={"http://www.google.com/maps/place/#{@schema.last_seen_remote_ip_location_lat},#{@schema.last_seen_remote_ip_location_lon}"}
      >
        <.icon name="hero-arrow-top-right-on-square" class="mb-3 w-3 h-3" />
      </a>
    </span>
    """
  end

  @doc """
  Helps to pluralize a word based on a cardinal number.

  Cardinal numbers indicate an amount—how many of something we have: one, two, three, four, five.

  Typically for English you want to set `one` and `other` options. The `other` option is used for all
  other numbers that are not `one`. For example, if you want to pluralize the word "file" you would
  set `one` to "file" and `other` to "files".
  """
  attr :number, :integer, required: true

  attr :zero, :string, required: false
  attr :one, :string, required: false
  attr :two, :string, required: false
  attr :few, :string, required: false
  attr :many, :string, required: false
  attr :other, :string, required: true

  attr :rest, :global

  def cardinal_number(assigns) do
    opts = Map.take(assigns, [:zero, :one, :two, :few, :many, :other])
    assigns = Map.put(assigns, :opts, opts)

    ~H"""
    <span data-value={@number} {@rest}>
      <%= Web.CLDR.Number.Cardinal.pluralize(@number, :en, @opts) %>
    </span>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(Web.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(Web.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  @doc """
  This component is meant to be used for step by step instructions

  ex.
  <.step>
    <:title>Step 1. Do Something</:title>
    <:content>
      Here are instructions for step 1...
    </:content>
  </.step>

  <.step>
    <:title>Step 2. Do Another Thing</:title>
    <:content>
      Here are instructions for step 2...
    </:content>
  </.step>

  """
  slot :title, required: true
  slot :content, required: true

  def step(assigns) do
    ~H"""
    <div class="mb-6">
      <h2 class="mb-2 text-2xl tracking-tight font-medium text-neutral-900">
        <%= render_slot(@title) %>
      </h2>
      <div class="px-4">
        <%= render_slot(@content) %>
      </div>
    </div>
    """
  end

  @doc """
  Render an animated status indicator dot.
  """

  attr :color, :string, default: "info"

  def ping_icon(assigns) do
    ~H"""
    <span class="relative flex h-2.5 w-2.5">
      <span class={~w[
        animate-ping absolute inline-flex
        h-full w-full rounded-full opacity-50
        #{ping_icon_color(@color) |> elem(1)}]}></span>
      <span class={~w[
        relative inline-flex rounded-full h-2.5 w-2.5
        #{ping_icon_color(@color) |> elem(0)}]}></span>
    </span>
    """
  end

  defp ping_icon_color(color) do
    case color do
      "info" -> {"bg-accent-500", "bg-accent-400"}
      "success" -> {"bg-green-500", "bg-green-400"}
      "warning" -> {"bg-orange-500", "bg-orange-400"}
      "danger" -> {"bg-red-500", "bg-red-400"}
    end
  end

  @doc """
  Renders a logo appropriate for the given provider.

  <.provider_icon adapter={:google_workspace} class="w-5 h-5 mr-2" />
  """
  attr :adapter, :atom, required: false
  attr :rest, :global

  def provider_icon(%{adapter: :google_workspace} = assigns) do
    ~H"""
    <img src={~p"/images/google-logo.svg"} alt="Google Workspace Logo" {@rest} />
    """
  end

  def provider_icon(%{adapter: :openid_connect} = assigns) do
    ~H"""
    <img src={~p"/images/openid-logo.svg"} alt="OpenID Connect Logo" {@rest} />
    """
  end

  def provider_icon(%{adapter: :microsoft_entra} = assigns) do
    ~H"""
    <img src={~p"/images/entra-logo.svg"} alt="Microsoft Entra Logo" {@rest} />
    """
  end

  def provider_icon(%{adapter: :okta} = assigns) do
    ~H"""
    <img src={~p"/images/okta-logo.svg"} alt="Okta Logo" {@rest} />
    """
  end

  def provider_icon(%{adapter: :jumpcloud} = assigns) do
    ~H"""
    <img src={~p"/images/jumpcloud-logo.svg"} alt="JumpCloud Logo" {@rest} />
    """
  end

  def provider_icon(%{adapter: :email} = assigns) do
    ~H"""
    <.icon name="hero-envelope" {@rest} />
    """
  end

  def provider_icon(%{adapter: :userpass} = assigns) do
    ~H"""
    <.icon name="hero-key" {@rest} />
    """
  end

  def provider_icon(assigns), do: ~H""

  def feature_name(%{feature: :idp_sync} = assigns) do
    ~H"""
    Automatically sync users and groups
    """
  end

  def feature_name(%{feature: :flow_activities} = assigns) do
    ~H"""
    See detailed Resource access logs
    """
  end

  def feature_name(%{feature: :policy_conditions} = assigns) do
    ~H"""
    Specify access-time conditions when creating policies
    """
  end

  def feature_name(%{feature: :multi_site_resources} = assigns) do
    ~H"""
    Define globally-distributed Resources
    """
  end

  def feature_name(%{feature: :traffic_filters} = assigns) do
    ~H"""
    Restrict access based on port and protocol rules
    """
  end

  def feature_name(%{feature: :self_hosted_relays} = assigns) do
    ~H"""
    Host your own Relays
    """
  end

  def feature_name(%{feature: :rest_api} = assigns) do
    ~H"""
    REST API
    """
  end

  def feature_name(assigns) do
    ~H""
  end

  def mailto_support(account, subject, email_subject) do
    body =
      """


      ---
      Please do not remove this part of the email.
      Account Name: #{account.name}
      Account Slug: #{account.slug}
      Account ID: #{account.id}
      Actor ID: #{subject.actor.id}
      """

    "mailto:support@firezone.dev?subject=#{URI.encode_www_form(email_subject)}&body=#{URI.encode_www_form(body)}"
  end

  def link_style do
    [
      "text-accent-500",
      "hover:underline"
    ]
  end
end
