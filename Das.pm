package Bio::Das;
# $Id: Das.pm,v 1.23 2003/12/29 23:20:32 lstein Exp $

# prototype parallel-fetching Das

use strict;
use Bio::Root::Root;
use Bio::Das::HTTP::Fetch;
use Bio::Das::TypeHandler;     # bring in the handler for feature type ontologies
use Bio::Das::Request::Dsn;    # bring in dsn  parser
use Bio::Das::Request::Types;  # bring in type parser
use Bio::Das::Request::Dnas;
use Bio::Das::Request::Features;
use Bio::Das::Request::Feature2Segments;
use Bio::Das::Request::Entry_points;
use Bio::Das::Request::Stylesheet;
use Bio::Das::FeatureIterator;
use Bio::Das::Util 'rearrange';
use Carp;

use IO::Socket;
use IO::Select;

use vars '$VERSION';
use vars '@ISA';
@ISA     = 'Bio::Root::Root';
$VERSION = 0.93;
*fetch_feature_by_name = \&get_feature_by_name;
my @COLORS = qw(cyan blue red yellow green wheat turquoise orange);

sub new {
  my $package = shift;

  # compatibility with 0.18 API
  my ($timeout,$auth_callback,$url,$dsn,$oldstyle_api,$aggregators);
  my @p = @_;

  if (@p >= 1 && $p[0] =~ /^http/) {
    ($url,$dsn,$aggregators) = @p;
  } elsif ($p[0] =~ /^-/) {  # named arguments
    ($url,$dsn,$aggregators,$timeout,$auth_callback) = rearrange(['source',
								  'dsn',
								  ['aggregators','aggregator'],
								  'timeout',
								  'auth_callback'],
								 @p);
  } else {
    ($timeout,$auth_callback) = @p;
  }

  $oldstyle_api = defined $url;

  my $self = bless {
		    'sockets'   => {},   # map socket to Bio::Das::HTTP::Fetch objects
		    'timeout'   => $timeout,
		    default_server => $url,
		    default_dsn    => $dsn,
		    oldstyle_api   => $oldstyle_api,
		    aggregators    => [],
	       },$package;
  $self->auth_callback($auth_callback) if defined $auth_callback;
  if ($aggregators) {
    my @a = ref($aggregators) eq 'ARRAY' ? @$aggregators : $aggregators;
    $self->add_aggregator($_) foreach @a;
  }
  return $self;
}

sub name {
  my $url =   shift->default_url;
  # $url =~ tr/+-//d;
  $url;
}

sub add_aggregator {
  my $self       = shift;
  my $aggregator = shift;
  warn "aggregator = $aggregator" if $self->debug;

  my $list = $self->{aggregators} ||= [];
  if (ref $aggregator) { # an object
    @$list = grep {$_->get_method ne $aggregator->get_method} @$list;
    push @$list,$aggregator;
  }

  elsif ($aggregator =~ /^(\w+)\{([^\/\}]+)\/?(.*)\}$/) {
    my($agg_name,$subparts,$mainpart) = ($1,$2,$3);
    my @subparts = split /,\s*/,$subparts;
    my @args = (-method    => $agg_name,
		-sub_parts => \@subparts);
    push @args,(-main_method => $mainpart) if $mainpart;
    warn "making an aggregator with (@args), subparts = @subparts" if $self->debug;
    require Bio::DB::GFF::Aggregator;
    push @$list,Bio::DB::GFF::Aggregator->new(@args);
  }

  else {
    my $class = "Bio::DB::GFF::Aggregator::\L${aggregator}\E";
    eval "require $class";
    $self->throw("Unable to load $aggregator aggregator: $@") if $@;
    push @$list,$class->new();
  }
}

sub aggregators {
  my $self = shift;
  my $d = $self->{aggregators};
  if (@_) {
    $self->clear_aggregators;
    $self->add_aggregator($_) foreach @_;
  }
  return unless $d;
  return @$d;
}

sub clear_aggregators { shift->{aggregators} = [] }

