package Bio::Das::HTTP::Fetch;
# file: Fetch.pm
# $Id: Fetch.pm,v 1.9 2002/08/31 23:32:53 lstein Exp $

use strict;
use IO::Socket qw(:DEFAULT :crlf);
use Bio::Das::Util;
use Bio::Das::Request;
use MIME::Base64;  # For HTTP authenication encoding
use Carp 'croak';
use Errno 'EINPROGRESS','EWOULDBLOCK';
use vars '$VERSION';

$VERSION = '1.1';
my $ERROR = '';   # for errors that occur before we create the object

use constant READ_UNIT => 1024 * 5;  # 5K read units


# notes:
# -request: an object implements the following methods:
#            ->url()            return the url for the request
#            ->method()         return the method for the request ('auto' allowed)
#            ->args()           return the args for the request
#            ->headers($hash)   do something with the HTTP headers (canonicalized)
#            ->start_body()     the body is starting, so do initialization
#            ->body($string)    a piece of the body text
#            ->finish_body()    the body has finished, so do cleanup
#            ->error()          set an error message
#
#  the request should return undef to abort the fetch and cause immediate cleanup
#
# -request: a Bio::Das::Request object
#
# -headers: hashref whose keys are HTTP headers and whose values are scalars or array refs
#           required headers will be added
#
sub new {
  my $pack = shift;
  my ($url,$request,$headers,$proxy,$debug) = rearrange(['url',
							 'request',
							 'headers',
							 'proxy',
							 'debug',
							],@_);
  croak "Please provide a -request argument" unless $request;

  # parse URL, return components
  my $dest = $proxy || $request->url;
  my ($mode,$host,$port,$path,$user,$pass) = $pack->parse_url($dest);
  croak "invalid url: $url\n" unless $host;

  # no headers to send by default
  $headers ||= {};

  # connect to remote host in nonblocking way
  my $sock = $pack->connect($mode,$host,$port);
  unless ($sock) {
    $request->error($pack->error);
    return;
  }

  $path = $request->url if $proxy;

  # save the rest of our information
  return bless {
                # ("waiting", "reading header", "reading body", or "parsing body")
                status            => 'waiting',
                socket            => $sock,
                path              => $path,
		request           => $request,
		outgoing_headers  => $headers,
                url               => $url,
                user              => $user,
                pass              => $pass,
                host              => $host,
                # rather than encoding for every request
                auth              => ($user ? encode_base64("$user:$pass") : ""),
		mode              => $mode, #http vs https
		debug             => $debug,
		incoming_header   => undef,  # none yet
               },$pack;
}

# this will return the socket associated with the object
sub socket   { shift->{socket} }
sub path     { shift->{path}   }
sub request  { shift->{request} }
sub outgoing_args    { shift->request->args    }
sub outgoing_headers { shift->{outgoing_headers} }
sub url              { shift->{url}              }  # mostly for debugging purposes
sub user             { shift->{user}             }  # mostly for debugging purposes
sub pass             { shift->{pass}             }  # mostly for debugging purposes
sub host             { shift->{host}             }  # mostly for debugging purposes
sub auth             { shift->{auth}             }
sub incoming_header  { shift->{incoming_header}  }  # buffer for header data
sub mode {
  my $self = shift;
  my $d    = $self->{mode};
  $self->{mode} = shift if @_;
  $d;
}
sub method   {
  my $self = shift;
  my $meth = uc $self->request->method;
  return 'GET' unless $meth;
  if ($meth eq 'AUTO') {
    return $self->outgoing_args ? 'POST' : 'GET';
  }
  return $meth;
}
sub status   {
  my $self = shift;
  my $d    = $self->{status};
  $self->{status} = shift if @_;
  $d;
}
sub debug {
  my $self = shift;
  my $d    = $self->{debug};
  $self->{debug} = shift if @_;
  $d;
}

# this will return the results from the request
sub results {
  my $self = shift;
  my $request = $self->request or return;
  $request->results;
}

# very basic URL-parsing sub
sub parse_url {
  my $self = shift;
  my $url = shift;
  my ($ssl,$hostent,$path) = $url =~ m!^http(s?)://([^/]+)(/?[^\#]*)! or return;
  $path ||= '/';

  my ($user,$pass); 
  ($user, $hostent) = $hostent =~ /^(.*@)?(.*)/;
  ($user, $pass) = split(':',substr($user,0,length($user)-1));
  if($pass and not $ssl){warn "Using password in unencrypted URI against RFC #2396 recommendation"}

  my ($host,$port) = split(':',$hostent);
  my ($mode,$defport);
  if ($ssl) {
    $mode='https';
    $defport=443;
  } else {
    $mode='http';
    $defport=80;
  }
  return ($mode,$host,$port||$defport,$path,$user,$pass);
}

