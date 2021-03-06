require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

describe HTTParty::Request do
  before do
    @request = HTTParty::Request.new(Net::HTTP::Get, 'http://api.foo.com/v1', :format => :xml)
  end

  describe "::NON_RAILS_QUERY_STRING_NORMALIZER" do
    let(:normalizer) { HTTParty::Request::NON_RAILS_QUERY_STRING_NORMALIZER }

    it "doesn't modify strings" do
      query_string = normalizer["foo=bar&foo=baz"]
      URI.unescape(query_string).should == "foo=bar&foo=baz"
    end

    context "when the query is an array" do

      it "doesn't include brackets" do
        query_string = normalizer[{:page => 1, :foo => %w(bar baz)}]
        URI.unescape(query_string).should == "foo=bar&foo=baz&page=1"
      end

      it "URI encodes array values" do
        query_string = normalizer[{:people => ["Bob Marley", "Tim & Jon"]}]
        query_string.should == "people=Bob%20Marley&people=Tim%20%26%20Jon"
      end
    end

    context "when the query is a hash" do
      it "correctly handles nil values" do
        query_string = normalizer[{:page => 1, :per_page => nil}]
        query_string.should == "page=1&per_page"
      end
    end
  end

  describe "initialization" do
    it "sets parser to HTTParty::Parser" do
      request = HTTParty::Request.new(Net::HTTP::Get, 'http://google.com')
      request.parser.should == HTTParty::Parser
    end

    it "sets parser to the optional parser" do
      my_parser = lambda {}
      request = HTTParty::Request.new(Net::HTTP::Get, 'http://google.com', :parser => my_parser)
      request.parser.should == my_parser
    end
  end

  describe "#format" do
    context "request yet to be made" do
      it "returns format option" do
        request = HTTParty::Request.new 'get', '/', :format => :xml
        request.format.should == :xml
      end

      it "returns nil format" do
        request = HTTParty::Request.new 'get', '/'
        request.format.should be_nil
      end
    end

    context "request has been made" do
      it "returns format option" do
        request = HTTParty::Request.new 'get', '/', :format => :xml
        request.last_response = stub
        request.format.should == :xml
      end

      it "returns the content-type from the last response when the option is not set" do
        request = HTTParty::Request.new 'get', '/'
        response = stub
        response.should_receive(:[]).with('content-type').and_return('text/json')
        request.last_response = response
        request.format.should == :json
      end
    end

  end

  context "options" do
    it "should use basic auth when configured" do
      @request.options[:basic_auth] = {:username => 'foobar', :password => 'secret'}
      @request.send(:setup_raw_request)
      @request.instance_variable_get(:@raw_request)['authorization'].should_not be_nil
    end

    it "should use digest auth when configured" do
      FakeWeb.register_uri(:head, "http://api.foo.com/v1",
        :www_authenticate => 'Digest realm="Log Viewer", qop="auth", nonce="2CA0EC6B0E126C4800E56BA0C0003D3C", opaque="5ccc069c403ebaf9f0171e9517f40e41", stale=false')

      @request.options[:digest_auth] = {:username => 'foobar', :password => 'secret'}
      @request.send(:setup_raw_request)

      raw_request = @request.instance_variable_get(:@raw_request)
      raw_request.instance_variable_get(:@header)['Authorization'].should_not be_nil
    end
  end

  describe "#uri" do
    context "query strings" do
      it "does not add an empty query string when default_params are blank" do
        @request.options[:default_params] = {}
        @request.uri.query.should be_nil
      end

      it "respects the query string normalization proc" do
        empty_proc = lambda {|qs| ""}
        @request.options[:query_string_normalizer] = empty_proc
        @request.options[:query] = {:foo => :bar}
        URI.unescape(@request.uri.query).should == ""
      end

      context "when representing an array" do
        it "returns a Rails style query string" do
          @request.options[:query] = {:foo => %w(bar baz)}
          URI.unescape(@request.uri.query).should == "foo[]=bar&foo[]=baz"
        end
      end

    end
  end

  describe "#setup_raw_request" do
    context "when query_string_normalizer is set" do
      it "sets the body to the return value of the proc" do
        @request.options[:query_string_normalizer] = HTTParty::Request::NON_RAILS_QUERY_STRING_NORMALIZER
        @request.options[:body] = {:page => 1, :foo => %w(bar baz)}
        @request.send(:setup_raw_request)
        body = @request.instance_variable_get(:@raw_request).body
        URI.unescape(body).should == "foo=bar&foo=baz&page=1"
      end
    end
  end

  describe 'http' do
    it "should use ssl for port 443" do
      request = HTTParty::Request.new(Net::HTTP::Get, 'https://api.foo.com/v1:443')
      request.send(:http).use_ssl?.should == true
    end

    it 'should not use ssl for port 80' do
      request = HTTParty::Request.new(Net::HTTP::Get, 'http://foobar.com')
      request.send(:http).use_ssl?.should == false
    end

    it "uses ssl for https scheme with default port" do
      request = HTTParty::Request.new(Net::HTTP::Get, 'https://foobar.com')
      request.send(:http).use_ssl?.should == true
    end

    it "uses ssl for https scheme regardless of port" do
      request = HTTParty::Request.new(Net::HTTP::Get, 'https://foobar.com:123456')
      request.send(:http).use_ssl?.should == true
    end

    context "PEM certificates" do
      before do
        OpenSSL::X509::Certificate.stub(:new)
        OpenSSL::PKey::RSA.stub(:new)
      end

      context "when scheme is https" do
        before do
          @request.stub!(:uri).and_return(URI.parse("https://google.com"))
          pem = :pem_contents
          @cert = mock("OpenSSL::X509::Certificate")
          @key =  mock("OpenSSL::PKey::RSA")
          OpenSSL::X509::Certificate.should_receive(:new).with(pem).and_return(@cert)
          OpenSSL::PKey::RSA.should_receive(:new).with(pem, "password").and_return(@key)

          @request.options[:pem] = pem
          @request.options[:pem_password] = "password"
          @pem_http = @request.send(:http)
        end

        it "should use a PEM certificate when provided" do
          @pem_http.cert.should == @cert
          @pem_http.key.should == @key
        end

        it "should verify the certificate when provided" do
          @pem_http = @request.send(:http)
          @pem_http.verify_mode.should == OpenSSL::SSL::VERIFY_PEER
        end
      end

      context "when scheme is not https" do
        it "does not assign a PEM" do
          http = Net::HTTP.new('google.com')
          http.should_not_receive(:cert=)
          http.should_not_receive(:key=)
          Net::HTTP.stub(:new => http)

          request = HTTParty::Request.new(Net::HTTP::Get, 'http://google.com')
          request.options[:pem] = :pem_contents
          request.send(:http)
        end
      end

      context "debugging" do
        before do
          @http = Net::HTTP.new('google.com')
          Net::HTTP.stub(:new => @http)
          @request = HTTParty::Request.new(Net::HTTP::Get, 'http://google.com')
        end

        it "calls #set_debug_output when the option is provided" do
          @request.options[:debug_output] = $stderr
          @http.should_receive(:set_debug_output).with($stderr)
          @request.send(:http)
        end

        it "does not set_debug_output when the option is not provided" do
          @http.should_not_receive(:set_debug_output)
          @request.send(:http)
        end
      end

      context 'with a proxy' do
        it 'should use a proxy address and port' do
          request = HTTParty::Request.new(Net::HTTP::Get, 'https://foobar.com',
            :http_proxyaddr => '1.2.3.4', :http_proxyport => 8080)
          http = request.send(:http)
          http.proxy_address.should == '1.2.3.4'
          http.proxy_port.should == 8080
        end

        it 'should use a proxy user and password when provided' do
          request = HTTParty::Request.new(Net::HTTP::Get, 'https://foobar.com',
            :http_proxyaddr => '1.2.3.4', :http_proxyport => 8080,
            :http_proxyuser => 'user', :http_proxypass => 'pass')
          http = request.send(:http)
          http.proxy_user.should == 'user'
          http.proxy_pass.should == 'pass'
        end
      end
    end

    context "when setting timeout" do
      it "does nothing if the timeout option is a string" do
        http = mock("http", :null_object => true)
        http.should_not_receive(:open_timeout=)
        http.should_not_receive(:read_timeout=)
        Net::HTTP.stub(:new => http)

        request = HTTParty::Request.new(Net::HTTP::Get, 'https://foobar.com', {:timeout => "five seconds"})
        request.send(:http)
      end

      it "sets the timeout to 5 seconds" do
        @request.options[:timeout] = 5
        @request.send(:http).open_timeout.should == 5
        @request.send(:http).read_timeout.should == 5
      end
    end
  end

  describe '#format_from_mimetype' do
    it 'should handle text/xml' do
      ["text/xml", "text/xml; charset=iso8859-1"].each do |ct|
        @request.send(:format_from_mimetype, ct).should == :xml
      end
    end

    it 'should handle application/xml' do
      ["application/xml", "application/xml; charset=iso8859-1"].each do |ct|
        @request.send(:format_from_mimetype, ct).should == :xml
      end
    end

    it 'should handle text/json' do
      ["text/json", "text/json; charset=iso8859-1"].each do |ct|
        @request.send(:format_from_mimetype, ct).should == :json
      end
    end

    it 'should handle application/json' do
      ["application/json", "application/json; charset=iso8859-1"].each do |ct|
        @request.send(:format_from_mimetype, ct).should == :json
      end
    end

    it 'should handle text/javascript' do
      ["text/javascript", "text/javascript; charset=iso8859-1"].each do |ct|
        @request.send(:format_from_mimetype, ct).should == :json
      end
    end

    it 'should handle application/javascript' do
      ["application/javascript", "application/javascript; charset=iso8859-1"].each do |ct|
        @request.send(:format_from_mimetype, ct).should == :json
      end
    end

    it "returns nil for an unrecognized mimetype" do
      @request.send(:format_from_mimetype, "application/atom+xml").should be_nil
    end

    it "returns nil when using a default parser" do
      @request.options[:parser] = lambda {}
      @request.send(:format_from_mimetype, "text/json").should be_nil
    end
  end

  describe 'parsing responses' do
    it 'should handle xml automatically' do
      xml = %q[<books><book><id>1234</id><name>Foo Bar!</name></book></books>]
      @request.options[:format] = :xml
      @request.send(:parse_response, xml).should == {'books' => {'book' => {'id' => '1234', 'name' => 'Foo Bar!'}}}
    end

    it 'should handle json automatically' do
      json = %q[{"books": {"book": {"name": "Foo Bar!", "id": "1234"}}}]
      @request.options[:format] = :json
      @request.send(:parse_response, json).should == {'books' => {'book' => {'id' => '1234', 'name' => 'Foo Bar!'}}}
    end

    it 'should handle yaml automatically' do
      yaml = "books: \n  book: \n    name: Foo Bar!\n    id: \"1234\"\n"
      @request.options[:format] = :yaml
      @request.send(:parse_response, yaml).should == {'books' => {'book' => {'id' => '1234', 'name' => 'Foo Bar!'}}}
    end

    it "should include any HTTP headers in the returned response" do
      @request.options[:format] = :html
      response = stub_response "Content"
      response.initialize_http_header("key" => "value")

      @request.perform.headers.should == { "key" => ["value"] }
    end

    describe 'with non-200 responses' do
      context "3xx responses" do
        it 'returns a valid object for 304 not modified' do
          stub_response '', 304
          resp = @request.perform
          resp.code.should == 304
          resp.body.should == ''
          resp.should be_nil
        end

        it "redirects if a 300 contains a location header" do
          redirect = stub_response '', 300
          redirect['location'] = 'http://foo.com/foo'
          ok = stub_response('<hash><foo>bar</foo></hash>', 200)
          @http.stub!(:request).and_return(redirect, ok)
          response = @request.perform
          response.request.base_uri.to_s.should == "http://foo.com"
          response.request.path.to_s.should == "http://foo.com/foo"
          response.request.uri.request_uri.should == "/foo"
          response.request.uri.to_s.should == "http://foo.com/foo"
          response.should == {"hash" => {"foo" => "bar"}}
        end

        it "redirects if a 300 contains a relative location header" do
          redirect = stub_response '', 300
          redirect['location'] = '/foo/bar'
          ok = stub_response('<hash><foo>bar</foo></hash>', 200)
          @http.stub!(:request).and_return(redirect, ok)
          response = @request.perform
          response.request.base_uri.to_s.should == "http://api.foo.com"
          response.request.path.to_s.should == "/foo/bar"
          response.request.uri.request_uri.should == "/foo/bar"
          response.request.uri.to_s.should == "http://api.foo.com/foo/bar"
          response.should == {"hash" => {"foo" => "bar"}}
        end

        it "handles multiple redirects and relative location headers on different hosts" do
          @request = HTTParty::Request.new(Net::HTTP::Get, 'http://test.com/redirect', :format => :xml)
          FakeWeb.register_uri(:get, "http://test.com/redirect", :status => [300, "REDIRECT"], :location => "http://api.foo.com/v2")
          FakeWeb.register_uri(:get, "http://api.foo.com/v2", :status => [300, "REDIRECT"], :location => "/v3")
          FakeWeb.register_uri(:get, "http://api.foo.com/v3", :body => "<hash><foo>bar</foo></hash>")
          response = @request.perform
          response.request.base_uri.to_s.should == "http://api.foo.com"
          response.request.path.to_s.should == "/v3"
          response.request.uri.request_uri.should == "/v3"
          response.request.uri.to_s.should == "http://api.foo.com/v3"
          response.should == {"hash" => {"foo" => "bar"}}
        end

        it "returns the HTTParty::Response when the 300 does not contain a location header" do
          net_response = stub_response '', 300
          HTTParty::Response.should === @request.perform
        end
      end

      it 'should return a valid object for 4xx response' do
        stub_response '<foo><bar>yes</bar></foo>', 401
        resp = @request.perform
        resp.code.should == 401
        resp.body.should == "<foo><bar>yes</bar></foo>"
        resp['foo']['bar'].should == "yes"
      end

      it 'should return a valid object for 5xx response' do
        stub_response '<foo><bar>error</bar></foo>', 500
        resp = @request.perform
        resp.code.should == 500
        resp.body.should == "<foo><bar>error</bar></foo>"
        resp['foo']['bar'].should == "error"
      end
    end
  end

  it "should not attempt to parse empty responses" do
    [204, 304].each do |code|
      stub_response "", code

      @request.options[:format] = :xml
      @request.perform.should be_nil
    end
  end

  it "should not fail for missing mime type" do
    stub_response "Content for you"
    @request.options[:format] = :html
    @request.perform.should == 'Content for you'
  end

  describe "a request that redirects" do
    before(:each) do
      @redirect = stub_response("", 302)
      @redirect['location'] = '/foo'

      @ok = stub_response('<hash><foo>bar</foo></hash>', 200)
    end

    describe "once" do
      before(:each) do
        @http.stub!(:request).and_return(@redirect, @ok)
      end

      it "should be handled by GET transparently" do
        @request.perform.should == {"hash" => {"foo" => "bar"}}
      end

      it "should be handled by POST transparently" do
        @request.http_method = Net::HTTP::Post
        @request.perform.should == {"hash" => {"foo" => "bar"}}
      end

      it "should be handled by DELETE transparently" do
        @request.http_method = Net::HTTP::Delete
        @request.perform.should == {"hash" => {"foo" => "bar"}}
      end

      it "should be handled by PUT transparently" do
        @request.http_method = Net::HTTP::Put
        @request.perform.should == {"hash" => {"foo" => "bar"}}
      end

      it "should be handled by HEAD transparently" do
        @request.http_method = Net::HTTP::Head
        @request.perform.should == {"hash" => {"foo" => "bar"}}
      end

      it "should be handled by OPTIONS transparently" do
        @request.http_method = Net::HTTP::Options
        @request.perform.should == {"hash" => {"foo" => "bar"}}
      end

      it "should keep track of cookies between redirects" do
        @redirect['Set-Cookie'] = 'foo=bar; name=value; HTTPOnly'
        @request.perform
        @request.options[:headers]['Cookie'].should match(/foo=bar/)
        @request.options[:headers]['Cookie'].should match(/name=value/)
      end

      it 'should update cookies with rediects' do
        @request.options[:headers] = {'Cookie'=> 'foo=bar;'}
        @redirect['Set-Cookie'] = 'foo=tar;'
        @request.perform
        @request.options[:headers]['Cookie'].should match(/foo=tar/)
      end

      it 'should keep cookies between rediects' do
        @request.options[:headers] = {'Cookie'=> 'keep=me'}
        @redirect['Set-Cookie'] = 'foo=tar;'
        @request.perform
        @request.options[:headers]['Cookie'].should match(/keep=me/)
      end

      it 'should make resulting request a get request if it not already' do
        @request.http_method = Net::HTTP::Delete
        @request.perform.should == {"hash" => {"foo" => "bar"}}
        @request.http_method.should == Net::HTTP::Get
      end

      it 'should not make resulting request a get request if options[:maintain_method_across_redirects] is true' do
        @request.options[:maintain_method_across_redirects] = true
        @request.http_method = Net::HTTP::Delete
        @request.perform.should == {"hash" => {"foo" => "bar"}}
        @request.http_method.should == Net::HTTP::Delete
      end
    end

    describe "infinitely" do
      before(:each) do
        @http.stub!(:request).and_return(@redirect)
      end

      it "should raise an exception" do
        lambda { @request.perform }.should raise_error(HTTParty::RedirectionTooDeep)
      end
    end
  end

  describe "#handle_deflation" do
    context "context-encoding" do
      before do
        @request.options[:format] = :html
        @last_response = mock()
        @last_response.stub!(:body).and_return('')
      end

      it "should inflate the gzipped body with content-encoding: gzip" do
        @last_response.stub!(:[]).with("content-encoding").and_return("gzip")
        @request.stub!(:last_response).and_return(@last_response)
        Zlib::GzipReader.should_receive(:new).and_return(StringIO.new(''))
        @request.last_response.should_receive(:delete).with('content-encoding')
        @request.send(:handle_deflation)
      end

      it "should inflate the gzipped body with content-encoding: x-gzip" do
        @last_response.stub!(:[]).with("content-encoding").and_return("x-gzip")
        @request.stub!(:last_response).and_return(@last_response)
        Zlib::GzipReader.should_receive(:new).and_return(StringIO.new(''))
        @request.last_response.should_receive(:delete).with('content-encoding')
        @request.send(:handle_deflation)
      end

      it "should inflate the deflated body" do
        @last_response.stub!(:[]).with("content-encoding").and_return("deflate")
        @request.stub!(:last_response).and_return(@last_response)
        Zlib::Inflate.should_receive(:inflate).and_return('')
        @request.last_response.should_receive(:delete).with('content-encoding')
        @request.send(:handle_deflation)
      end
    end
  end

  context "with POST http method" do
    it "should raise argument error if query is not a hash" do
      lambda {
        HTTParty::Request.new(Net::HTTP::Post, 'http://api.foo.com/v1', :format => :xml, :query => 'astring').perform
      }.should raise_error(ArgumentError)
    end
  end

  describe "argument validation" do
    it "should raise argument error if basic_auth and digest_auth are both present" do
      lambda {
        HTTParty::Request.new(Net::HTTP::Post, 'http://api.foo.com/v1', :basic_auth => {}, :digest_auth => {}).perform
      }.should raise_error(ArgumentError, "only one authentication method, :basic_auth or :digest_auth may be used at a time")
    end

    it "should raise argument error if basic_auth is not a hash" do
      lambda {
        HTTParty::Request.new(Net::HTTP::Post, 'http://api.foo.com/v1', :basic_auth => ["foo", "bar"]).perform
      }.should raise_error(ArgumentError, ":basic_auth must be a hash")
    end

    it "should raise argument error if digest_auth is not a hash" do
      lambda {
        HTTParty::Request.new(Net::HTTP::Post, 'http://api.foo.com/v1', :digest_auth => ["foo", "bar"]).perform
      }.should raise_error(ArgumentError, ":digest_auth must be a hash")
    end
  end
end