sub default_dsn {
  my $self = shift;
  my $d    = $self->{default_dsn};
  $self->{default_dsn} = shift if @_;
  $d;
}

sub default_server { shift->{default_server} }

sub oldstyle_api   { shift->{oldstyle_api}   }

sub default_url {
  my $self = shift;
  return unless $self->default_server && $self->default_dsn;
  return join '/',$self->default_server,$self->default_dsn;
}

sub auth_callback{
  my $self = shift;
  if(defined $_[0]){
    croak "Authentication callback routine to set is not a reference to code" 
      unless ref $_[0] eq "CODE";
  }

  my $d    = $self->{auth_callback};
  $self->{auth_callback} = shift if @_;
  $d;
}

sub proxy {
  my $self = shift;
  my $d    = $self->{proxy};
  $self->{proxy} = shift if @_;
  $d;
}

sub timeout {
  my $self = shift;
  my $d = $self->{timeout};
  $self->{timeout} = shift if @_;
  $d;
}

sub debug {
  my $self = shift;
  my $d = $self->{debug};
  $self->{debug} = shift if @_;
  $d;
}

# call with list of base names
# will return a list of DSN objects
sub dsn {
  my $self = shift;
  return $self->default_dsn(@_) if $self->oldstyle_api;
  return $self->_dsn(@_);
}

sub _dsn {
  my $self = shift;
  my @requests = $_[0]=~/^-/ ? Bio::Das::Request::Dsn->new(@_)
                             : map { Bio::Das::Request::Dsn->new($_) } @_;
  $self->run_requests(\@requests);
}

sub sources {
  my $self = shift;
  my $default_server = $self->default_server or return;
  return $self->_dsn($default_server);
}

sub entry_points {
  my $self = shift;
  my ($dsn,$ref,$callback) =  rearrange([['dsn','dsns'],
					 ['ref','refs','refseq','seq_id','name'],
					 'callback',
					],@_);
  $dsn ||= $self->default_url;
  croak "must provide -dsn argument" unless $dsn;
  my @dsn = ref $dsn ? @$dsn : $dsn;
  my @request;
  for my $dsn (@dsn) {
    push @request,Bio::Das::Request::Entry_points->new(-dsn    => $dsn,
						       -ref    => $ref,
						       -callback => $callback);
  }
  $self->run_requests(\@request);
}

sub stylesheet {
  my $self = shift;
  my ($dsn,$callback) =  rearrange([['dsn','dsns'],
				    'callback',
				   ],@_);
  $dsn ||= $self->default_url;
  croak "must provide -dsn argument" unless $dsn;
  my @dsn = ref $dsn ? @$dsn : $dsn;
  my @request;
  for my $dsn (@dsn) {
    push @request,Bio::Das::Request::Stylesheet->new(-dsn    => $dsn,
						     -callback => $callback);
  }
  $self->run_requests(\@request);
}


# call with list of DSN objects, and optionally list of segments and categories
sub types {
  my $self = shift;
  my ($dsn,$segments,$categories,$enumerate,$callback) = rearrange([['dsn','dsns'],
								    ['segment','segments'],
								    ['category','categories'],
								    'enumerate',
								    'callback',
								   ],@_);
  $dsn ||= $self->default_url;
  croak "must provide -dsn argument" unless $dsn;
  my @dsn = ref $dsn ? @$dsn : $dsn;
  my @request;
  for my $dsn (@dsn) {
    push @request,Bio::Das::Request::Types->new(-dsn        => $dsn,
						-segment    => $segments,
						-categories => $categories,
						-enumerate   =>$enumerate,
						-callback    => $callback,
					       );
  }
  $self->run_requests(\@request);
}

# call with list of DSN objects, and a list of one or more segments
sub dna {
  my $self = shift;
  my ($dsn,$segments,$callback) = rearrange([['dsn','dsns'],
					     ['segment','segments'],
					     'callback',
					    ],@_);
  $dsn ||= $self->default_url;
  croak "must provide -dsn argument" unless $dsn;
  my @dsn = ref $dsn && ref $dsn eq 'ARRAY' ? @$dsn : $dsn;
  my @request;
  for my $dsn (@dsn) {
    push @request,Bio::Das::Request::Dnas->new(-dsn        => $dsn,
					       -segment    => $segments,
					       -callback    => $callback);
  }
  $self->run_requests(\@request);
}

