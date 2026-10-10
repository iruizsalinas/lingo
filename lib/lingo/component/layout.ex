defmodule Lingo.Component.Layout do
  @moduledoc """
  Builders for components v2: text, images, files and containers laid out
  in the message itself. Messages using them need the `Lingo.Component.v2_flag/0`
  flag and can't have `:content` or `:embeds`.

      Lingo.Api.Message.create(channel_id, %{
        flags: Lingo.Component.v2_flag(),
        components: [
          Layout.container([Layout.text_display("**Server status**"), Layout.separator()],
            accent_color: 0x57F287
          )
        ]
      })
  """

  import Lingo.Component, only: [put: 3]

  @spacings %{small: 1, large: 2}

  @doc "Up to 3 text displays with an accessory (a button or a thumbnail) beside them."
  @spec section([map()], map()) :: map()
  def section(text_displays, accessory),
    do: %{type: 9, components: text_displays, accessory: accessory}

  @doc "Markdown text."
  @spec text_display(String.t()) :: map()
  def text_display(content), do: %{type: 10, content: content}

  @doc "A small image, for a section's accessory. Options: `:description` and `:spoiler`."
  @spec thumbnail(String.t(), keyword()) :: map()
  def thumbnail(url, opts \\ []),
    do: %{type: 11, media: %{url: url}} |> put(opts, [:description, :spoiler])

  @doc "A grid of up to 10 images or videos, built with `gallery_item/2`."
  @spec media_gallery([map()]) :: map()
  def media_gallery(items), do: %{type: 12, items: items}

  @doc "One item of a `media_gallery/1`. Options: `:description` and `:spoiler`."
  @spec gallery_item(String.t(), keyword()) :: map()
  def gallery_item(url, opts \\ []),
    do: %{media: %{url: url}} |> put(opts, [:description, :spoiler])

  @doc "An attached file, by `attachment://name` URL. Option: `:spoiler`."
  @spec file(String.t(), keyword()) :: map()
  def file(url, opts \\ []), do: %{type: 13, file: %{url: url}} |> put(opts, [:spoiler])

  @doc "Space between components. Options: `:divider` (draw a line) and `:spacing` (`:small` or `:large`)."
  @spec separator(keyword()) :: map()
  def separator(opts \\ []) do
    spacing = Map.get(@spacings, opts[:spacing], opts[:spacing])
    put(%{type: 14}, [divider: opts[:divider], spacing: spacing], [:divider, :spacing])
  end

  @doc "A box around components, like an embed. Options: `:accent_color` and `:spoiler`."
  @spec container([map()], keyword()) :: map()
  def container(components, opts \\ []),
    do: %{type: 17, components: components} |> put(opts, [:accent_color, :spoiler])

  @doc "A media reference by URL."
  @spec unfurled_media(String.t()) :: map()
  def unfurled_media(url), do: %{url: url}
end
