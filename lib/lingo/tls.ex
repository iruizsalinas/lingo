defmodule Lingo.TLS do
  @moduledoc false

  # Client TLS options that actually verify the peer: OTP's CA store,
  # plus hostname checks that accept wildcard certificates.

  @spec client_options() :: [:ssl.tls_client_option()]
  def client_options do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end
end