# 0.18 API - fetch by segment
sub segment {
  my $self = shift;
  my ($ref,$start,$stop,$version) = rearrange([['ref','name'],'start',['stop','end'],'version'],@_);
  my $dsn = $self->default_url;
  if (defined $start && defined $stop) {
    return Bio::Das::Segment->new($ref,$start,$stop,$version,$self,$dsn);
  } else {
    my @segments;
    my $request = Bio::Das::Request::Features->new(-dsn        => $dsn,
						   -das        => $self,
						   -segments   => $ref,
						   -type       => 'NULL',
						   -segment_callback => sub {
						     push @segments,shift;
						   });
    $self->run_requests([$request]);
    return @segments;
  }
}

# 0.18 API - fetch by feature name - returns a set of Bio::Das::Segment objects
sub get_feature_by_name {
  my $self = shift;
  my ($name, $class, $ref, $base_start, $stop) 
       = $self->_rearrange([qw(NAME CLASS REF START END)],@_);
  my $dsn = $self->default_url;
  my $request = Bio::Das::Request::Feature2Segments->new(-class   => $class,
							 -dsn     => $dsn,
							 -feature => $name,
							 -das     => $self,
							);
  $self->run_requests([$request]);
  return $request->results;
}

# gbrowse compatibility
sub refclass { 'Segment' }

# call with list of DSNs, and optionally list of segments and categories
sub features {
  my $self = shift;
  my ($dsn,$segments,$types,$categories,
      $fcallback,$scallback,$feature_id,$group_id,$iterator) 
                                 = rearrange([['dsn','dsns'],
			                      ['segment','segments'],
					      ['type','types'],
					      ['category','categories'],
					      ['callback','feature_callback'],
					      'segment_callback',
                                              'feature_id',
                                              'group_id',
					      'iterator',
					     ],@_);

  croak "must provide -dsn argument" unless $dsn;
  my @dsn = ref $dsn && ref $dsn eq 'ARRAY' ? @$dsn : $dsn;

  # handle types
  my @aggregators;
  my $typehandler = Bio::Das::TypeHandler->new;
  my $typearray   = $typehandler->parse_types($types);
  for my $a ($self->aggregators) {
    unshift @aggregators,$a if $a->disaggregate($typearray,$typehandler);
  }

  my @types = map {$_->[0]} @$typearray;
  my @request;
  for my $dsn (@dsn) {
    push @request,Bio::Das::Request::Features->new(
                           -dsn              => $dsn,
						-segments         => $segments,
						-types            => \@types,
						-categories       => $categories,
						-feature_callback => $fcallback  || undef,
						-segment_callback => $scallback  || undef,
                           -feature_id       => $feature_id || undef,
                           -group_id         => $group_id   || undef,
                           );
  }
  my @results = $self->run_requests(\@request);
  $self->aggregate(\@aggregators,
		   $results[0]->can('results') ? \@results : [\@results],
		   $typehandler) if @aggregators && @results;

  return Bio::Das::FeatureIterator->new(\@results) if $iterator;
  return wantarray ? @results : $results[0];
}

sub search_notes { }

sub aggregate {
  my $self = shift;
  my ($aggregators,$featarray,$typehandler) = @_;
  my @f;

  foreach (@$featarray) {
    if (ref($_) eq 'ARRAY') { # 0.18 API
      push @f,$_;
    } elsif ($_->is_success) { # current API
      push @f,scalar $_->results;
    }
  }
  return unless @f;
  for my $f (@f) {
    for my $a (@$aggregators) {
      $a->aggregate($f,$typehandler);
    }
  }
}

sub add_pending {
  my $self    = shift;
  my $fetcher = shift;
  $self->{sockets}{$fetcher->socket} = $fetcher;
}

