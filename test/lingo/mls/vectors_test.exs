defmodule Lingo.MLS.VectorsTest do
  use ExUnit.Case, async: true

  import Lingo.Test.MLSVectors

  alias Lingo.MLS.{
    Codec,
    Commit,
    Crypto,
    Framing,
    Group,
    HPKE,
    KeySchedule,
    Message,
    Tree,
    Welcome
  }

  # a member's view of a vector tree: its leaf key plus the path secrets it holds
  defp private_group(vector, tree, leaf) do
    leaf_x = 2 * leaf["index"]

    path_keys =
      Map.new(leaf["path_secrets"], fn %{"node" => x, "path_secret" => path_secret} ->
        {x, HPKE.derive_key_pair(Crypto.derive_secret(hex(path_secret), "node"))}
      end)

    %Group{
      group_id: hex(vector["group_id"]),
      epoch: vector["epoch"] - 1,
      tree: tree,
      leaf_index: leaf["index"],
      signature_private_key: hex(leaf["signature_priv"]),
      secrets: %{},
      confirmed_transcript_hash: hex(vector["confirmed_transcript_hash"]),
      private_keys:
        Map.put(
          path_keys,
          leaf_x,
          {Tree.get(tree, leaf_x).encryption_key, hex(leaf["encryption_priv"])}
        )
    }
  end

  defp join(vector) do
    {:ok, {:key_package, key_package}} =
      Message.decode(hex(vector["key_package"]), &Message.decode_mls_message/1)

    {:ok, {:welcome, _}} = Message.decode(hex(vector["welcome"]), &Message.decode_mls_message/1)
    <<1::16, 3::16, welcome::binary>> = hex(vector["welcome"])

    Group.join(
      welcome,
      key_package,
      hex(vector["init_priv"]),
      hex(vector["encryption_priv"]),
      hex(vector["signature_priv"]),
      hex(vector["ratchet_tree"])
    )
  end

  describe "IETF vectors" do
    test "key schedule" do
      [vector] = load("key-schedule")
      group_id = hex(vector["group_id"])

      Enum.reduce(
        Enum.with_index(vector["epochs"]),
        hex(vector["initial_init_secret"]),
        fn {epoch, n}, init_secret ->
          context =
            Welcome.encode_group_context(%{
              cipher_suite: 2,
              group_id: group_id,
              epoch: n,
              tree_hash: hex(epoch["tree_hash"]),
              confirmed_transcript_hash: hex(epoch["confirmed_transcript_hash"]),
              extensions: []
            })
            |> IO.iodata_to_binary()

          assert context == hex(epoch["group_context"])

          secrets =
            KeySchedule.advance(
              init_secret,
              hex(epoch["commit_secret"]),
              context,
              hex(epoch["psk_secret"])
            )

          for key <-
                ~w(joiner_secret welcome_secret init_secret sender_data_secret encryption_secret
                      exporter_secret epoch_authenticator external_secret confirmation_key
                      membership_key resumption_psk) do
            assert Map.fetch!(secrets, String.to_atom(key)) == hex(epoch[key]),
                   "#{key} in epoch #{n}"
          end

          assert elem(HPKE.derive_key_pair(secrets.external_secret), 0) ==
                   hex(epoch["external_pub"])

          %{
            "label" => label,
            "context" => exporter_context,
            "length" => length,
            "secret" => secret
          } = epoch["exporter"]

          # the vectors use the hex string itself as the label
          assert KeySchedule.export(secrets.exporter_secret, label, hex(exporter_context), length) ==
                   hex(secret)

          secrets.init_secret
        end
      )
    end

    test "transcript hashes" do
      [vector] = load("transcript-hashes")

      <<1::16, rest::binary>> = hex(vector["authenticated_content"])
      {content, rest} = Framing.decode_framed_content(rest)
      {signature, rest} = Codec.decode_vector(rest)
      {confirmation_tag, <<>>} = Codec.decode_vector(rest)

      message = %{content: content, signature: signature}

      confirmed =
        Crypto.hash([
          hex(vector["interim_transcript_hash_before"]),
          Framing.confirmed_transcript_input(message)
        ])

      assert confirmed == hex(vector["confirmed_transcript_hash_after"])
      assert Crypto.mac(hex(vector["confirmation_key"]), confirmed) == confirmation_tag

      assert Crypto.hash([confirmed, Codec.vector(confirmation_tag)]) ==
               hex(vector["interim_transcript_hash_after"])
    end

    test "passive client joining from a Welcome" do
      cases = Enum.filter(load("passive-client-welcome"), &(&1["external_psks"] == []))
      assert length(cases) == 4

      for vector <- cases do
        assert {:ok, group} = join(vector)
        assert Group.epoch_authenticator(group) == hex(vector["initial_epoch_authenticator"])
      end
    end

    # the passive-client commit vectors all join through a Welcome carrying a
    # pre-shared key, which DAVE never uses; these cover the same ground
    test "treekem: merging and decrypting UpdatePaths from other implementations" do
      for vector <- load("treekem") do
        tree = Codec.decode_exact(hex(vector["ratchet_tree"]), &Tree.decode/1)

        for update <- vector["update_paths"],
            leaf <- vector["leaves_private"],
            leaf["index"] != update["sender"] do
          group = private_group(vector, tree, leaf)
          path = Codec.decode_exact(hex(update["update_path"]), &Commit.decode_update_path/1)

          assert {:ok, new_tree, commit_secret, keys} =
                   Group.merge_update_path(group, tree, path, update["sender"], [])

          assert Tree.tree_hash(new_tree) == hex(update["tree_hash_after"])
          assert commit_secret == hex(update["commit_secret"])
          assert map_size(keys) > 0
        end
      end
    end
  end
end
