package Bio::Das;

use strict;
use Carp 'croak';

use URI::URL;
use URI::Escape qw(uri_escape uri_unescape);
use HTTP::Request::Common;
use LWP::UserAgent;

use Bio::Das::Util;  # for rearrange()
use Bio::Das::Segment;
use Bio::Das::Stylesheet;
use Bio::Das::Source;
use constant FORCE_GET=> 0;

#use overload '""' => 'toString';

use vars qw($VERSION @ISA %VALID_TYPE);
@ISA       = qw();
$VERSION = '0.17';

*source = \&dsn;

%VALID_TYPE = map {$_=>1} qw(dsn entry_points dna resolve 
			     types features link stylesheet);

sub new {
  my $class = shift;
  my ($server,$dsn) = rearrange([qw(server dsn)],@_);
  return bless {
		server => $server,
		dsn    => $dsn,
		debug  => 0,
	       },$class;
}

# return base url for server (unchecked)
sub server {
  my $self = shift;
  my $d = $self->{server};
  $self->{server} = shift if @_;
  $d;
}

# return the last error
sub error {
  my $self = shift;
  my $d = $self->{error};
  $self->{error} = shift if @_;
  $d;
}

sub debug {
  my $self = shift;
  my $d = $self->{debug};
  $self->{debug} = shift if @_;
  $d;
}

# return symbolic data source (unchecked)
sub dsn {
  my $self = shift;
  my $d = $self->{dsn};
  $self->{dsn} = shift if @_;
  $d;
}

# return an LWP user agent
sub agent {
  my $self = shift;
  return $self->{agent} ||= LWP::UserAgent->new;
}

# construct base url
sub base {
  my $self = shift;
  my $b = $self->server;
  $b .= '/' . $self->dsn if $self->dsn;
  $b;
}

# construct a DAS request
sub request_url {
  my $self = shift;
  my $type = lc shift or croak 'usage: request($type [,@param])';
  croak "Invalid request type $type" unless $VALID_TYPE{lc $type};
  my $url = URI::URL->new(join '/',$self->base,$type);
  $url->query(shift) if @_;
  return $url;
}

# get a request
sub request {
  my $self = shift;
  my $type = shift or die "Usage: request(\$type)";
  my $url = $self->request_url($type);

  if (my $args = shift) { # flatten
    my @args;
    for my $p (keys %$args) {
      if (ref($args->{$p})) {
	push @args,map { $p=>$_ } @{$args->{$p}};
      } else {
	push @args,$p,$args->{$p};
      }
    }

    return POST($url=>\@args);  # arguments will be POSTed

    if (FORCE_GET) {
      my @pairs;
      while (@args) {
	my $key   = shift @args;
	my $value = shift @args;
	next unless defined $value;
	$value ||= '';
	$key   ||= '';
	push @pairs,"$key=$value";
      }
      my $query_string = join ';',@pairs;
      $url->query($query_string);
      return GET($url);
    }
  } else {
    return GET($url);
  }
}

# Issue a request, return XML.
# Optionally, pass content to subroutine
sub do_request {
  my $self = shift;
  my $type   = shift;              # the type of the request comes first
  my ($parser,$chunk,$other) = rearrange([['parse','parser'],'chunk'],@_);

  my $request = ref($other) ? $self->request($type,$other) : $self->request($type);
  warn "Request:\n",$request->as_string,"\n" if $self->debug;

  my $ua = $self->agent;

  my $reply;
  if ($parser && $parser->can('parsesub')) {
    $chunk ||= 4096;
    $reply = $ua->request($request,$parser->parsesub,$chunk);
    $parser->parsedone;
    $self->error($reply->message) if $reply->is_error;
    my ($status_code) = $reply->header('x-das-status') =~ /(\d+)/;
    return $self->error("An error occurred, das status code ".$reply->header('x-das-status')) 
       unless $status_code == 200;
    return $reply->is_success;
  } else {
    $reply = $ua->request($request);
    $self->error($reply->message) if $reply->is_error;
    return $reply->content;
  }
}

sub _dna        { shift->do_request('dna',@_) }
sub _features   { shift->do_request('features',@_) }
sub _sources    { shift->do_request('dsn',@_) }
sub _entry_points { shift->do_request('entry_points',@_) }
sub _types      { shift->do_request('types',@_) }
sub _link       { shift->do_request('link',@_) }
sub _stylesheet { shift->do_request('stylesheet',@_) }