sub remove_pending {
  my $self    = shift;
  my $fetcher = shift;
  delete $self->{sockets}{$fetcher->socket};
}

sub run_requests {
  my $self     = shift;
  my $requests = shift;
  my $auth_callback = $self->auth_callback();

  for my $request (@$requests) {
    my $fetcher = Bio::Das::HTTP::Fetch->new(
                            -request => $request,
					        -headers => {'Accept-encoding' => 'gzip'},
					        -proxy   => $self->proxy || ''
					        ) or next;
                            
    $fetcher->debug(1) if $self->debug;
    $self->add_pending($fetcher);
  }

  my $timeout = $self->timeout;

  # create two IO::Select objects to handle writing & reading  
  my $readers = IO::Select->new;
  my $writers = IO::Select->new;

  for my $fetcher (values %{$self->{sockets}}) {
    my $socket = $fetcher->socket;
    $writers->add($socket);
  }

  my $timed_out;
  while ($readers->count or $writers->count) {
    my ($readable,$writable) = IO::Select->select($readers,$writers,undef,$timeout);

    ++$timed_out && last unless $readable || $writable;

    foreach (@$writable) {                      # handle is ready for writing
      my $fetcher = $self->{sockets}{$_};       # recover the HTTP fetcher
      my $result = $fetcher->send_request();      # try to send the request
      $readers->add($_) if $result;             # send successful, so monitor for reading
      $fetcher->request->error($fetcher->error())
	  unless $result;                           # copy the error message
      $writers->remove($_);                     # and remove from list monitored for writing
    }

    foreach (@$readable) {                      # handle is ready for reading
      my $fetcher = $self->{sockets}{$_};       # recover the HTTP object
      my $result = $fetcher->read;              # read some data
      if($fetcher->error
	     && $fetcher->error =~ /^401\s/
	     && $self->auth_callback()){              # Don't give up if given authentication challenge
         $self->authenticate($fetcher);         # The result will automatically appear, as fetcher contains request reference
      }
      unless ($result) {                        # remove if some error occurred
	$fetcher->request->error($fetcher->error) unless defined $result;
	$readers->remove($_);
	delete $self->{sockets}{$_};
      }
    }
  }

  # handle timeouts
  if ($timed_out) {
    while (my ($sock,$f) = each %{$self->{sockets}}) { # list of still-pending requests
      $f->request->error('timeout');
      $readers->remove($sock);
      $writers->remove($sock);
      close $sock;
    }
  }

  delete $self->{sockets};
  if ($self->oldstyle_api()) {
    return unless $requests->[0]->is_success();
    return wantarray ? $requests->[0]->results : ($requests->[0]->results)[0];
  }
  return wantarray ? @$requests : $requests->[0];
}

# The callback routine used below for authentication must accept three arguments: 
#    the fetcher object, the realm for authentication, and the iteration
# we are on.  A return of undef means that we should stop trying this connection (e.g. cancel button
# pressed, or x number of iterations tried), otherwise a two element array (not a reference to an array)
# should be returned with the username and password in that order.
# I assume if you've called autheniticate, it's because you've gotten a 401 error. 
# Otherwise this does not make sense.
# There is also no caching of authentication done.  I suggest the callback do this, so
# the user isn't asked 20 times for the same name and password.

sub authenticate($$$){
  my ($self, $fetcher) = @_;
  my $callback = $self->auth_callback;

  return undef unless defined $callback;

  $self->{auth_iter} = {} if not defined $self->{auth_iter};

  my ($realm) = $fetcher->error =~ /^\S+\s+'(.*)'/; 

  return if $self->{auth_iter}->{$realm} < 0;  # Sign that we've given up, don't try again

  my ($user, $pass) = &$callback ($fetcher, $realm, ++($self->{auth_iter}->{$realm}));

  if(not defined $user){  #Give up, denote with negative iteration value
    $self->{auth_iter}->{$realm} = -1;
  }

  # Reuse request (no need to manipulate result lists) with new authentication built into dsn
  my $request = $fetcher->request;
  $self->remove_pending($fetcher);
  # How do we clean up the old fetcher,which is no longer needed?
  $fetcher->request->dsn->set_authentication($user, $pass);
  return $self->run_requests([$request]);
}