# this is called to connect to remote host
sub connect {
  my $pack = shift;
  my ($mode,$host,$port,$user,$pass) = @_;
  my $sock;
  if ($mode eq 'https') {
    load_ssl();
    $sock = IO::Socket::SSL->new(Proto => 'tcp',
				 Type => SOCK_STREAM,
				 SSL_use_cert => 0,
				 SSL_verify_mode => 0x00)
  } else {
    $sock = IO::Socket::INET->new(Proto => 'tcp',
				  Type  => SOCK_STREAM)
  }

  return unless $sock;
  $sock->blocking(0);
  my $host_ip = inet_aton($host) or return $pack->error("$host: Unknown host");
  my $addr = sockaddr_in($port,$host_ip);
  my $result = $sock->IO::Socket::INET::connect($addr);  # don't allow SSL to do its handshake yet!
  return $sock if $result;  # return the socket if connected immediately
  return $sock if $! == EINPROGRESS;  # or if it's in progress
  return;                             # return undef on other errors
}

# this is called to send the HTTP request
sub send_request {
  my $self = shift;
  warn "$self->send_request()" if $self->debug;

  die "not in right state, expected state 'waiting' but got '",$self->status,"'"
    unless $self->status eq 'waiting';

  unless ($self->{socket}->connected) {
    $! = $self->{socket}->sockopt(SO_ERROR);
    return $self->error("couldn't connect: $!") ;
  }

  # if we're in https mode, then we need to complete the
  # SSL handshake at this point
  if ($self->mode eq 'https') {
    $self->complete_ssl_handshake($self->{socket}) || return $self->error($self->{socket}->error);
  }

  $self->{formatted_request} ||= $self->format_request;

  warn "SENDING $self->{formatted_request}" if $self->debug;

  # Send the header and request.  Note that we have to respect
  # both IO::Socket EWOULDBLOCK errors as well as the dodgy
  # IO::Socket::SSL "SSL wants a write" error.
  my $bytes = syswrite($self->{socket},$self->{formatted_request});
  if (!$bytes) {
    return $self->status if $! == EWOULDBLOCK;  # still trying
    return $self->status if $self->{socket}->errstr =~ /SSL wants a write/;
    return $self->error("syswrite(): $!");
  }
  if ($bytes >= length $self->{formatted_request}) {
    $self->status('reading header');
  } else {
    substr($self->{formatted_request},0,$bytes) = '';  # truncate and try again
  }
  $self->status;
}

# this is called when the socket is ready to be read
sub read {
  my $self = shift;
  my $stat = $self->status;
  return $self->read_header if $stat eq 'reading header';
  return $self->read_body   if $stat eq 'reading body'
                            or $stat eq 'parsing body';
}

# read the header through to the $CRLF$CRLF (blank line)
# return a true value for 200 OK
sub read_header {
  my $self = shift;

  my $bytes = sysread($self->{socket},$self->{header},READ_UNIT,length $self->{header});
  if (!defined $bytes) {
    return $self->status if $! == EWOULDBLOCK;
    return $self->status if $self->{socket}->errstr =~ /SSL wants a read/;
  }
  return $self->error("Unexpected close before header read") unless $bytes > 0;

  # have we found the CRLF yet?
  my $i = rindex($self->{header},"$CRLF$CRLF");
  return $self->status unless $i >= 0;  # no, so keep waiting

  # found the header
  # If we have stuff after the header, then process it
  my $header     = substr($self->{header},0,$i);
  my $extra_data = substr($self->{header},$i+4);

  my ($status_line,@other_lines) = split $CRLF,$header;
  my ($stat_code,$stat_msg) = $status_line =~ m!^HTTP/1\.[01] (\d+) (.+)!;

  # If unauthorized, capture the realm for the authentication 
  if($stat_code == 401){
    # Can't use do_headers, Request will barf on lack of X-Das version
    if(my ($line) = grep /^WWW-Authenticate:\s+/, @other_lines){
      my ($scheme,$realm) = $line =~ /^\S+:\s+(\S+)\s+realm="(.*?)"/;  
      if($scheme ne 'Basic'){
        $self->error("Authenciation scheme required ($scheme) is not the supported 'Basic'");
      }
      # The realm is actually allowed to be blank according to RFC #1945 BNF
      return $self->error("$stat_code '$realm' realm needs proper authentication");  
    }
  }

  # On non-200 status codes return an error
  return $self->error("$stat_code $stat_msg") unless $stat_code == 200;

  # handle header
  $self->do_headers(@other_lines) || return;

  $self->status('reading body');
  $self->do_body($extra_data) || return if length $extra_data;

  undef $self->{header};  # don't need header now
  return $self->status;
}

sub read_body {
  my $self = shift;
  my $data;
  my $result = sysread($self->{socket},$data,READ_UNIT);

  # call do_body() if we read data
  if ($result) {
    $self->do_body($data) or return;
    return $self->status;
  }

  # call request's finish_body() method on normal EOF
  elsif (defined $result) {
    $self->request->finish_body or return if $self->request;
    return 0;
  }

  # sysread() returned undef, so error out
  else {
    return $self->status if $! == EWOULDBLOCK;  # well, this is OK
    return $self->status if $self->{socket}->errstr =~ /SSL wants a write/;
    my $errmsg = "read error: $!";
    if (my $cb = $self->request) {
      $cb->finish_body;
      $cb->error($errmsg);
    }
    return $self->error($errmsg);
  }

}