# return a new Bio::Das::Segment object
sub segment {
  my $self = shift;
  my ($sequence,$refseq,$start,$stop,$offset,$length);

  # handle a few shortcut cases
  if (@_ == 1) {
    # 1) Bio::Das->new($das_segment)
    if (ref($_[0]) && $_[0]->isa('Bio::RangeI')) {
      $sequence  = shift;
      $start     = $sequence->start;
      $stop      = $sequence->stop;
    } else {
      $refseq    = shift;
    }

  } else {

    ($sequence,$refseq,$start,$stop,$offset,$length) =
      rearrange(  [
		   ['seq','segment'],
		   ['ref','refseq'],
		   'start',
		   ['stop','end'],
		   'offset',
		   'length',
		  ],
		@_);
  }

  # play games with offset and length
  $start = $offset+1        if defined $offset;
  $stop   = $start+$length-1 if defined $length;

  # we're asked here to clone the segment, possibly using a
  # different start and stop boundary
  return $self->segment(-refseq=>$sequence->refseq,
			-start => $start,
			-stop  => $stop) if $sequence;

  return Bio::Das::Segment->new($self,$refseq,$start,$stop);
}

sub entry_points {
  my $self = shift;
  return Bio::Das::Segment->entry_points($self);
}

sub stylesheet {
  my $self = shift;
  return Bio::Das::Stylesheet->new($self);
}

sub sources {
  my $self = shift;
  return Bio::Das::Source->sources($self);
}

sub types {
  my $self = shift;
  Bio::Das::Segment->new($self)->types;
}

1;
__END__

=head1 NAME

Bio::Das - Interface to Distributed Annotation System

=head1 SYNOPSIS

  use Bio::Das;

  # contact a DAS server using the "elegans" data source
  my $das      = Bio::Das->new('http://www.wormbase.org/db/das' => 'elegans');

  # fetch a segment
  my $segment  = $das->segment(-ref=>'CHROMOSOME_I',-start=>10_000,-stop=>20_000);

  # get features and DNA from segment
  my @features = $segment->features;
  my $dna      = $segment->dna;

  # find out what data sources are available:
  my $db       = Bio::Das->new('http://www.wormbase.org/db/das')
  my @sources  $db->sources;

  # select a source
  $db->dsn($sources[1]);

  # find out what feature types are available
  my @types       = $db->types;

  # get the stylesheet
  my $stylesheet  = $db->stylesheet;

  # get the entry points
  my @entry_poitns = $db->entry_points;

=head1 DESCRIPTION

Bio::Das provides access to genome sequencing and annotation databases
that export their data in Distributed Annotation System (DAS) format.
This system is described at http://biodas.org.

The components of the Bio::Das class hierarchy are:

=over 4

=item Bio::Das

This class performs I/O with the DAS server, and is responsible for
generating Bio::Das::Segment, Bio::Das::Stylesheet, and
Bio::Das::Source objects.

=item Bio::Das::Segment

This class encapsulates information about a named segment of the
genome.  Segments are generated by Bio::Das, and in turn are
responsible for generating Bio::Das::Segment::Feature objects.
Bio::Das::Segment implements the Bio::RangeI interface.

=item Bio::Das::Segment::Feature

This is a subclass of Bio::Das::Segment, and provides information
about an annotated genomic feature.  In addition to implementing
Bio::RangeI, this class implements the Bio::SeqFeatureI interface.

=item Bio::Das::Segment::GappedAlignment

This is a subclass of Bio::Das::Segment::Feature that adds a minimal
set of methods appropriate for manipulating gapped alignments.

=item Bio::Das::Segment::Transcript

This is a subclass of Bio::Das::Segment::Feature that adds a minimal
set of methods appropriate for manipulating mRNA transcript models.

=item Bio::Das::Stylesheet

This is a class that translates Bio::Das::Segment::Feature objects
into suggested glyph names and arguments.  It represents the remote
DAS server's suggestions for how particular annotations should be
represented visually.

=item Bio::Das::Source

This class contains descriptive information about a DAS data source
(DSN).

=item Bio::Das::Parser

This is a base class used by the Bio::Das::* hierarchy that provides
methods for parsing the XML used in DAS data transmission.

=item Bio::Das::Util

Internally-used utility functions.

=back

=head2 OBJECT CREATION

The public Bio::Das constructor is new():

=over 4

=item $das = Bio::Das->new($server_url [,$dsn])

Create a new Bio::Das object, associated with the URL given in
$server_url.  The server URL uses the format described in the
specification at biodas.org, and consists of a site-specific prefix
and the "/das" path name.  For example:

 http://www.wormbase.org/db/das
 ^^^^^^^^^^^^^^^^^^^^^^^^^^
 site-specific prefix

The optional $dsn argument specifies a data source, for use by DAS
servers that provide access to several annotation sets.  A data source
is a symbolic name, such as 'human_genes'.  A list of such sources can
be obtained from the server by using the sources() method.  Once set,
the data source can be examined or changed with the dsn() method.

=back

=head2 OBJECT METHODS

Once created, the Bio::Das object provides the following methods:

=over 4

=item @sources = $das->sources

Return a list of data sources available from this server.  This is one
of the few methods that can be called before setting the data source.

=item $segment = $das->segment($id)

=item $segment = $das->segment(-ref => $reference [,@args]);

The segment() method returns a new Bio::Das::Segment object, which can
be queried for information related to a sequence segment.  There are
two forms of this call.  In the single-argument form, you pass
segment() an ID to be used as the reference sequence.  Sequence IDs
are server-specific (some servers will accept genbank accession
numbers, others more complex IDs such as Locus:unc-9).  The method
will return a Bio::Das::Segment object containing a region of the
genomic corresponding to the ID.

Instead of a segment ID, you may use a previously-created
Bio::Das::Segment object, in which case a copy of the segment will be
returned to you.  You can then adjust its start and end positions.

In the multiple-argument form, you pass a series of argument/value
pairs:

  Argument   Value                   Default
  --------   -----                   -------

  -ref       Reference ID            none
  -segment   Bio::Das::Segment obj   none
  -start     Starting position       1
  -stop      Ending position         length of ref ID
  -offset    Starting position       0
             (0-based)
  -length    Length of segment       length of ref ID

The B<-ref> argument is required, and indicates the ID of the genomic
segment to retrieve.  B<-segment> is optional, and can be used to use
a previously-created Bio::Das::Segment object as the reference point
instead.  If both arguments are passed, B<-segment> supersedes
B<-ref>.

B<-start> and B<-end> indicate the start and stop of the desired
genomic segment, relative to the reference ID.  If not provided, they
default to the start and stop of the reference segment.  These
arguments use 1-based indexing, so a B<-start> of 0 positions the
segment one base before the start of the reference.

B<-offset> and B<-length> arguments are alternative ways to indicate a
segment using zero-based indexing.  It is probably not a good to mix
the two calling styles, but if you do, be aware that B<-offset>
supersedes B<-start> and B<-length> supersedes B<-stop>.

Note that no checking of the validity of the passed reference ID will
be performed until you call the segment's features() or dna() methods.

=item @entry_points = $das->entry_points

The entry_points() method returns an array of Bio::Das::Segment
objects that have been designated "entry points" by the DAS server.
Also see the Bio::Das::Segment->entry_points() method.

=item $stylesheet = $das->stylesheet

Return the stylesheet from the remote DAS server.  The stylesheet
contains suggestions for the visual format for the various features
provided by the server and can be used to translate features into
glyphs.  The object returned is a Bio::Das::Stylesheet object.

=item @types = $das->types

This method returns a list of all the annotation feature types served
by the DAS server.  The return value is an array of Bio::Das::Type
objects.

=back

=head2 ACCESSORS

A number of less-frequently used methods are accessors for the
Bio::Das object, and can be used to examine and change its settings.
Called with no arguments, the accessors return the current value of
the setting.  Called with a single argument, the accessors change the
setting and return its previous value.

  Accessor         Description
  --------         -----------
  server()         Get/set the URL of the server
  error()          Get/set the last error message
  dsn()            Get/set the DSN of the data source
  source()         An alias for dsn()

=head2 INTERNAL METHODS

The methods in this section are published methods that are used
internally.  They may be useful for subclassing.

=over 4

=item $agent = $das->agent

Return the LWP::UserAgent that will be used for communicating with the
DAS server.

=item $url = $das->base

Return a URL resulting from combining the server URL with the DSN.

=item $request = $das->request($query_type [,@args])

Create a LWP::Request object for use in communicating with the DAS
server.  The B<$query_type> argument is the type of the request, and may be
one of "dsn", "entry_points", "dna", "resolve", "types", "features",
"link", and "stylesheet".The optional B<@args> array contains a series
of name/value pairs to pass to the DAS server.

=item $url = $das->request_url($query_type)

Creates a URI::URL object corresponding to the indicated query type.

=item $data = $das->do_request($query_type [,@args][,-parser=>$parser] [,-chunk=>$chunksize]

This method invokes the DAS query indicated by B<$query_type> using
the arguments indicated by B<@args>, and returns the resulting XML
document.  For example, to get the raw XML output from a DAS server
using the dna request on the M7 clone segment from 1 to 30,000, you
could call do_request() like this:

 $dna_xml = $das->do_request('dna',-ref=>'M7',-start=>1,-stop=>30000);

Query arguments correspond to the CGI parameters listed for each
request in the DAS specification, with the exception that they are
preceded by a hyphen.

You may provide a B<-parser> argument, in which case the downloaded
XML is passed to the indicated parser for interpretation.  The
B<-chunk> argument controls the size of the chunks passed to the
parser.  Parsers must be objects the implement the interface described
in L<Bio::Das::Parser>.

=back

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