1;

__END__


=head1 NAME

Bio::Das - Interface to Distributed Annotation System

=head1 SYNOPSIS

  use Bio::Das;

  # PARALLEL API
  # create a new DAS agent with a timeout of 5 sec
  my $das = Bio::Das->new(5);

  # fetch features from wormbase server spanning two segments on chromosome I
  my $response = $das->features(-dsn     => 'http://www.wormbase.org/db/das/elegans',
				-segment => ['CHROMOSOME_I:1,10000',
                                             'CHROMOSOME_I:10000,20000'
                                            ]
			       );
  die $response->error unless $response->is_success;
  my $results = $response->results;
  for my $segment (keys %$results) {
      my @features = @{$results->{$segment}};
      print join ' ',$seg,@features,"\n";
  }

  # alternatively, invoke with a callback:
  $das->features(-dsn     => 'http://www.wormbase.org/db/das/elegans',
	  	 -segment => ['CHROMOSOME_I:1,10000',
                              'CHROMOSOME_I:10000,20000'
                             ],
		 -callback => sub { my $feature = shift;
                                    my $segment = $feature->segment;
                                    my ($start,$end) = ($feature->start,$feature->end);
                                    print "$segment => $feature ($start,$end)\n";
                                  }
			       );

   # SERIALIZED API
   my $das = Bio::Das->new(-source => 'http://www.wormbase.org/db/das',
                           -dsn    => 'elegans',
                           -aggregators => ['primary_transcript','clone']);
   my $segment  = $das->segment('Chr1');
   my @features = $segment->features;
   my $dna      = $segment->dna;

=head1 DESCRIPTION

Bio::Das provides access to genome sequencing and annotation databases
that export their data in Distributed Annotation System (DAS) format
version 1.5.  This system is described at http://biodas.org.  Both
unencrypted (http:) and SSL-encrypted (https:) DAS servers are
supported.  (To run SSL, you will need IO::Socket::SSL and Net::SSLeay
installed).

The components of the Bio::Das class hierarchy are:

=over 4

=item Bio::Das

This class performs I/O with the DAS server, and is responsible for
generating DAS requests.  At any time, multiple requests to different
DAS servers can be running simultaneously.

=item Bio::Das::Request

This class encapsulates a request to a particular DAS server, as well
as the response that is returned from it.  Methods allow you to return
the status of the request, the error message if any, and the data
results.

=item Bio::Das::Segment

This encapsulates information about a segment on the genome, and
contains information on its start, end and length.

=item Bio::Das::Feature

This provides information on a particular feature of a
Bio::Das::Segment, such as its type, orientation and score.

=item Bio::Das::Type

This class contains information about a feature's type, and is a
holder for an ontology term.

=item Bio::Das::DSN

This class contains information about a DAS data source.

=item Bio::Das::Stylesheet

This class contains information about the stylesheet for a DAS source.

=back

=head2 OBJECT CREATION

The public Bio::Das constructor is new():

=over 4

=item $das = Bio::Das->new(-timeout       => $timeout,
                           -auth_callback => $authentication_callback,
                           -aggregators   => \@aggregators)

Create a new Bio::Das object, with the indicated timeout and optional
callback for authentication.  The timeout will be used to decide when
a server is not responding and to return a "can't connect" error.  Its
value is in seconds, and can be fractional (most systems will provide
millisecond resolution).  The authentication callback will be invoked
if the remote server challenges Bio::Das for authentication credentials.

Aggregators are used to build multilevel hierarchies out of the raw
features in the DAS stream.  For a description of aggregators, see
L<Bio::DB::GFF>, which uses exactly the same aggregator system as
Bio::Das.

If successful, this method returns a Bio::Das object.

=item $das = Bio::Das->new($timeout [,$authentication_callback])

Shortcut for the above.

=item $das = Bio::Das->new(-source => $url, -dsn => $dsn, -aggregators=>\@aggregators);