# this generates the appropriate GET or POST request
sub format_request {
  my $self    = shift;
  my $method  = $self->method;
  my $args    = $self->format_args;
  my $path    = $self->path;
  my $auth    = $self->auth;

  my @additional_headers = ('User-agent' => join('/',__PACKAGE__,$VERSION));
  push @additional_headers, ('Authorization'  => "Basic $auth") if $auth;
  push @additional_headers,('Content-length' => length $args,
			    'Content-type'   => 'application/x-www-form-urlencoded')
    if $args && $method eq 'POST';

  # probably don't want to do this
  $method = 'GET' if $method eq 'POST' && !$args;

  # there is an automatic CRLF pair at the bottom of headers, so don't add it
  my $headers = $self->format_headers(@additional_headers);

  return join CRLF,"$method $path HTTP/1.0",$headers,$args;
}

# this creates the CGI request string
sub format_args {
  my $self = shift;
  my @args;
  if (my $a = $self->outgoing_args) {
    foreach (keys %$a) {
      next unless defined $a->{$_};
      my $key    = escape($_);
      my @values = ref($a->{$_}) eq 'ARRAY' ? map { escape($_) } @{$a->{$_}}
	                                    : $a->{$_};
      push @args,"$key=$_" foreach (grep {$_ ne ''} @values);
    }
  }
  return join ';',@args;
}

# this creates the request headers
sub format_headers {
  my $self    = shift;
  my @additional_headers = @_;

  # this order allows overriding
  my %headers = (@additional_headers,%{$self->outgoing_headers});

  # clean up the headers
  my %clean_headers;
  for my $h (keys %headers) {  
    next if $h =~ /\s/;  # no whitespace allowed - invalid header
    my @values = ref($headers{$h}) eq 'ARRAY' ? @{$headers{$h}}
                                                : $headers{$h};
    foreach (@values) { s/[\n\r\t]/ / }        # replace newlines and tabs with spaces
    $clean_headers{canonicalize($h)} = \@values;  # canonicalize
  }

  my @lines;
  for my $k (keys %clean_headers) {
    for my $v (@{$clean_headers{$k}}) {
      push @lines,"$k: $v";
    }
  }

  return join CRLF,@lines,'';
}

sub escape {
  my $s = shift;
  $s =~ s/([^a-zA-Z0-9_.-])/uc sprintf("%%%02x",ord($1))/eg;
  $s;
}

sub canonicalize {
  my $s = shift;
  $s = ucfirst lc $s;
  $s =~ s/(-\w)/uc $1/eg;
  $s;
}

sub do_headers {
  my $self = shift;
  my @header_lines = @_;

  # split 'em into a hash, merge duplicates with semicolons
  my %headers;
  foreach (@header_lines) {
    my ($header,$value) = /^(\S+): (.+)$/ or next;
    $headers{canonicalize($header)} = $headers{$header} ? "; $value" : $value;
  }

  if (my $request = $self->request) {
    $request->headers(\%headers) || return $self->error($request->error);
  }
  1;
}

# this is called to read the body of the message and act on it
sub do_body {
  my $self = shift;
  my $data = shift;

  my $request = $self->request or return;
  if ($self->status eq 'reading body') { # transition
    $request->start_body or return;
    $self->status('parsing body');
  }

  warn "parsing()...." if $self->debug;
  return $request->body($data);
}

# warn in case of error and return undef
sub error {
  my $self = shift;
  if (@_) {
    unless (ref $self) {
      $ERROR = "@_";
      return;
    }
    warn "$self->{url}: ",@_ if $self->debug;
    $self->{error} = "@_";
    return;
  } else {
    return ref($self) ? $self->{error} : $ERROR;
  }
}

sub load_ssl {
  eval 'require IO::Socket::SSL' or croak "Must have IO::Socket::SSL installed to use https: urls: $@";

  # cheating a bit -- IO::Socket::SSL doesn't have this function, and needs to!
  eval <<'END' unless defined &IO::Socket::SSL::pending;
sub IO::Socket::SSL::pending {
  my $self = shift;
  my $ssl  = ${*$self}{'_SSL_object'};
  return Net::SSLeay::pending($ssl); # *
}
END

}

sub complete_ssl_handshake {
  my $self = shift;
  my $sock = shift;
  $sock->blocking(1);  # handshake requires nonblocking i/o
  my $result = $sock->connect_SSL($sock);
  $sock->blocking(0);
}

# necessary to define these methods so that IO::Socket::INET objects will act like
# IO::Socket::SSL objects.
sub IO::Socket::INET::pending { 0     }
sub IO::Socket::INET::errstr  { undef }


1;
