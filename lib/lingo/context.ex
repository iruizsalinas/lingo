defmodule Lingo.Context do
  @moduledoc """
  An interaction your bot is handling: a slash or context menu command, a
  component click, a modal submission or an autocomplete request.

  Every interaction callback in `Lingo.Bot` receives one, and this module's
  functions are imported into modules that `use Lingo.Bot`.

  ## Responding

  Discord expects an answer within 3 seconds: `reply/2`, `update/2`,
  `show_modal/2` or `autocomplete_result/2`, or `defer/2` first to answer
  within 15 minutes. Each returns `{:ok, ctx}`, remembering that the
  interaction was answered so the next `reply/2` sends a follow-up. The `!`
  versions return the context or raise `Lingo.Error`.

      def handle_command("slow", ctx) do
        ctx = defer!(ctx)
        reply!(ctx, "Done: \#{do_slow_work()}")
      end

  A context remembers which bot it belongs to, so it can be answered from
  any process.

  ## Reading input

  Options you declared with `Lingo.Bot.Commands.command/3` have atom keys and
  subcommands nest; modal fields are keyed by their custom id, as strings.
  `option/2` and `modal_value/2` accept either form.
  """

  alias Lingo.Context.{Input, Parse, Resolved, Response}
  alias Lingo.Type.{Interaction, Member, Message, User}

  @type t :: %__MODULE__{
          bot: atom() | nil,
          type: Interaction.interaction_type(),
          interaction_id: String.t(),
          interaction_token: String.t(),
          application_id: String.t(),
          guild_id: String.t() | nil,
          channel_id: String.t() | nil,
          user_id: String.t() | nil,
          member: Member.t() | nil,
          user: User.t() | nil,
          locale: String.t() | nil,
          guild_locale: String.t() | nil,
          app_permissions: String.t() | nil,
          command_name: String.t() | nil,
          options: %{optional(atom() | String.t()) => term()},
          raw_options: [map()] | nil,
          resolved: map() | nil,
          target_id: String.t() | nil,
          custom_id: String.t() | nil,
          component_type: atom() | integer() | nil,
          values: [String.t()],
          message: Message.t() | nil,
          interaction: Interaction.t() | nil,
          replied: boolean(),
          deferred: boolean()
        }

  @typedoc "Message content: a string, or a keyword list or map of message fields."
  @type content :: String.t() | keyword() | map()

  defstruct [
    :bot,
    :type,
    :interaction_id,
    :interaction_token,
    :application_id,
    :guild_id,
    :channel_id,
    :user_id,
    :member,
    :user,
    :locale,
    :guild_locale,
    :app_permissions,
    :command_name,
    :resolved,
    :raw_options,
    :target_id,
    :custom_id,
    :component_type,
    :message,
    :interaction,
    options: %{},
    values: [],
    replied: false,
    deferred: false
  ]

  @doc false
  def new(%Interaction{} = interaction, bot \\ nil), do: Parse.context(interaction, bot)

  ## Responding

  @doc """
  Sends a message: the response, or a follow-up once answered. `content` is
  a string, or message fields such as `:content`, `:embeds`, `:components`,
  `:files` and `:flags`.
  """
  defdelegate reply(ctx, content), to: Response
  @doc "Sends a response only the user who triggered the interaction can see."
  defdelegate ephemeral(ctx, content), to: Response

  @doc "Edits the message a component is on, as the response to clicking it or after `defer(ctx, update: true)`."
  defdelegate update(ctx, content), to: Response

  @doc """
  Acknowledges the interaction now and answers later. Does nothing if
  already deferred. Options: `:ephemeral` (only the user sees the answer) and
  `:update` (for components: the answer edits their message).
  """
  defdelegate defer(ctx, opts \\ []), to: Response
  @doc "Opens a modal built with `Lingo.Component.Modal.modal/3`. Must be the first response."
  defdelegate show_modal(ctx, modal), to: Response

  @doc "Answers autocomplete with up to 25 choices, maps or keyword lists with `:name` and `:value`."
  defdelegate autocomplete_result(ctx, choices), to: Response

  @doc "Like `reply/2`, but returns the context or raises `Lingo.Error`."
  defdelegate reply!(ctx, content), to: Response
  @doc "Like `ephemeral/2`, but returns the context or raises `Lingo.Error`."
  defdelegate ephemeral!(ctx, content), to: Response
  @doc "Like `update/2`, but returns the context or raises `Lingo.Error`."
  defdelegate update!(ctx, content), to: Response
  @doc "Like `defer/2`, but returns the context or raises `Lingo.Error`."
  defdelegate defer!(ctx, opts \\ []), to: Response
  @doc "Like `show_modal/2`, but returns the context or raises `Lingo.Error`."
  defdelegate show_modal!(ctx, modal), to: Response
  @doc "Like `autocomplete_result/2`, but returns the context or raises `Lingo.Error`."
  defdelegate autocomplete_result!(ctx, choices), to: Response

  ## Reading input

  @doc """
  The value of a command option or modal field, or `nil`. For `user`, `role`,
  `channel`, `mentionable` and `attachment` options this is the id;
  `get_user/2` and friends give you the struct.
  """
  defdelegate option(ctx, name), to: Input
  @doc "The value of a modal field, by its custom id. Same as `option/2`."
  defdelegate modal_value(ctx, field_id), to: Input
  @doc "The option the user is typing in, during autocomplete, as `{name, value}`."
  defdelegate focused_option(ctx), to: Input

  @doc "The user an option points at."
  defdelegate get_user(ctx, name), to: Input
  @doc "The guild member an option points at."
  defdelegate get_member(ctx, name), to: Input
  @doc "The role an option points at."
  defdelegate get_role(ctx, name), to: Input
  @doc "The channel an option points at."
  defdelegate get_channel(ctx, name), to: Input
  @doc "The attachment an option points at."
  defdelegate get_attachment(ctx, name), to: Input

  ## Resolved data: what Discord sent along with the interaction, by id

  @doc "A user Discord sent along with the interaction."
  defdelegate resolved_user(ctx, user_id), to: Resolved
  @doc "A guild member Discord sent along with the interaction, by user id."
  defdelegate resolved_member(ctx, user_id), to: Resolved
  @doc "A role Discord sent along with the interaction."
  defdelegate resolved_role(ctx, role_id), to: Resolved
  @doc "A channel Discord sent along with the interaction."
  defdelegate resolved_channel(ctx, channel_id), to: Resolved

  @doc "A message Discord sent along with the interaction; for message commands, `ctx.target_id` is the target."
  defdelegate resolved_message(ctx, message_id), to: Resolved
  @doc "An attachment Discord sent along with the interaction."
  defdelegate resolved_attachment(ctx, attachment_id), to: Resolved
end