This is the serialized DAS API for clients that will be accessing a
single server exclusively.  The arguments are the URL of the remote
DAS server (ending with the "das" component of the URL), the remote
data source, and the list of aggregators to load. 

=item $das = Bio::Das->new('http://das.server/cgi-bin/das',$dsn,$aggregators)

Shortcut for the above.

=back

=head2 ACCESSOR METHODS

Once created, the Bio::Das object provides the following accessor methods:

=over 4

=item $proxy = $das->proxy([$new_proxy])

Get or set the proxy to use for accessing indicated servers.  Only
HTTP and HTTPS proxies are supported at the current time.

=item $callback = $das->auth_callback([$new_callback])

Get or set the callback to use when authentication is required.  See
the section "Authentication" for more details.

=item $timeout = $das->timeout([$new_timeout])

Get or set the timeout for slow servers.

=item $debug  = $das->debug([$debug_flag])

Get or set a flag that will turn on verbose debugging messages.

=back

=head2 DATA FETCHING METHODS

The following methods accept a series of arguments, contact the
indicated DAS servers, and return a series of response objects from
which you can learn the status of the request and fetch the results.

=over 4

=item @response = $das->dsn(@list_of_urls)

The dsn() method accepts a list of DAS server URLs and returns a list
of the DSNs provided by each server.

The request objects will indicate whether each request was successful
via their is_success() methods.  For your convenience, the request
object is automagically stringified into the requested URL.  For example:

 my $das = Bio::Das->new(5);  # timeout of 5 sec
 my @response = $das->dsn('http://stein.cshl.org/perl/das',
  			 'http://genome.cse.ucsc.edu/cgi-bin/das',
			 'http://user:pass@www.wormbase.org/db/das',
			 'https://euclid.well.ox.ac.uk/cgi-bin/das',
			);

 for my $url (@response) {
   if ($url->is_success) {
     my @dsns = $url->results;
     print "$url:\t\n";
     foreach (@dsns) {
       print "\t",$_->url,"\t",$_->description,"\n";
     }
   } else {
     print "$url: ",$url->error,"\n";
   }
 }

Each element in @dsns is a L<Bio::Das::DSN> object that can be used
subsequently in calls to features(), types(), etc.  For example, when
this manual page was written, the following was the output of this
script.

 http://stein.cshl.org/perl/das/dsn:	
 http://stein.cshl.org/perl/das/chr22_transcripts	This is the EST-predicted transcripts on...

 http://servlet.sanger.ac.uk:8080/das:	
 http://servlet.sanger.ac.uk:8080/das/ensembl1131   The latest Ensembl database	

 http://genome.cse.ucsc.edu/cgi-bin/das/dsn:	
 http://genome.cse.ucsc.edu/cgi-bin/das/hg8	Human Aug. 2001 Human Genome at UCSC
 http://genome.cse.ucsc.edu/cgi-bin/das/hg10	Human Dec. 2001 Human Genome at UCSC
 http://genome.cse.ucsc.edu/cgi-bin/das/mm1	Mouse Nov. 2001 Human Genome at UCSC
 http://genome.cse.ucsc.edu/cgi-bin/das/mm2	Mouse Feb. 2002 Human Genome at UCSC
 http://genome.cse.ucsc.edu/cgi-bin/das/hg11	Human April 2002 Human Genome at UCSC
 http://genome.cse.ucsc.edu/cgi-bin/das/hg12	Human June 2002 Human Genome at UCSC
 http://user:pass@www.wormbase.org/db/das/dsn:	
 http://user:pass@www.wormbase.org/db/das/elegans     This is the The C. elegans genome at CSHL
 
 https://euclid.well.ox.ac.uk/cgi-bin/das/dsn:	
 https://euclid.well.ox.ac.uk/cgi-bin/das/dicty	        Test annotations
 https://euclid.well.ox.ac.uk/cgi-bin/das/elegans	C. elegans annotations on chromosome I & II
 https://euclid.well.ox.ac.uk/cgi-bin/das/ensembl	ensembl test annotations
 https://euclid.well.ox.ac.uk/cgi-bin/das/test	        Test annotations
 https://euclid.well.ox.ac.uk/cgi-bin/das/transcripts	transcripts test annotations

