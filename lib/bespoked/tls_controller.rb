#

module Bespoked
  class TlsController
    attr_accessor :run_loop,
                  :rack_server,
                  :proxy_controller,
                  :challenges

    def initialize(run_loop_in, logger_in, proxy_controller_in)
      #, challenge, authorization)
      self.challenges = {}
      @logger = logger_in
      self.run_loop = run_loop_in
      self.proxy_controller = proxy_controller_in
      self.rack_server = LibUVRackServer.new(@run_loop, logger_in, method(:handle_request), {:Port => 55101})

      # We're going to need a private key.
      private_key = OpenSSL::PKey::RSA.new(4096)

      # We need an ACME server to talk to, see github.com/letsencrypt/boulder
      # WARNING: This endpoint is the production endpoint, which is rate limited and will produce valid certificates.
      # You should probably use the staging endpoint for all your experimentation:
      endpoint = 'https://acme-staging.api.letsencrypt.org/'
      #endpoint = 'https://acme-v01.api.letsencrypt.org/'

      # Initialize the client
      client = Acme::Client.new(private_key: private_key, endpoint: endpoint, connection_options: { request: { open_timeout: 5, timeout: 5 } })
      @client = client

      # If the private key is not known to the server, we need to register it for the first time.
      registration = client.register(contact: 'mailto:diclophis@gmail.com')
      @logger.puts registration

      # You may need to agree to the terms of service (that's up the to the server to require it or not but boulder does by default)
      @logger.puts registration.agree_terms
    end

    def install_tls_registration(dns)
      authorization = @client.authorize(domain: dns)

      # If authorization.status returns 'valid' here you can already get a certificate
      # and _must not_ try to solve another challenge.
      do_not_solve_dns_challenge = authorization.status == 'valid' # or => 'pending'

      unless do_not_solve_dns_challenge
        # You can can store the authorization's URI to fully recover it and
        # any associated challenges via Acme::Client#fetch_authorization.
        @logger.puts authorization.uri # => '...'

        # This example is using the http-01 challenge type. Other challenges are dns-01 or tls-sni-01.
        challenge = authorization.http01
        challenge_key = File.join("/", challenge.filename)
        @challenges[challenge_key] = challenge

        #@challenge = challenge

        # The challenge file can be served with a Ruby webserver.
        # You can run a webserver in another console for that purpose. You may need to forward ports on your router.
        #
        # $ ruby -run -e httpd public -p 8080 --bind-address 0.0.0.0

        # Load a challenge based on stored authorization URI. This is only required if you need to reuse a challenge as outlined above.
        # challenge = client.fetch_authorization(File.read('authorization_uri')).http01

        # Once you are ready to serve the confirmation request you can proceed.
        
        puts challenge.request_verification # => true

        timer = @run_loop.timer
        timer.progress do
          @logger.puts challenge.authorization.verify_status # => 'pending'
          if challenge.authorization.verify_status == 'valid'
            csr = Acme::Client::CertificateRequest.new(names: dns)

            # We can now request a certificate. You can pass anything that returns
            # a valid DER encoded CSR when calling to_der on it. For example an
            # OpenSSL::X509::Request should work too.
            certificate = @client.new_certificate(csr) # => #<Acme::Client::Certificate ....>

            # Save the certificate and the private key to files
            @proxy_controller.add_tls_host(certificate.request.private_key.to_pem, certificate.fullchain_to_pem, dns)

            #certificate.request.private_key.to_pem)
            #File.write("cert.pem", certificate.to_pem)
            #File.write("chain.pem", certificate.chain_to_pem)
            #File.write("fullchain.pem", certificate.fullchain_to_pem)
            timer.stop
          end
        end
        timer.start(1000, 1000)
      end
    end

    def shutdown
      @rack_server.shutdown
    end

    def start
      #self.install_tls_registration("bardin.haus")
      #self.install_tls_registration("attalos.bardin.haus")
      @rack_server.start
    end

    def handle_request(env)
  #while true
    puts "."
    @logger.puts "WTFFFFFF"

    if challenge = @challenges[env["PATH_INFO"]]
      @logger.puts challenge.authorization.verify_status # => 'pending'
      @logger.puts env.inspect
      ['200', {'Content-Type' => challenge.content_type}, [challenge.file_content]]
    else
      ['200', {'Content-Type' => "text/plain"}, ["OK"]]
    end

	  # Wait a bit for the server to make the request, or just blink. It should be fast.
	#  sleep(1)

    # Rely on authorization.verify_status more than on challenge.verify_status,
    # if the former is 'valid' you can already issue a certificate and the status of
    # the challenge is not relevant and in fact may never change from pending.
    #challenge.authorization.verify_status # => 'valid'
  #  @logger.puts challenge.error # => nil

    # If authorization.verify_status is 'invalid', you can get at the error
    # message only through the failed challenge.
 #   if authorization.verify_status == 'invalid' # => 'invalid'
 #     @logger.puts authorization.http01.error # => {"type" => "...", "detail" => "..."}
 #   end
 # end

	# The http-01 method will require you to respond to a HTTP request.

	# You can retrieve the challenge token
	#challenge_token = challenge.token # => "some_token"

	# You can retrieve the expected path for the file.
	#challenge_path = challenge.filename # => ".well-known/acme-challenge/:some_token"

	# You can generate the body of the expected response.
	#challenge_response = challenge.file_content # => 'string token and JWK thumbprint'

	# You are not required to send a Content-Type. This method will return the right Content-Type should you decide to include one.
	#challenge_response_type = challenge.content_type

	# Save the file. We'll create a public directory to serve it from, and inside it we'll create the challenge file.
	#FileUtils.mkdir_p( File.join( 'public', File.dirname( challenge.filename ) ) )

	# We'll write the content of the file
	#File.write( File.join( 'public', challenge.filename), challenge.file_content )

	## Optionally save the authorization URI for use at another time (eg: by a background job processor)
	#File.write('authorization_uri', authorization.uri)

    end
  end
end
