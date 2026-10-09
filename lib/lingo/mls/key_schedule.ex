defmodule Lingo.MLS.KeySchedule do
  @moduledoc false

  # The per-epoch key schedule (RFC 9420, section 8). Pre-shared keys are not
  # supported, so psk_secret is always the all-zero string.

  alias Lingo.MLS.Crypto

  @epoch_labels [
    sender_data_secret: "sender data",
    encryption_secret: "encryption",
    exporter_secret: "exporter",
    external_secret: "external",
    confirmation_key: "confirm",
    membership_key: "membership",
    resumption_psk: "resumption",
    epoch_authenticator: "authentication",
    init_secret: "init"
  ]

  @spec zero() :: binary()
  def zero, do: :binary.copy(<<0>>, Crypto.hash_size())

  @doc "Advances from the previous epoch's init secret, as a commit does."
  @spec advance(binary(), binary(), iodata(), binary()) :: map()
  def advance(init_secret, commit_secret, group_context, psk_secret \\ zero()) do
    joiner_secret =
      Crypto.expand_with_label(
        Crypto.extract(init_secret, commit_secret),
        "joiner",
        group_context,
        Crypto.hash_size()
      )

    join(joiner_secret, group_context, psk_secret)
  end

  @doc "Starts from a joiner secret, as a Welcome does."
  @spec join(binary(), iodata(), binary()) :: map()
  def join(joiner_secret, group_context, psk_secret \\ zero()) do
    member_secret = Crypto.extract(joiner_secret, psk_secret)

    epoch_secret =
      Crypto.expand_with_label(member_secret, "epoch", group_context, Crypto.hash_size())

    epoch_secret
    |> from_epoch_secret()
    |> Map.merge(%{
      joiner_secret: joiner_secret,
      welcome_secret: welcome_secret(joiner_secret, psk_secret)
    })
  end

  @spec welcome_secret(binary(), binary()) :: binary()
  def welcome_secret(joiner_secret, psk_secret \\ zero()),
    do: Crypto.derive_secret(Crypto.extract(joiner_secret, psk_secret), "welcome")

  @doc "Derives every epoch secret from the epoch secret itself, as group creation does."
  @spec from_epoch_secret(binary()) :: map()
  def from_epoch_secret(epoch_secret) do
    Map.new(@epoch_labels, fn {name, label} ->
      {name, Crypto.derive_secret(epoch_secret, label)}
    end)
  end

  @spec welcome_key_and_nonce(binary()) :: {binary(), binary()}
  def welcome_key_and_nonce(welcome_secret) do
    {Crypto.expand_with_label(welcome_secret, "key", "", Crypto.key_size()),
     Crypto.expand_with_label(welcome_secret, "nonce", "", Crypto.nonce_size())}
  end

  @doc "MLS-Exporter (RFC 9420, section 8.5)."
  @spec export(binary(), String.t(), binary(), pos_integer()) :: binary()
  def export(exporter_secret, label, context, length) do
    exporter_secret
    |> Crypto.derive_secret(label)
    |> Crypto.expand_with_label("exported", Crypto.hash(context), length)
  end
end