Notice that the DSN URLs always have the format:

 http://www.wormbase.org/db/das/$DSN
 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

In which the ^^^ indicated part is identical to the server address.

=item @response = $das->types(-dsn=>[$dsn1,$dsn2],@other_args)

The types() method asks the indicated servers to return the feature
types that they provide.  Arguments are name-value pairs:

  Argument      Description
  --------      -----------

  -dsn          A DAS DSN, as returned by the dsn() call.  You may
                also provide a simple string containing the DSN URL.
                To make the types() request on multiple servers, pass an
                array reference containing the list of DSNs.

  -segment      (optional) An array ref of segment objects.  If provided, the
                list of types will be restricted to the indicated segments.

  -category     (optional) An array ref of type categories.  If provided,
                the list of types will be restricted to the indicated
                categories.

  -enumerate    (optional) If true, the server will return the count of
                each time.

  -callback     (optional) Specifies a subroutine to be invoked on each
                type object received.

Segments have the format: "seq_id:start,end".  If successful, the
response results() method will return a list of Bio::Das::Type
objects.

If a callback is specified, the code ref will be invoked with two
arguments.  The first argument is the Bio::Das::Segment object, and
the second is an array ref containing the list of types present in
that segment.  If no -segment argument was provided, then the callback
will be invoked once with a dummy segment (a version, but no seq_id,
start or end), and an arrayref containing the types.  If a callback is
specified, then the @response array will return the status codes for
each request, but invoking results() will return empty.

=item @response = $das->entry_points(-dsn=>[$dsn1,$dsn2],@other_args)

Invoke an entry_points request.  Arguments are name-value pairs:

  Argument      Description
  --------      -----------

  -dsn          A DAS DSN, as returned by the dsn() call.  You may
                also provide a simple string containing the DSN URL.
                To make the types() request on multiple servers, pass an
                array reference containing the list of DSNs.

  -callback     (optional) Specifies a subroutine to be invoked on each
                segment object received.

If a callback is specified, then the @response array will contain the
status codes for each request, but the results() method will return
empty.

Successful responses will return a set of Bio::Das::Segment objects.

=item @response = $das->features(-dsn=>[$dsn1,$dsn2],@other_args)

Invoke a features request to return a set of Bio::Das::Feature
objects.  The -dsn argument is required, and may point to a single DSN
or to an array ref of several DSNs.  Other arguments are optional:

  Argument      Description
  --------      -----------

  -dsn          A DAS DSN, as returned by the dsn() call.  You may
                also provide a simple string containing the DSN URL.
                To make the types() request on multiple servers, pass an
                array reference containing the list of DSNs.

  -segment      A single segment, or an array ref containing
                several segments.  Segments are either Bio::Das::Segment
                objects, or strings of the form "seq_id:start,end".

  -type         (optional) A single feature type, or an array ref containing
                several feature types.  Types are either Bio::Das::Type
                objects, or plain strings.

  -category     (optional) A single feature type category, or an array ref
                containing several categories.  Category names are described
                in the DAS specification.

  -feature_id   (optional) One or more feature IDs.  The server will return
                the list of segment(s) that contain these IDs.  You will
                need to check with the data provider for the proper format
                of the IDs, but the style "class:ID" is common.  This will
                be replaced in the near future by LSID-style IDs.  Also note
                that only servers compliant with the 1.52 version of the
                spec will honor this.

  -group_id     (optional) One or more group IDs.  The server will return
                the list of segment(s) that contain these IDs.  You will
                need to check with the data provider for the proper format
                of the IDs, but the style "class:ID" is common.  This will
                be replaced in the near future by LSID-style IDs.  Also note
                that only servers compliant with the 1.52 version of the
                spec will honor this.

  -callback     (optional) Specifies a subroutine to be invoked on each
                Bio::Das::Feature object received.

  -segment_callback (optional) Specifies a subroutine to be invoked on each
                    Segment that is retrieved.

  -iterator     (optional)  If true, specifies that an iterator should be
                returned rather than a list of features.

