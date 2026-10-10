defmodule Lingo.MLS.Group.Auth do
  @moduledoc false

  # Decoding PublicMessages and checking their signatures and membership tags.

  alias Lingo.MLS.{Crypto, Framing, Message, Tree}

  alias Lingo.MLS.Group
  alias Lingo.MLS.Group.Util

  def decode_public_message(mls_message) do
    case Message.decode(mls_message, &Message.decode_mls_message/1) do
      {:ok, {:public_message, message}} -> {:ok, message}
      {:ok, _other} -> {:error, :not_a_public_message}
      error -> error
    end
  end

  def fetch_content(%{content: %{content: {type, value}}}, type), do: {:ok, value}
  def fetch_content(_message, _type), do: {:error, :unexpected_content}

  def verify_message(group, message) do
    context = Util.encode_context(Group.context(group))

    with :ok <- Util.check(message.content.group_id == group.group_id, :wrong_group),
         {:ok, signature_key} <- signer_key(group, message.content.sender),
         tbs = Framing.framed_content_tbs(message.content, context),
         :ok <-
           Util.check(
             Crypto.verify_with_label(signature_key, "FramedContentTBS", tbs, message.signature),
             :invalid_signature
           ) do
      verify_membership_tag(group, message, context)
    end
  end

  def signer_key(group, {:member, leaf_index}) do
    case Tree.leaf(group.tree, leaf_index) do
      nil -> {:error, :unknown_sender}
      leaf -> {:ok, leaf.signature_key}
    end
  end

  def signer_key(group, {:external, index}) do
    case Enum.at(Group.external_senders(group), index) do
      nil -> {:error, :unknown_sender}
      sender -> {:ok, sender.signature_key}
    end
  end

  def signer_key(_group, _sender), do: {:error, :unsupported_sender}

  def verify_membership_tag(group, %{content: %{sender: {:member, _}}} = message, context) do
    expected =
      Crypto.mac(group.secrets.membership_key, Framing.membership_tag_input(message, context))

    Util.check(Util.equal?(expected, message.membership_tag), :invalid_membership_tag)
  end

  def verify_membership_tag(_group, _message, _context), do: :ok
end