If a callback (-callback or -segment_callback) is specified, then the
@response array will contain the status codes for each request, but
results() will return empty.

The subroutine specified by -callback will be invoked every time a
feature is encountered.  The code will be passed a single argument
consisting of a Bio::Das::Feature object.  You can find out what
segment this feature is contained within by executing the object's
segment() method.

The subroutine specified by -segment_callback will be invoked every
time one of the requested segments is finished.  It will be invoked
with two arguments consisting of the name of the segment and an array
ref containing the list of Bio::Das::Feature objects contained within
the segment.

If both -callback and -segment_callback are specified, then the first
subroutine will be invoked for each feature, and the second will be
invoked on each segment *AFTER* the segment is finished.  In this
case, the segment processing subroutine will be passed an empty list
of features.

Note, if the -segment argument is not provided, some servers will
provide all the features in the database.

The -iterator argument is a true/false flag.  If true, the call will
return a L<Bio::Das::FeatureIterator> object.  This object implements
a single method, next_seq(), which returns the next Feature.  Example:

   $iterator = $das->features(-dsn=>[$dsn1,$dsn2],-iterator=>1);
   while (my $feature = $iterator->next_seq) {
     print "got a ",$feature->method,"\n";
   }

=item @response = $das->dna(-dsn=>[$dsn1,$dsn2],@other_args)

Invoke a features request to return a DNA string.  The -dsn argument
is required, and may point to a single DSN or to an array ref of
several DSNs.  Other arguments are optional:

  Argument      Description
  --------      -----------

  -dsn          A DAS DSN, as returned by the dsn() call.  You may
                also provide a simple string containing the DSN URL.
                To make the types() request on multiple servers, pass an
                array reference containing the list of DSNs.

  -segment      (optional) A single segment, or an array ref containing
                several segments.  Segments are either Bio::Das::Segment
                objects, or strings of the form "seq_id:start,end".

  -callback     (optional) Specifies a subroutine to be invoked on each
                DNA string received.

-dsn, -segment and -callback have the same meaning that they do in
similar methods.

=back

=head2 add_aggregator

NOTE: Aggregator support is currently experimental and is provided for
compatibility with Generic Genome Browser.

 Title   : add_aggregator
 Usage   : $db->add_aggregator($aggregator)
 Function: add an aggregator to the list
 Returns : nothing
 Args    : an aggregator
 Status  : public

This method will append an aggregator to the end of the list of
registered aggregators.  Three different argument types are accepted:

  1) a Bio::DB::GFF::Aggregator object -- will be added
  2) a string in the form "aggregator_name{subpart1,subpart2,subpart3/main_method}"
         -- will be turned into a Bio::DB::GFF::Aggregator object (the /main_method
        part is optional).
  3) a valid Perl token -- will be turned into a Bio::DB::GFF::Aggregator
        subclass, where the token corresponds to the subclass name.

=cut

=head2 aggregators

 Title   : aggregators
 Usage   : $db->aggregators([@new_aggregators]);
 Function: retrieve list of aggregators
 Returns : list of aggregators
 Args    : a list of aggregators to set (optional)
 Status  : public

This method will get or set the list of aggregators assigned to
the database.  If 1 or more arguments are passed, the existing
set will be cleared.

=cut

=head2 clear_aggregators

 Title   : clear_aggregators
 Usage   : $db->clear_aggregators
 Function: clears list of aggregators
 Returns : nothing
 Args    : none
 Status  : public

This method will clear the aggregators stored in the database object.
Use aggregators() or add_aggregator() to add some back.

=cut

=head2 Fetching results

- documentation pending -

=head2 Authentication

- documentation pending -

=head1 AUTHOR

Lincoln Stein <lstein@cshl.org>.

Copyright (c) 2001 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=head1 SEE ALSO

L<Bio::Das::Segment>, L<Bio::Das::Type>, L<Bio::Das::Stylesheet>,
L<Bio::Das::Source>, L<Bio::RangeI>

=cut
